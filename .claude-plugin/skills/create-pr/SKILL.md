---
name: create-pr
description: "Create a PR with test results and UI screenshots. Runs IT/E2E tests, detects UI changes, captures screenshots, builds the PR body, then runs gh pr create. Usable standalone or via reference from other skills. Triggers on: 'create PR', 'open pull request', 'PRを作成', 'PR作成', '/create-pr'."
user-invokable: true
argument-hint: "[--title <title>] [--closes <issue-number>] [--spec <spec-name>] [--skip-tests] [--base <branch>]"
---

# Create PR — with test results and screenshots

Create a PR including test results and UI screenshots. Usable standalone or via reference from `/handle-issue` or `/spec-implement`.

## Execution Context

This skill is used in two contexts. Note that the responsibility for commit/push differs:

| Context | Commit / Push Responsibility |
|---------|------------------------------|
| **Standalone execution** (running `/create-pr` directly) | This skill itself runs commit/push |
| **Invocation from spec-implement** (via Step 10) | review-worker runs this skill. Commit/push is review-worker's responsibility |

When invoked from the 4B path of `/handle-issue`, treat it the same as standalone execution.

## Inputs

Parse the following arguments from `$ARGS`. All are optional.

| Argument | Required | Description |
|----------|:--------:|-------------|
| `--title <title>` | NO | PR title. If omitted, auto-generated from the branch name (kebab-case → space-separated, leading uppercase) |
| `--closes <issue-number>` | NO | Related Issue number. When specified, append `Closes #{number}` to the end of the PR body |
| `--spec <spec-name>` | NO | Spec name. When specified, add Spec doc links to the PR body and read results from `final-e2e-gate.md` |
| `--skip-tests` | NO | Skip test execution. Use when quality checks / Final E2E Gate already ran |
| `--base <branch>` | NO | Base branch. Auto-detected if omitted |

**Examples**:
- `/create-pr --title "Fix null pointer in parser" --closes 42`
- `/create-pr --spec user-export --skip-tests`
- `/create-pr` (no arguments — fully automated)

## Argument Parsing

Extract the following variables from the `$ARGS` string. Claude parses `$ARGS` semantically and assigns each variable.

| Variable | Argument | Default |
|----------|---------|---------|
| `TITLE_ARG` | `--title <value>` | `""` (auto-generated from branch name when omitted) |
| `CLOSES_ARG` | `--closes <number>` | `""` |
| `SPEC_ARG` | `--spec <name>` | `""` |
| `BASE_ARG` | `--base <branch>` | `""` |
| `SKIP_TESTS` | `--skip-tests` | `false` |

**Parsing rule**: For arguments whose values may contain spaces (e.g., `--title`), treat the quoted portion as a single value (e.g., `--title "Fix null pointer in parser"` → `TITLE_ARG="Fix null pointer in parser"`). Claude must read the `$ARGS` string directly and parse semantically rather than splitting via shell `set --`.

## Prerequisites Check (MANDATORY)

Run the following checks in order. If any fails, **STOP** and report the remediation.

### 1. Verify gh CLI authentication

```bash
gh auth status
```

On failure: instruct "Run `gh auth login` to authenticate the GitHub CLI" and STOP.

### 2. Verify repository

```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
```

On failure: instruct "Run from the GitHub repository's root directory" and STOP.

### 3. Verify working tree

```bash
git status --porcelain
```

If there are uncommitted changes: display a warning and confirm whether to commit or stash. Do not proceed to PR creation while uncommitted changes remain.

### 4. Identify base branch

```bash
# Auto-detect when --base is unspecified
BASE_BRANCH=${BASE_ARG:-$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')}
# Fallback
BASE_BRANCH=${BASE_BRANCH:-main}
```

### 5. Verify diff

```bash
BRANCH=$(git branch --show-current)
# Refresh remote tracking branch to compute diff accurately
git fetch origin "${BASE_BRANCH}" --quiet 2>/dev/null
COMMIT_COUNT=$(git rev-list --count "origin/${BASE_BRANCH}..HEAD")
```

If the diff is 0 commits: instruct "No diff against the base branch" and STOP.

