---
name: handle-pr-comments
description: "Fetch PR review comments, categorize them, and respond. Code-fix comments get implemented, questions get answered, approvals get logged. After fixes, run quality checks and push. Triggers on: 'handle PR comments', 'address review comments', 'fix PR feedback', 'PR #N comments', '/handle-pr-comments', 'レビュー対応', 'PRコメント対応'."
user-invokable: true
argument-hint: "<pr-number>"
---

# Handle PR Comments — Review Comment Workflow

Fetch and classify PR review comments and respond to them systematically.

## Execution Context

This skill is used in the following contexts:

| Context | Commit/push responsibility |
|---------|----------------------------|
| **Standalone execution** (running `/handle-pr-comments` directly) | This skill itself performs the commit/push |
| **Used inside spec-implement** | review-worker invokes this skill; commit/push is review-worker's responsibility |

## Input

- **pr**: PR number (e.g., `#123`, `123`) or PR URL. Received as the first argument of `$ARGS`.

**Invocation form**: `/handle-pr-comments <pr-number>` (e.g., `/handle-pr-comments 123` or `/handle-pr-comments #123`)

If the argument is missing, ask the user for the PR number.

**Input normalization**: First take the first argument of `$ARGS` as `PR_INPUT`. If `PR_INPUT` is in URL form (e.g., `https://github.com/.../pull/123`), extract the PR number with `gh pr view "$PR_INPUT" --json number -q .number`. If in `#123` form, strip the leading `#`. Use the normalized numeric PR number as `{number}` in subsequent steps.

## Prerequisite Checks (MANDATORY)

Run the following checks in order. If any fails, **STOP** and provide remediation guidance.

### 1. gh CLI Authentication

```bash
gh auth status
```

On failure: prompt "Run `gh auth login` to authenticate the GitHub CLI" and STOP.

### 2. Repository Check

```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
# Split owner and repo for API calls
OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"
```

On failure: prompt "Run this from the root directory of a GitHub repository" and STOP.

Subsequent API calls (`gh api repos/${OWNER}/${REPO_NAME}/...`) use `${OWNER}/${REPO_NAME}`.

### 3. PR State Check

```bash
gh pr view {number} --json state,headRefName,baseRefName -q '.state'
```

- `MERGED` -> warn "This PR has already been merged" and confirm whether to continue
- `CLOSED` -> warn "This PR is closed" and confirm whether to continue

### 4. Working Tree Check

```bash
git status --porcelain
```

If uncommitted changes exist: prompt "The working tree has uncommitted changes. Commit or stash them and rerun" and STOP.

### 5. Switch to PR Branch

```bash
gh pr checkout {number}
```

On switch failure: display the branch name and instruct manual checkout.

## Procedure

### 1. Fetch PR Information and Comments

Use the following API calls to fetch all PR comments and resolved state.

```bash
# PR meta info
gh pr view {number} --json title,body,state,headRefName,baseRefName,reviewDecision,reviews,comments

# Inline code comments (review comments)
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/comments --paginate

# Review summary
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/reviews --paginate

# Resolved status of review threads (via GraphQL)
gh pr view {number} --json reviewThreads -q '.reviewThreads[] | {id: .id, isResolved: .isResolved, comments: [.comments[] | {id: .id, databaseId: .databaseId, createdAt: .createdAt, path: .path, line: .line, body: .body}]}'
```

Use the value of `${OWNER}/${REPO_NAME}` obtained and split in prerequisite check 2.

**Information to collect**:
- REST: each comment's `id`, `body`, `path` (file), `line`, `user`, `created_at`
- GraphQL (`reviewThreads`): each thread's `isResolved` and the in-thread comments' `id`, `databaseId`, `createdAt`, `path`, `line`
- Review decision status (`APPROVED`, `CHANGES_REQUESTED`, `COMMENTED`)

**Resolved judgment**: The REST API (`pulls/{number}/comments`) does not expose a thread's resolved state, so use `gh pr view --json reviewThreads`. When mapping resolved state onto REST comments, prefer the `id` / `databaseId` of the comments retrieved from the `reviewThreads` side as the primary join key. Only fall back to a composite key (`createdAt` + `path` + `line`) when those are unavailable. Never join on the `body` string alone (identical comment bodies cause mismatches).

### 2. Categorize Comments

Classify each comment into one of the following five categories.

| Category | Criterion | Action |
|----------|-----------|--------|
| **Code fix required** | Requests a concrete code change ("Change X", "Fix Y", "Remove Z") | Apply the fix |
| **Question / clarification** | "Why ...?", "What's the intent of ...?", "Is this correct?" form | Reply via comment |
| **Style / formatting** | Naming conventions, indentation, formatting, comment-addition feedback | Apply the fix |
| **Approval / LGTM** | "LGTM", "Looks good", "No issues", and similar positive comments | Record only |
| **Suggestion (optional)** | "nit:", "suggestion:", "consider:", "optional:", "if you have time" | Defer to user judgment |

