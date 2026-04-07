---
name: setup-ci
description: >
  Generate a PR-triggered GitHub Actions CI workflow for the project.
  Detects project type (Rust/Leptos/Node.js) and creates .github/workflows/ci.yml
  mirroring the quality checks from quality-checks.md.
  Triggers: 'setup CI', 'add CI workflow', 'create GitHub Actions', 'PR checks',
  'CI/CD を追加', 'CI ワークフロー', 'GitHub Actions を設定'.
argument-hint: "[--with-e2e] [--with-services]"
user-invokable: true
---

# Setup CI

Generate a PR-triggered GitHub Actions CI workflow that mirrors the quality check commands defined in `.claude-plugin/rules/quality-checks.md`. Ensures parity between local agent-chain quality checks and external CI.

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
# Priority 3: Node.js
elif [ -f package.json ]; then
  PROJECT_TYPE="nodejs"
else
  echo "Error: Supported project type not detected (Cargo.toml or package.json required)"
  exit 1
fi
```

### 2. Gather Project-Specific Configuration

#### Rust / Leptos

| Setting | Detection | Default |
|---------|-----------|---------|
| Toolchain | `rust-toolchain.toml` の `channel` フィールド | `stable` |
| Workspace | `Cargo.toml` に `[workspace]` セクションがあるか | single crate |

#### Node.js

| Setting | Detection | Default |
|---------|-----------|---------|
| Node version | `package.json` の `engines.node` | `20` |
| Package manager | lockfile 種別で判定 | `npm` |
| ESLint | `devDependencies` に `eslint` があるか | 未導入ならステップ除外 |
| Prettier | `devDependencies` に `prettier` があるか | 未導入ならステップ除外 |
| TypeScript | `devDependencies` に `typescript` があるか | 未導入ならステップ除外 |
| Build script | `package.json` の `scripts.build` があるか | なければステップ除外 |
| Test script | `package.json` の `scripts.test` があるか | なければステップ除外 |

**Package manager detection:**

| Lockfile | Package Manager | Install Command |
|----------|----------------|-----------------|
| `pnpm-lock.yaml` | `pnpm` | `pnpm install --frozen-lockfile` |
| `yarn.lock` | `yarn` | `yarn install --frozen-lockfile` |
| `package-lock.json` | `npm` | `npm ci` |
| None | `npm` | `npm install` |

#### Common

Read `.spec-workflow/steering/tech.md` if it exists for additional context (language versions, framework choices).

### 3. Select and Customize Template

Read the reference template matching the detected project type:

| Project Type | Template |
|-------------|----------|
| `rust` | `.claude-plugin/skills/setup-ci/references/ci-rust.yml` |
| `leptos` | `.claude-plugin/skills/setup-ci/references/ci-leptos.yml` |
| `nodejs` | `.claude-plugin/skills/setup-ci/references/ci-nodejs.yml` |

Replace placeholders with the values gathered in Step 2:

**Rust / Leptos:**
- `{{TOOLCHAIN}}` → detected toolchain (e.g., `stable`, `nightly`, `1.82`)

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

### 4. Handle Options

#### `--with-e2e`

Append the E2E test job from `.claude-plugin/skills/setup-ci/references/job-e2e.yml`.
Uncomment the section matching the detected project type and apply the same placeholder replacements.

#### `--with-services`

Add service containers from `.claude-plugin/skills/setup-ci/references/job-services.yml`.
Uncomment services that match the project's dependencies (detect from `docker-compose.yml`, `design.md` Container Architecture, or `Cargo.toml` dependencies like `diesel`, `redis`).

### 5. Generate the Workflow File

1. Create `.github/workflows/` directory if it does not exist
2. If `.github/workflows/ci.yml` already exists:
   - Show the diff between existing and new content
   - Ask the user for confirmation before overwriting
3. Write the generated YAML to `.github/workflows/ci.yml`

### 6. Verify and Report

After writing the file, report:

```
CI workflow generated: .github/workflows/ci.yml

Project type: {detected type}
Triggers: pull_request (main, master) + push (main, master)
Quality checks:
  - {list of enabled check steps}

Options applied:
  - E2E tests: {yes/no}
  - Service containers: {yes/no}

Next steps:
  - Commit and push to verify the workflow runs correctly
  - Configure repository secrets if integration tests require them
```

## Source of Truth

The CI workflow commands MUST match `.claude-plugin/rules/quality-checks.md` exactly.
CI-specific setup steps (tool installation etc.) are permitted as prerequisites, but the quality check commands themselves must be identical.
If `quality-checks.md` is updated, re-running `/setup-ci` regenerates the workflow with updated commands.

## Notes

- The generated YAML includes a header comment noting it was generated by `/setup-ci`
- This skill is also invoked automatically when `/spec-tasks` detects a new project without CI (Step 2.7)
- GitHub Actions only (V1). GitLab CI / other providers may be added in future versions