Use `origin/${BASE_BRANCH}` for subsequent base-branch comparison commands as well (`git diff`, `git rev-list`, `git log`, etc.).

### 6. Sanitize branch name

A `/` in the branch name nests directory paths and breaks them, so generate a filesystem-safe slug:

```bash
BRANCH_SLUG=$(echo "$BRANCH" | tr '/' '-')
```

**Usage:**
- **Filesystem paths** (screenshot save destinations, etc.): use `${BRANCH_SLUG}`
- **The ref portion of GitHub URLs** (`blob/{ref}/...`): use `${BRANCH}` (the `blob/` form correctly interprets refs containing `/`)
- **git operations / `gh pr create`**: use `${BRANCH}`

## Procedure

### 1. Collect Test Results

If `--skip-tests` is specified, skip this step and only run the existing-report read in Step 1.5.

#### 1.1 Project Type Detection

Follow the project type detection logic in `quality-checks.md`:

```bash
# 1. Leptos full-stack detection
if grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null; then
  PROJECT_TYPE="leptos"
# 2. Rust API detection (axum, actix-web, rocket, etc.)
elif grep -qE '(axum|actix-web|rocket)' Cargo.toml 2>/dev/null; then
  PROJECT_TYPE="rust-api"
# 3. Node.js detection
elif test -f package.json; then
  PROJECT_TYPE="nodejs"
# 4. None of the above
else
  PROJECT_TYPE="generic"
fi
```

#### 1.2 Run Unit Tests and Capture Results

```bash
# Explicitly initialize variables (avoid picking up environment values)
unset UT_EXIT; UT_RESULT=""; UT_OUTPUT=""

# Rust (includes rust-api, leptos) — prefer lib tests so they don't overlap with IT
# For bin-only crates (no src/lib.rs) cargo test --lib fails, so fall back
if [[ "$PROJECT_TYPE" =~ ^(rust-api|leptos)$ ]]; then
  if [ -f src/lib.rs ] || grep -qE '^\s*\[lib\]' Cargo.toml 2>/dev/null; then
    UT_OUTPUT=$(cargo test --lib --quiet 2>&1) ; UT_EXIT=$?
  else
    UT_OUTPUT=$(cargo test --quiet 2>&1) ; UT_EXIT=$?
  fi

# Node.js
elif [ "$PROJECT_TYPE" = "nodejs" ]; then
  UT_OUTPUT=$(npm test 2>&1) ; UT_EXIT=$?

# No test runner detected (generic, etc.)
else
  UT_RESULT="SKIP"
  UT_OUTPUT="No unit tests"
fi

# Result judgment when the runner ran
if [ -n "$UT_EXIT" ]; then
  if [ "$UT_EXIT" -eq 0 ]; then UT_RESULT="PASS"; else UT_RESULT="FAIL"; fi
fi
```

#### 1.3 Run Integration Tests and Capture Results

Follow the detection logic in `quality-checks.md` "Step C: Run integration tests":

```bash
# Rust: check for integration tests (.rs under tests/. Exclude e2e/ and unit/ via -path)
IT_EXISTS=$(find tests -path 'tests/e2e' -prune -o -path 'tests/unit' -prune -o -type f -name '*.rs' -print -quit 2>/dev/null)

# Node.js: check for an integration test script or files
IT_SCRIPT=$(grep -q '"test:integration"' package.json 2>/dev/null && echo "yes")
IT_FILES=$(find tests test __tests__ -type f -name 'integration*' -print -quit 2>/dev/null)
```

Run the tests only if any of `IT_EXISTS`, `IT_SCRIPT`, or `IT_FILES` is non-empty:

```bash
# Explicitly initialize variables
unset IT_EXIT; IT_RESULT=""; IT_OUTPUT=""

if [ -n "$IT_EXISTS" ]; then
  # Rust
  IT_OUTPUT=$(cargo test --tests --quiet 2>&1) ; IT_EXIT=$?

elif [ "$IT_SCRIPT" = "yes" ]; then
  # Node.js (script available)
  IT_OUTPUT=$(npm run test:integration 2>&1) ; IT_EXIT=$?

elif [ -n "$IT_FILES" ]; then
  # Node.js (file pattern only — no script)
  IT_OUTPUT=$(npm test -- --testPathPattern=integration 2>&1) ; IT_EXIT=$?

else
  # No integration tests
  IT_RESULT="SKIP"
  IT_OUTPUT="No integration tests"
fi

# Result judgment when the runner ran
if [ -n "$IT_EXIT" ]; then
  if [ "$IT_EXIT" -eq 0 ]; then IT_RESULT="PASS"; else IT_RESULT="FAIL"; fi
fi
```

