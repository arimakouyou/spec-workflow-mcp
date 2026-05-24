---
name: setup-ci
description: >
  Generate GitHub Actions CI/CD workflows for the project (base 5 files + optional extras, P4-02 compliant).
  Detects project type (Rust/Leptos/Node.js/.NET/Blazor) and creates ci.yml, e2e.yml,
  scheduled-quality.yml, dependabot.yml, release.yml mirroring quality-checks.md.
  Options like --with-sast, --with-auto-merge, --with-auto-fix generate additional workflow files.
  Triggers on: 'setup CI', 'add CI workflow', 'create GitHub Actions', 'PR checks',
  'CI/CD を追加', 'CI ワークフロー', 'GitHub Actions を設定'.
argument-hint: "[--with-e2e] [--with-services] [--with-scheduled] [--no-pr-comments] [--with-docs-lint] [--with-sast] [--with-flaky-detection] [--with-auto-merge] [--with-auto-fix]"
user-invokable: true
---

# Setup CI

Generate GitHub Actions CI/CD workflows that mirror the quality check commands defined in `.claude-plugin/rules/quality-checks.md`. Ensures parity between local agent-chain quality checks and external CI.

**P4-02 compliance**: This skill generates 5 base CI/CD configuration files and satisfies the harness-maturity-check P4-02 requirement (5 or more CI/CD configuration files). Options (`--with-sast`, etc.) generate additional files.

## Process

### 1. Detect Project Type

Use the same priority chain as `quality-checks.md`:

```bash
# Priority 1: Leptos full-stack (Rust WASM)
if [ -f Cargo.toml ] && grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null; then
  PROJECT_TYPE="leptos"
# Priority 2: Rust
elif [ -f Cargo.toml ]; then
  PROJECT_TYPE="rust"
# Priority 3: .NET Blazor (Leptos equivalent full-stack)
elif find . -maxdepth 2 -name '*.csproj' -exec grep -l 'BlazorWebAssembly\|Microsoft.AspNetCore.Components.WebAssembly' {} + 2>/dev/null | head -1 | grep -q .; then
  PROJECT_TYPE="dotnet-blazor"
# Priority 4: .NET API
elif ls *.sln 2>/dev/null | head -1 | grep -q . || find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  PROJECT_TYPE="dotnet"
# Priority 5: Node.js
elif [ -f package.json ]; then
  PROJECT_TYPE="nodejs"
else
  echo "Error: Supported project type not detected (Cargo.toml, *.csproj, *.sln, or package.json required)"
  exit 1
fi
```

### 2. Gather Project-Specific Configuration

#### Rust / Leptos

| Setting | Detection | Default |
|---------|-----------|---------|
| Toolchain | `channel` field in `rust-toolchain.toml` | `stable` |
| Workspace | Whether `Cargo.toml` has a `[workspace]` section | single crate |

#### Node.js

| Setting | Detection | Default |
|---------|-----------|---------|
| Node version | `engines.node` in `package.json` | `20` |
| Package manager | Determined by lockfile type | `npm` |
| ESLint | Whether `eslint` is in `devDependencies` | Step removed if not installed |
| Prettier | Whether `prettier` is in `devDependencies` | Step removed if not installed |
| TypeScript | Whether `typescript` is in `devDependencies` | Step removed if not installed |
| Build script | Whether `scripts.build` exists in `package.json` | Step removed if absent |
| Test script | Whether `scripts.test` exists in `package.json` | Step removed if absent |

**Package manager detection:**

| Lockfile | Package Manager | Install Command |
|----------|----------------|-----------------|
| `pnpm-lock.yaml` | `pnpm` | `pnpm install --frozen-lockfile` |
| `yarn.lock` | `yarn` | `yarn install --frozen-lockfile` |
| `package-lock.json` | `npm` | `npm ci` |
| None | `npm` | `npm install` |

#### .NET / .NET Blazor

| Setting | Detection | Default |
|---------|-----------|---------|
| .NET version | `<TargetFramework>` in .csproj or `sdk.version` in `global.json` | `10.0.x` |
| Solution file | `*.sln` at the repository root (**required** — if absent, instruct `dotnet new sln` + `dotnet sln add`) | — |
| Blazor WASM | `Microsoft.AspNetCore.Components.WebAssembly` in .csproj | false |

#### Common

Read `.spec-workflow/steering/tech.md` if it exists for additional context (language versions, framework choices).

### 3. Select and Customize Templates

Read the reference templates matching the detected project type. Generate **all 5 files**:

| # | Output | Template | Purpose |
|---|--------|----------|---------|
| 1 | `.github/workflows/ci.yml` | `references/ci-{type}.yml` | PR quality checks |
| 2 | `.github/workflows/e2e.yml` | `references/e2e-standalone.yml` | E2E / integration tests |
| 3 | `.github/workflows/scheduled-quality.yml` | `references/scheduled-quality-standalone.yml` | Weekly quality scan |
| 4 | `.github/dependabot.yml` | `references/dependabot.yml` | Automatic dependency updates |
| 5 | `.github/workflows/release.yml` | `references/release.yml` | Release / publish |

