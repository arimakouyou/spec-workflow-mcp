---
name: handle-issue
description: "Fetch a GitHub Issue, analyze its change scope, and route it to the appropriate workflow. Large changes go to spec workflow; trivial bug fixes are handled directly via TDD; ambiguous cases are confirmed with the user. Triggers on: 'handle issue', 'work on issue #N', 'issue #N', 'GitHub issue', 'fix issue', '/handle-issue', 'issueを対応', 'issueに取り組む'."
user-invokable: true
argument-hint: "<issue-number>"
---

# Issue Handling — GitHub Issue Workflow

Fetch and analyze a GitHub Issue and automatically route it to the optimal workflow based on the change scope.

## Input

- **issue**: Issue number (e.g., `#42`, `42`) or Issue URL. Received as the first argument of `$ARGS`.

**Invocation form**: `/handle-issue <issue-number>` (e.g., `/handle-issue 42` or `/handle-issue #42`)

If no argument is given, ask the user for the Issue number.

**Input normalization**: First, take the first argument of `$ARGS` as `ISSUE_INPUT`. If `ISSUE_INPUT` is in URL form (e.g., `https://github.com/.../issues/42`), extract the Issue number with `gh issue view "$ISSUE_INPUT" --json number -q .number`. If it is in `#42` form, strip the leading `#`. The remaining steps use the normalized numeric Issue number as `{number}`.

## Prerequisite Checks (MANDATORY)

Run the following checks in order. If any fails, **STOP** and provide remediation guidance.

### 1. gh CLI Authentication

```bash
gh auth status
```

On failure: prompt "Run `gh auth login` to authenticate the GitHub CLI" and STOP.

### 2. Repository Check

```bash
gh repo view --json nameWithOwner -q '.nameWithOwner'
```

On failure: prompt "Run this from the root directory of a GitHub repository" and STOP.

### 3. Working Tree Check

```bash
git status --porcelain
```

If uncommitted changes exist: **STOP**. Tell the user to clean the working tree with `git commit` or `git stash` and rerun. The 4B path eventually runs `/create-pr`, which requires a clean working tree as a prerequisite.

## Procedure

### 1. Fetch Issue Information

```bash
gh issue view {number} --json title,body,labels,assignees,milestone,comments,state
```

**State checks**:
- If the Issue is `CLOSED` -> warn and confirm whether to continue
- If the Issue is assigned to someone other than the current user -> warn and confirm whether to continue

**Detect related Issues/PRs**:
- Extract cross-references in `#N`, `closes #N`, `fixes #N`, `related to #N` form from the Issue body
- Present detected related Issues/PRs to the user as informational (non-blocking)

### 2. Codebase Analysis

Investigate the impact area based on the Issue content:

1. **Identify related files**: search keywords, error messages, and function names from the Issue with Grep/Glob
2. **Estimate impact range**: estimate the count of related files and modules/components that need changes
3. **Confirm test coverage**: check whether existing tests cover the related code
4. **Determine architectural impact**: judge whether new APIs, DB schema changes, or new components are needed

### 3. Change-Scope Classification (Triage)

Quantify change scope with the following scoring matrix.

| Criterion | Weight | Large (3 pts) | Medium (2 pts) | Small (1 pt) |
|-----------|--------|---------------|----------------|--------------|
| Affected file count | x3 | 6 or more files | 3-5 files | 1-2 files |
| Architectural change | x3 | New API / DB change / new component | Extension of existing API | Modification within existing code |
| Label | x2 | feature / enhancement | bug (complex) | bug (simple) |
| Requirements clarity | x2 | Ambiguous / needs discussion | Mostly clear | Reproduction steps clear |
| Test coverage | x1 | No coverage | Partial coverage | Existing tests present |

**Total score range**: 11 (minimum) - 33 (maximum)

**Routing decision**:
- **27 or more** -> **4A. Large-Change Path** (Spec Workflow)
- **18-26** -> **4C. Decision-Required Path** (user confirmation)
- **17 or less** -> **4B. Trivial Bug-Fix Path** (direct TDD)

Always display the scoring result in this format:

```
## Triage Result: Issue #{number}

| Criterion | Score | Weight | Subtotal | Rationale |
|-----------|-------|--------|----------|-----------|
| Affected file count | {1-3} | x3 | {subtotal} | {reason} |
| Architectural change | {1-3} | x3 | {subtotal} | {reason} |
| Label | {1-3} | x2 | {subtotal} | {reason} |
| Requirements clarity | {1-3} | x2 | {subtotal} | {reason} |
| Test coverage | {1-3} | x1 | {subtotal} | {reason} |

**Total**: {total}/33 -> **{path name}**
```

### 4A. Large-Change Path — Route to Spec Workflow

For large changes, write the spec first to prevent rework.

1. **Confirm branch creation**: propose branch name `feat/issue-{N}-{slug}` and get user confirmation
   - `{slug}` is generated as kebab-case from the Issue title (max 30 chars)
   - Example: `feat/issue-42-add-user-export`

2. **Create branch**:
   ```bash
   git checkout -b {branch-name}
   ```

3. **Organize Issue context**: gather:
   - Issue title and body
   - Labels and milestone
   - Codebase analysis result (affected files, architectural impact)
   - Related Issues/PRs

4. **Transition to Spec Workflow**:
   - Auto-generate spec-name as kebab-case from the Issue title
   - Load the `/spec-request-spec` skill and start immediately
   - Record the Issue URL in the "Background" section of request-spec.md
   - Pass the Issue body as the initial input for use cases

   > Load the `/spec-request-spec` skill and start immediately. Use the Issue context above as input for the request spec.

### 4B. Trivial Bug-Fix Path — Direct TDD

For clear, small bugs, fix directly with a TDD approach without writing a spec.

1. **Confirm branch creation**: propose branch name `fix/issue-{N}-{slug}` and get user confirmation
   - Example: `fix/issue-15-null-pointer-in-parser`

2. **Create branch**:
   ```bash
   git checkout -b {branch-name}
   ```

3. **RED — write a reproduction test**:
   - Author a test based on the reproduction steps in the Issue
   - Confirm the test **fails** (reproducing the bug)
   - Refer to `/tdd-skills` (or `/tdd-skills-rust` for Rust projects)

4. **GREEN — implement the minimal fix**:
   - Implement the smallest change that makes the test **pass**
   - Confirm no existing tests break

5. **REFACTOR — clean up**:
   - Improve quality of the fix (deduplication, naming, etc.)
   - Confirm tests continue to pass

6. **Quality checks**:
   - Run quality checks per the project's `quality-checks.md` rule
   - On failure, attempt fixes (up to 3 times); if unresolved, report to the user

7. **Create PR**:
   Pass the following arguments to the `/create-pr` skill to create the PR:
   - `--title "{Summary of the fix based on the Issue title}"`
   - `--closes {number}`

   > Load the `/create-pr` skill with the arguments above. The skill runs IT/E2E tests, detects UI changes, captures screenshots when applicable, and creates a PR including structured test results.

### 4C. Decision-Required Path — User Confirmation

For mid-range scores, defer to the user.

1. **Present the analysis**:
   - Triage scoring table (the format from step 3)
   - Codebase analysis summary (impact, risk)
   - Recommended path and rationale

2. **Present choices**:
   ```
   Choose one:
   A) Treat as a large change and use Spec Workflow (write spec, then implement)
   B) Treat as a trivial fix and use TDD directly
   C) Need more investigation (analyze the codebase further)
   ```

3. **Wait for the user's decision**: proceed to 4A or 4B based on the choice. For C, perform additional analysis and re-triage.

## Branch Naming Convention

| Issue type | Branch prefix | Example |
|------------|---------------|---------|
| bug | `fix/issue-{N}-{slug}` | `fix/issue-15-null-pointer-in-parser` |
| feature / enhancement | `feat/issue-{N}-{slug}` | `feat/issue-42-add-user-export` |
| Other | `fix/issue-{N}-{slug}` | `fix/issue-99-update-error-message` |

`{slug}` is the Issue title converted to kebab-case, truncated to 30 characters max.

## Rules

- Always confirm with the user before creating a branch
- If the Issue is `CLOSED`, warn and STOP unless the user explicitly continues
- If the Issue is assigned to someone else, warn and STOP unless the user explicitly continues
- When transitioning to Spec Workflow (path 4A), always record the Issue URL in request-spec.md
- For direct TDD (path 4B), only create the PR after all quality checks PASS
- Always display scoring results as a table to make rationale transparent
- Treat related Issues/PRs as informational, not as blocking requirements