#### 1.4 Run E2E Tests and Capture Results

```bash
# Explicitly initialize variables
unset E2E_EXIT; E2E_RESULT=""; E2E_OUTPUT=""

# Playwright
if test -f playwright.config.ts || test -f playwright.config.js; then
  E2E_OUTPUT=$(npx playwright test 2>&1) ; E2E_EXIT=$?

# Rust E2E (target only files under tests/e2e/ — specify per-test via --test so range does not overlap with IT)
elif test -d tests/e2e; then
  E2E_RS_COUNT=$(find tests/e2e -maxdepth 1 -name '*.rs' -type f 2>/dev/null | wc -l)
  if [ "$E2E_RS_COUNT" -eq 0 ]; then
    # Directory exists but no .rs files → SKIP
    E2E_RESULT="SKIP"
    E2E_OUTPUT="No test files in tests/e2e/"
  else
    E2E_OUTPUT=""
    E2E_EXIT=0
    for e2e_file in tests/e2e/*.rs; do
      [ -e "$e2e_file" ] || continue
      e2e_target=$(basename "$e2e_file" .rs)
      e2e_run_output=$(cargo test --test "$e2e_target" --quiet 2>&1)
      e2e_run_exit=$?
      E2E_OUTPUT="${E2E_OUTPUT}${E2E_OUTPUT:+$'\n'}${e2e_run_output}"
      if [ "$e2e_run_exit" -ne 0 ]; then E2E_EXIT=$e2e_run_exit; fi
    done
  fi

# Node.js E2E script
elif grep -q '"test:e2e"' package.json 2>/dev/null; then
  E2E_OUTPUT=$(npm run test:e2e 2>&1) ; E2E_EXIT=$?

else
  E2E_RESULT="SKIP"
  E2E_OUTPUT="No E2E tests"
fi

if [ -n "$E2E_EXIT" ]; then
  if [ "$E2E_EXIT" -eq 0 ]; then E2E_RESULT="PASS"; else E2E_RESULT="FAIL"; fi
fi
```

#### 1.5 Read Existing Report When Spec Is Specified

When `--spec` is specified (`SPEC_ARG` is non-empty), build the report path using the spec name from argument parsing and read the result if `final-e2e-gate.md` exists:

```bash
if [ -n "$SPEC_ARG" ]; then
  GATE_REPORT=".spec-workflow/specs/${SPEC_ARG}/reviews/final-e2e-gate.md"
  if test -f "$GATE_REPORT"; then
    # Extract the report's Results table, Verdict, and Notes
    # Instead of re-running tests, copy the report content into the PR body
  fi
fi
```

When `--skip-tests` is specified, use only this read result. If the report does not exist either, write "Test results: manual verification required" in the test results section.

#### 1.6 Behavior on Test Failure

If any test result is `FAIL`:

1. Show the failing test results to the user
2. Present these options:
   - A) Create the PR with tests failing (the PR body will include FAIL)
   - B) Abort PR creation and fix the tests
3. If the user chooses B, skip PR creation and STOP

### 2. UI Change Detection

Detect UI-related changes from the changed files.

```bash
# Detect changes in frontend-related files
UI_FILES=$(git diff --name-only "origin/${BASE_BRANCH}...HEAD" -- \
  '*.tsx' '*.jsx' '*.vue' '*.svelte' \
  '*.css' '*.scss' '*.less' '*.pcss' '*.html')

# Detect changes inside UI-related directories
UI_DIR_FILES=$(git diff --name-only "origin/${BASE_BRANCH}...HEAD" | \
  grep -E '(components|pages|dashboard_frontend|webview|frontend|ui)/')

# Leptos: detect changes in Rust files containing the view! macro
if [ "$PROJECT_TYPE" = "leptos" ]; then
  LEPTOS_UI=$(
    git diff --name-only "origin/${BASE_BRANCH}...HEAD" -- '*.rs' | \
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        grep -l 'view!' "$file" 2>/dev/null
      done
  )
fi
```