Replace `{type}` with `rust` / `leptos` / `dotnet` / `nodejs` (for `dotnet-blazor`, use the `dotnet` template and add Blazor-specific steps).

**Additional placement for Rust / Leptos only (project root):**

| Output | Template | Purpose |
|--------|----------|---------|
| `clippy.toml` (repository root) | `references/clippy.toml.template` | Auxiliary configuration to enforce TS-R4 (no unwrap) at L3 CI. Denies unwrap/expect/panic in production code while allowing them in test code (`allow-*-in-tests = true`). The CI side (`ci-rust.yml` / `ci-leptos.yml`) explicitly sets `-D clippy::unwrap_used / clippy::expect_used / clippy::panic` |

If a `clippy.toml` already exists in the project, do not overwrite it. Verify that necessary keys such as `allow-unwrap-in-tests` are included, and only propose merging the missing entries.

Replace placeholders with the values gathered in Step 2:

**Rust / Leptos:**
- `{{TOOLCHAIN}}` → detected toolchain (e.g., `stable`, `nightly`, `1.82`)

**.NET / .NET Blazor:**
- `{{DOTNET_VERSION}}` → detected .NET version (e.g., `10.0.x`)
- Prerequisite: exactly one `.sln` exists at the repository root (commands run without specifying a `.sln` path)

**Node.js:**
- `{{NODE_VERSION}}` → detected Node version (e.g., `20`)
- `{{PACKAGE_MANAGER}}` → detected package manager (e.g., `npm`)
- `{{INSTALL_COMMAND}}` → detected install command (e.g., `npm ci`)

**Remove steps for unconfigured tools** (Node.js only):
- No `eslint` in devDependencies → remove "Lint" step
- No `prettier` in devDependencies → remove "Format check" step
- No `typescript` in devDependencies → remove "Type check" step
- No `build` script in package.json → remove "Build" step
- No `test` script in package.json → remove "Tests" step

**PR comment step** (common to all project types):
- The PR comment posting step ("Post CI results to PR") is included in all templates by default
- When `--no-pr-comments` is specified, the "Post CI results to PR" step is removed from the template

### 4. Handle Options

#### `--with-e2e`

Uncomment the section in the `e2e-standalone.yml` template that matches the detected project type, and replace placeholders.
- Node.js: setup-node → install → Playwright install → Playwright test → PR comment
- Rust: rust-toolchain → cargo test --test → PR comment
- Also uncomment the `pull_request` trigger and `pull-requests: write` permission
- **Even when this option is not specified**, `e2e.yml` is still generated, but the test execution step, `pull_request` trigger, and PR comment permission remain commented out (only `workflow_dispatch` is active)

#### `--with-services`

Uncomment the service container section in `e2e.yml`.
Detect required services from the project's dependencies (`docker-compose.yml`, design.md Container Architecture, `diesel`/`redis` in `Cargo.toml`, etc.) and enable them.

#### `--no-pr-comments`

Remove the PR comment feedback steps:
- Remove the "Post CI results to PR" step from `ci.yml`
- Remove the "Post E2E results to PR" step from `e2e.yml`
- Remove `pull-requests: write` from each workflow's `permissions` block

PR comment feedback is **enabled** by default. Use this option to opt out explicitly.

#### `--with-sast`

Enable security-focused static analysis (SAST) (P6-04):
- **Rust / Leptos**: Uncomment the security-focused clippy lint section in `ci.yml`
  (`-W clippy::suspicious -W clippy::correctness -W clippy::complexity`)
- **.NET / .NET Blazor**: Add an `AnalysisLevel=latest-all` security Analyzer step to `ci.yml`
  (`CA2xxx` security category, `CA3xxx` security design guidelines). CodeQL C# is also available
- **Node.js**: Generate an additional `codeql.yml` workflow file (`javascript-typescript`)
  - CodeQL is GitHub's free SAST tool, available without limits on public repositories
  - CodeQL for Rust is in beta as of 2025, so clippy security lints are recommended

Generate `codeql.yml` only when the project type is Node.js.

#### `--with-flaky-detection`

Enable flaky test mitigation settings (P6-08/P6-09):
- Uncomment the test retry section (`nick-fields/retry@v3`) in `ci.yml`
- Retry count: 3 (success on the 2nd or later attempt is warned as a flaky candidate)
- See the `flaky-test-management` Skill for the flaky test management policy

#### `--with-auto-merge`

Generate an auto-merge workflow (P6-10/P6-11):
- Generate `auto-merge.yml` under `.github/workflows/`
- Auto-merge dependabot PRs and PRs labeled `auto-merge`
- **Prerequisites**: The following must be enabled in GitHub repository settings:
  - "Require status checks to pass before merging"
  - "Allow auto-merge"

**Auto-merge conditions (P6-11):**

| PR source | Required checks | Required approvals | Auto-merge |
|-----------|-----------------|--------------------|------------|
| dependabot | All CI passes | Not required (bot PR) | Yes |
| human + `auto-merge` label | All CI passes | 1 or more | Yes |
| human (no label) | All CI passes | 1 or more | No (manual) |

#### `--with-auto-fix`