**Classification rules**:
- Skip already `resolved` comments (record as handled)
- Lower priority for comments attached to `APPROVED` reviews
- If a comment fits multiple categories, adopt the higher-action category

### 2.5 Validity Verification of Feedback (MANDATORY — Do Not Blindly Trust Copilot Suggestions)

After categorization and **before drafting the response plan**, verify the validity of each comment. Machine reviewers like Copilot bot can produce false positives or over-flagging, so always read the source for confirmation following the principles below.

**Verification principles (self-contained)**:

- Responses to review feedback **must not lower existing quality assurance levels or consistency**. Do not adopt suggestions that lower quality, even if the reviewer seems plausible
- **Do not blindly trust** machine reviewer suggestions. Even seemingly reasonable feedback must be independently judged for validity by cross-checking with repository rules and the intent of existing implementation
- When unsure whether the feedback or the existing implementation is correct, **ask the user** (do not silently follow)

For each comment:

1. **Verify the target exists**: open `path:line` referenced by the comment with Read and confirm the issue actually exists there
2. **Consistency with spec / context**: check the feedback against the project's `${CLAUDE_PLUGIN_ROOT}/rules/` / `.spec-workflow/steering/*.md` (product / tech / structure) / `design.md` / intent of existing implementation. In particular, steering / rules are **prior** to the feedback in the following cases:
   - File-placement feedback ↔ File Placement Rules (P4-01) in `steering/structure.md`
   - Dependency-addition feedback ↔ "External Dependencies (Approved)" in `steering/tech.md`
   - Architecture-direction feedback ↔ Accepted ADRs in `steering/tech.md`
   - Scope-creep feedback ↔ Non-Goals in `steering/product.md`
   - Naming / style / error-handling feedback ↔ `${CLAUDE_PLUGIN_ROOT}/rules/*-style.md` / `${CLAUDE_PLUGIN_ROOT}/rules/design-principles.md`
   Feedback that contradicts steering / rules is classified as `invalid`; reply to the comment with a link to the relevant document and an explanation.
3. **Past PR resolution status**: check whether similar feedback was already addressed in merged PRs (PR description / `git log` / `CHANGELOG.md`)
4. **Three-level validity decision**:
   - `valid` — feedback is correct and should be addressed
   - `partial` — direction is right but the specific fix is problematic (handle with an alternative)
   - `invalid` — feedback is wrong (source misread, already resolved, within spec). Do not act; explain in a reply

**Decision examples**:

| Decision | Example |
|----------|---------|
| valid | "`### REQ-1.1:` heading conflicts with the `### REQ-1:` + AC comment rule" -> verify against the actual template |
| partial | "Remove `unwrap()`" -> removal direction is right, but `map_err` aligns with the design rule better than `?` |
| invalid | "Use `### REQ-N.M:` heading" -> rule is the opposite (`REQ-N:` + AC comment); feedback is incorrect |

**Handling feedback that risks quality regression**:

- If following the machine feedback risks **lowering** existing quality gates or consistency, ask the user before acting
- When in doubt, call `advisor()` for a second opinion

Merge the verification result into the Step 3 response plan and annotate each comment with `validity: valid | partial | invalid`.

### 3. Present Response Plan

Show the classification result to the user and **always get confirmation before executing**.

```
## PR #{number} Review Comment Response Plan

### Auto-handle (code fix required + style): {N} items
| # | File | Line | Reviewer | Summary | Plan |
|---|------|------|----------|---------|------|
| 1 | {path} | {line} | {user} | {summary} | {plan} |
| ... | | | | | |

### Question replies: {N} items
| # | File | Line | Reviewer | Question | Draft answer |
|---|------|------|----------|----------|--------------|
| 1 | {path} | {line} | {user} | {question} | {answer} |
| ... | | | | | |

### User decision required (suggestions): {N} items
| # | File | Line | Reviewer | Suggestion |
|---|------|------|----------|------------|
| 1 | {path} | {line} | {user} | {suggestion} |
| ... | | | | |

### Skipped (resolved / approved): {N} items

**Proceed with the plan above?**
```

Wait until the user has decided how to handle "suggestion" items and approved the plan.

### 4. Execute Comment Responses

After user approval, address comments in the following order.

#### 4.0 Comprehensive Search for Same-Kind Issues (MANDATORY)

Before addressing items, mechanically search the repository for **other instances of the same kind of issue** for each `valid` / `partial` comment. A single piece of PR-review feedback often implies that the same pattern lurks in multiple places (overall finding from pr-review-patterns.md: 35% of feedback stems from "duplicate management of the same information").

**Search techniques**:

| Feedback type | Example search query |
|---------------|----------------------|
| ID / key-name error (e.g., `N-th` -> `M-th`) | `grep -rn "N-th\|N 番目" .` to find residuals across the repo |
| Inconsistent terms / commands (e.g., `-warnaserror` vs `--warnaserror`) | grep both forms across the repo |
| Inconsistent placement (e.g., key at top-level vs nested) | `grep -rn "<key-name>" .` to check every occurrence |
| Nested fences / placeholders | grep code blocks and placeholder patterns across the repo |
| Shell robustness (e.g., assumes `jq`) | `grep -rn "jq " <directory containing scripts>` |

Fix discovered same-kind issues together in **the same PR / same commit** (splitting them out makes testing harder). Annotate the discovery counts in the Step 3 response plan to make them visible to the user:

```
### Response plan (including same-kind issues)
- N-th -> M-th fix: 1 item (original feedback) + 2 items (discovered via grep, in the same file)
```

#### 4.1 Detect Conflicting Feedback

Before starting, check for conflicting feedback:

- Conflicting feedback from multiple reviewers on the **same file / same line range**
- Opposing opinions on the **same topic** (e.g., "Split this function" vs "Keep this function as-is")

When conflicts are detected:
1. Present the conflicting comment pair to the user
2. Display each reviewer's review status (`APPROVED` / `CHANGES_REQUESTED`) as informational
3. Wait for the user's decision on which feedback to prioritize

#### 4.2 Apply Code Fixes (code fix required + style + accepted suggestions)

For each comment:

1. Read the relevant location in the target file
2. Apply the fix as the comment requests
3. Confirm the fix is correct

After all fixes are complete, proceed to the quality checks (Step 5) collectively.

#### 4.3 Reply to Questions

Post replies to each question comment via `gh api`:

```bash
# Reply to an inline comment
gh api repos/${OWNER}/${REPO_NAME}/pulls/comments/{comment_id}/replies \
  -f body="{reply body}"

# Reply on the general comment thread
gh api repos/${OWNER}/${REPO_NAME}/issues/{number}/comments \
  -f body="{reply body}"
```

#### 4.4 Self-Review (MANDATORY)

Before quality checks (Step 5) and push (Step 6), **self-review the entire post-fix diff**. Detect new inconsistencies introduced by the fix (e.g., only some files were updated and others were left behind, referenced IDs/naming are no longer aligned, comment text disagrees with implementation, etc.).

```bash
git diff "origin/{baseRefName}..HEAD"
```

Review angles:

- Comprehensive grep for same-kind patterns (does a single rename/ID change reflect everywhere?)
- Any breaking changes against existing tests or APIs
- Missed fixes / partial updates causing inconsistency with other files
- If the project has its own review checklist (e.g., `.claude/_docs/know-how/pr-review-patterns.md`), re-inspect along its categories
- If codex or other review-style plugins are enabled, take additional angles via `/codex:review` etc.

If Critical / Moderate problems are found, return to Step 4.2 for additional fixes. For Minor only, present to the user and request judgment.

**Conditions for skipping self-review**: only when the fix is extremely minor (e.g., a one-line typo) and with the user's explicit consent.

### 5. Quality Checks

Run quality checks per the project's `quality-checks.md` rule.

On quality-check failure:
1. Analyze the cause and attempt automatic fixes (max 3 times)
2. If automatic fixes do not resolve, report to the user and discuss

### 6. Commit and Push

```bash
git add {fixed files}
git commit -m "fix: address review comments — {summary of changes}

Addressed comments:
- {summary of comment 1}
- {summary of comment 2}
..."
git push
```

**Commit rules**:
- If fixes span many areas, group by relevance into multiple commits
- Each commit message states which review comments it addresses

### 7. Reply to Reviewers

Notify reviewers of completion for comments that involved code fixes:

```bash
gh api repos/${OWNER}/${REPO_NAME}/pulls/comments/{comment_id}/replies \
  -f body="Addressed. {brief description of the change}"
```

### 8. Completion Report

When all responses are done, display the summary:

```
## PR #{number} Review Comment Response Complete

### Response Summary
- Code fixes: {N} done
- Question replies: {N} done
- Style fixes: {N} done
- Suggestions: {N} ({M} adopted, {K} declined)
- Skipped: {N} (resolved / approved)

### Commits
- {commit-hash}: {commit-message}
- ...

### Quality check result: {PASS/FAIL}

### Outstanding (if any)
- {description and reason for unhandled comments}
```

## Rules

- Always present the response plan to the user and get confirmation before executing
- Escalate conflicting feedback to the user; do not decide unilaterally
- Do not re-handle already-`resolved` comments
- Lower priority for comments on `APPROVED` reviews (non-blocking)
- Confirm quality checks PASS before pushing
- Each commit message must list the review comments addressed
- Reply to comments after pushing the fix (do not reply before push)
- Do not handle PRs in `MERGED` / `CLOSED` state by default (continue only with explicit user instruction)