**Judgment**: If any of `UI_FILES`, `UI_DIR_FILES`, or `LEPTOS_UI` is non-empty → `HAS_UI_CHANGES=true`

If `HAS_UI_CHANGES=false`, skip Step 3.

### 3. Capture Screenshots

Run only when `HAS_UI_CHANGES=true`.

#### 3.1 Screenshot Collection Policy

Try in the following priority order:

**Priority 1: When E2E tests have already run**
- Collect screenshots produced by Playwright
- `.png` files inside the `test-results/` directory
- Newly added or updated files inside the `docs/screenshots/` directory (detected via `git diff --name-only`)

**Priority 2: When a dev server can be started**
- Used when E2E tests have not run but UI has changed

```bash
# Detect the dev server start command
if grep -q '"dev:dashboard"' package.json 2>/dev/null; then
  DEV_CMD="npm run dev:dashboard"
elif grep -q '"dev"' package.json 2>/dev/null; then
  DEV_CMD="npm run dev"
elif [ "$PROJECT_TYPE" = "leptos" ]; then
  DEV_CMD="cargo leptos watch"
fi
```

Start dev server → walk through changed UI screens with Playwright and capture screenshots → stop dev server

```bash
# Manual screenshot capture using Playwright (use BRANCH_SLUG in the path)
npx playwright screenshot --browser chromium "http://localhost:${PORT:-5173}" \
  "docs/screenshots/pr-evidence/${BRANCH_SLUG}/page.png"
```

**Priority 3: When neither is feasible**
- Skip screenshot capture
- Note in the PR body: "UI changes were detected, but automatic screenshot capture failed. Please verify manually."

#### 3.2 Save and Commit Screenshots

```bash
# Save destination directory (use BRANCH_SLUG in the path)
SCREENSHOT_DIR="docs/screenshots/pr-evidence/${BRANCH_SLUG}"
mkdir -p "$SCREENSHOT_DIR"

# Hold the collected screenshot paths in an array
# (store the actual file paths obtained via Priority 1 or 2)
COLLECTED_SCREENSHOTS=(
  # e.g., "test-results/screenshot-1.png"
  # e.g., "docs/screenshots/pr-evidence/.../page.png"
)

# Copy / commit only when at least one screenshot was collected
if [ "${#COLLECTED_SCREENSHOTS[@]}" -gt 0 ]; then
  cp "${COLLECTED_SCREENSHOTS[@]}" "$SCREENSHOT_DIR/"

  # Commit and push
  git add docs/screenshots/pr-evidence/
  git commit -m "docs: add screenshots for PR"
  git push
fi
```

If 0 screenshots were collected, do not copy / commit / push, and note in the PR body: "UI changes were detected, but automatic screenshot capture failed. Please verify manually." (same handling as Priority 3).

### 4. Build the PR Body

Build the PR body using the template below. Sections are assembled dynamically depending on the context.

#### 4.1 Overview Section

| Condition | Overview Text |
|-----------|---------------|
| `--closes` specified | `Fix for Issue #${CLOSES_ARG}.` |
| `--spec` specified | `Implementation of spec: ${SPEC_ARG}.` |
| Neither specified | Generate a branch change overview from `git log --oneline origin/${BASE_BRANCH}..HEAD` |

#### 4.2 Changes Section

```bash
git log --oneline origin/${BASE_BRANCH}..HEAD
```

List each commit message as a bullet item.

#### 4.3 Test Results Section

Build each test category's result in the following format:

**For PASS/FAIL** (output displayed collapsed):

```markdown
### Unit Tests
{UT_RESULT}: {pass count} passed, {fail count} failed

### Integration Tests (IT)
<details>
<summary>{IT_RESULT}: {summary line}</summary>

```
{last 50 lines of IT_OUTPUT}
```
</details>

### E2E Tests
<details>
<summary>{E2E_RESULT}: {summary line}</summary>

```
{last 50 lines of E2E_OUTPUT}
```
</details>
```