Add a workflow where the agent generates an auto-fix PR when a quality issue is detected (P8-07):
- Generate `auto-fix-quality.yml` under `.github/workflows/`
- Launch Claude Code when an issue with both `[quality]` + `[automated]` labels is created, and auto-fix via `/handle-issue`
- **Prerequisites**:
  - The `ANTHROPIC_API_KEY` secret must be set on the GitHub repository
  - `anthropics/claude-code-action@v1` must be available

**Auto-fix flow (P8-07):**

1. `scheduled-quality.yml` detects a quality violation and creates an issue with `[quality]` + `[automated]` labels
2. `auto-fix-quality.yml` is triggered by the issue creation event
3. Claude Code runs `/handle-issue {issue-number}`
4. Implements the fix and creates a PR via `/create-pr --closes {issue-number}`
5. Quality verification by CI + review-worker
6. If `--with-auto-merge` is enabled, auto-merge via the `auto-merge` label

**Auto-fix scope:**

| Issue type | Auto-fix | Reason |
|------------|----------|--------|
| Format violation | Yes | Mechanically fixable with `cargo fmt` / `prettier --write` |
| Unused dependency | Yes | Remove from `Cargo.toml` / `package.json` |
| Missing doc comment | Yes | Apply suggestions from `/generate-api-docs` |
| Stale documentation | Yes | Update content to match the current state |
| Security vulnerability | No | Report only via issue comment (human judgment required) |
| Design deviation | No | Report only via issue comment (human judgment required) |

#### `--with-docs-lint`

Uncomment the documentation lint sections (QC10 / P5-03) in `ci.yml` and `scheduled-quality.yml`:
- Format check via markdownlint-cli2
- Link verification via markdown-link-check (scheduled-quality.yml only)
- Both are `continue-on-error: true` (Advisory)

#### `--with-scheduled`

Uncomment the quality check sections in the `scheduled-quality-standalone.yml` template that match the detected project type:
- Node.js: npm audit, jscpd code duplication detection
- Rust: cargo audit, cargo udeps, clippy
- **Even when this option is not specified**, `scheduled-quality.yml` is still generated, but only lockfile verification and documentation freshness checks are active


### 5. Generate Workflow Files

Generate all 5 of the following files (always 5 files for P4-02 compliance):

1. Create the `.github/workflows/` directory if it does not exist
2. Process each file in turn:
   - `.github/workflows/ci.yml` — generated from the `ci-{type}.yml` template
   - `.github/workflows/e2e.yml` — generated from the `e2e-standalone.yml` template
   - `.github/workflows/scheduled-quality.yml` — generated from the `scheduled-quality-standalone.yml` template
   - `.github/dependabot.yml` — generated from the `dependabot.yml` template
   - `.github/workflows/release.yml` — generated from the `release.yml` template
3. If any file already exists:
   - Show the diff against the existing file
   - Ask the user for overwrite confirmation
   - Do not overwrite without confirmation
4. In `dependabot.yml`, uncomment the ecosystem matching the detected project type:
   - Node.js → `npm` section
   - Rust / Leptos → `cargo` section
   - The `github-actions` section is always enabled

### 6. Verify and Report

After writing all files, report:

```
CI/CD workflows generated (P4-02 compliant):
  1. .github/workflows/ci.yml          — PR quality checks
  2. .github/workflows/e2e.yml         — E2E tests
  3. .github/workflows/scheduled-quality.yml — Weekly quality scan
  4. .github/dependabot.yml            — Automatic dependency updates
  5. .github/workflows/release.yml     — Release

Total CI/CD config files: 5 (P4-02 requires ≥ 5)

Project type: {detected type}
Quality checks (ci.yml):
  - {list of enabled check steps}

Options applied:
  - E2E tests: {active/commented-out (--with-e2e)}
  - Service containers: {yes/no (--with-services)}
  - Scheduled quality checks: {active/minimal (--with-scheduled)}
  - PR comment feedback: {enabled/disabled (--no-pr-comments)}
  - Documentation lint: {enabled/disabled (--with-docs-lint)}
  - SAST: {enabled/disabled (--with-sast)}
  - Flaky test retry: {enabled/disabled (--with-flaky-detection)}
  - Auto-merge: {enabled/disabled (--with-auto-merge)}
  - Auto-fix: {enabled/disabled (--with-auto-fix)}

Next steps:
  - Commit and push to verify the workflows run correctly
  - Configure repository secrets if publishing or integration tests require them
  - If E2E tests are not configured, enable them via /setup-ci --with-e2e
```

## Source of Truth

The CI workflow commands MUST match `.claude-plugin/rules/quality-checks.md` exactly.
CI-specific setup steps (tool installation etc.) are permitted as prerequisites, but the quality check commands themselves must be identical.
If `quality-checks.md` is updated, re-running `/setup-ci` regenerates the workflow with updated commands.

## Notes

- The generated YAML includes a header comment noting it was generated by `/setup-ci`
- This skill is also invoked automatically when `/spec-tasks` detects a new project without CI (Step 2.7)
- GitHub Actions only (V1). GitLab CI / other providers may be added in future versions