**For SKIP** (concise display):

```markdown
### Integration Tests (IT)
SKIP — No integration tests
```

**When --spec is specified and final-e2e-gate.md exists** (copy report):

```markdown
### Final E2E Gate
| Step | Result | Details |
|------|--------|---------|
{Copy the Results table from final-e2e-gate.md verbatim}

**Verdict**: {PASS / PASS(with SKIP)}

### Notes
{Copy the Notes section from final-e2e-gate.md verbatim. Includes SKIP reasons, exclusion-at-design-time rationale, etc.}
```

If the Notes section is empty or absent, omit the Notes section itself.

#### 4.4 UI Screenshots Section (only when `HAS_UI_CHANGES=true`)

```markdown
## UI Screenshots
| Screen | Screenshot |
|--------|-----------|
| {screen name} | ![{screen name}](https://github.com/{REPO}/blob/{BRANCH}/docs/screenshots/pr-evidence/{BRANCH_SLUG}/{filename}.png?raw=1) |
```

When screenshot capture was skipped:

```markdown
## UI Changes
UI changes were detected, but automatic screenshot capture failed.
Changed files:
- {list of UI_FILES}
```

#### 4.5 Spec Documents Section (only when `--spec` is specified)

Use `SPEC_ARG` from argument parsing to fix the link target:

```markdown
## Spec Documents
- [Requirements](.spec-workflow/specs/${SPEC_ARG}/requirements.md)
- [Design](.spec-workflow/specs/${SPEC_ARG}/design.md)
- [Test Design](.spec-workflow/specs/${SPEC_ARG}/test-design.md)
- [Tasks](.spec-workflow/specs/${SPEC_ARG}/tasks.md)
```

#### 4.5.5 CI Feedback Section

Display only when `.github/workflows/ci.yml` exists:

```markdown
## CI Feedback
CI test results are auto-posted to PR comments (sticky comment scheme). See the comment thread for details.
```

If `.github/workflows/ci.yml` does not exist, omit this section.

#### 4.6 Footer

```markdown
{When CLOSES_ARG is non-empty}
Closes #${CLOSES_ARG}
```

### 5. Create the PR

Write the assembled PR body to a temp file and pass it via `--body-file` (prevents quote breakage even when the body contains newlines or quotes):

```bash
PR_BODY_FILE="$(mktemp)"
cat > "${PR_BODY_FILE}" <<'PRBODY'
{Body assembled in 4.1–4.6}
PRBODY

gh pr create \
  --title "{title}" \
  --body-file "${PR_BODY_FILE}" \
  --base "${BASE_BRANCH}" \
  --assignee @me

rm -f "${PR_BODY_FILE}"
```

After PR creation, **report the PR URL to the user**.

### 6. Completion Report

```
## PR Creation Complete

- **PR**: {PR URL}
- **Title**: {title}
- **Base**: {BASE_BRANCH} ← {BRANCH}
- **Test results**: UT={UT_RESULT}, IT={IT_RESULT}, E2E={E2E_RESULT}
- **UI screenshots**: {present (N images) / none / skipped}
{When --closes is specified}
- **Related Issue**: #${CLOSES_ARG}
{When --spec is specified}
- **Spec**: ${SPEC_ARG}
```

## Rules

- Do not create a PR with uncommitted changes
- On test failure, always confirm with the user (do not auto-create a PR with FAIL)
- Save screenshots under `docs/screenshots/pr-evidence/` (do not modify the existing `docs/screenshots/`)
- Truncate long output to the last 50 lines and collapse it under a `<details>` tag
- Even when `--skip-tests` is specified, do not omit the test results section (copy from existing report, or write "manual verification required" if no report exists)
- Use the `blob/{BRANCH}/...?raw=1` form for screenshot URLs in the PR body (refs are interpreted correctly even when the branch name contains `/`)
- When using a branch name in a file path, use `BRANCH_SLUG` (with `/` already replaced by `-`)
- Project type detection follows the logic in `quality-checks.md`
