---
paths:
  - "**/*.rs"
  - "**/*.cs"
  - "**/Cargo.toml"
  - "**/*.csproj"
  - "**/*.sln"
  - "**/package.json"
---

# Quality Check Commands

Unified command specification for quality checks run by parallel-worker, review-worker, and other agents. All agents must use the commands defined in this rule.

> **CI Parity**: These commands are also used by the `/setup-ci` skill to generate GitHub Actions CI workflow YAML. CI templates may include additional setup steps (tool installation etc.) as prerequisites, but the quality check commands themselves must be identical. Re-run `/setup-ci` after updating this file to keep CI in sync.

> **Build Cache**: When running these commands, apply the Rust build cache configuration as described in `rust-build-cache` Skill (e.g., by using a single Bash snippet that both configures the cache and runs the `cargo` commands, or by using a per-command `RUSTC_WRAPPER=sccache cargo ...` prefix).

> **Hook Enforcement**: The following checks are also enforced via plugin hooks (`.claude-plugin/hooks/`):
> - **Auto-format (PostToolUse)**: `post-edit.sh` — QC1 rustfmt, QC6 prettier, QC10 markdownlint, QC12 dotnet format (auto-fix on Edit/Write)
> - **Format guard (PreToolUse)**: `format-check-guard.sh` — QC1/QC6/QC12 format check (blocking on git commit)
> - **Lockfile guard (PreToolUse)**: `lockfile-guard.sh` — QC9 lockfile verification (blocking on git commit)
> - **Security audit (PreToolUse)**: `security-audit-guard.sh` — QC4/QC6/QC12 vulnerability audit (blocking on git commit)

---

## Test Taxonomy

> The **canonical definition of test taxonomy** referenced by spec-test-design / spec-tasks / parallel-worker / review-worker / spec-verify.
> Source: `.claude/_docs/plans/dapper-hardening-orchestrator.md` root cause J (J-3).

Each test layer has a **clearly defined scope of responsibility**, and tests outside that scope must be assigned to a different layer. Scope violations such as writing per-feature tests in E2E, including UI verification in IT, or putting full integration into smoke are prohibited.

### 7-Layer Test Taxonomy

| Layer | Responsibility | Scope | Typical runtime | fixture | When to run |
|---|------|------|:--------:|:------:|:------:|
| **UT** (Unit Test) | pure logic (spec satisfaction + absence of out-of-spec behavior) | single function | ms | none | every TDD cycle / Phase Review / PR / merge |
| **CT** (Component Test) | component reactivity (mount -> signal -> DOM observation) | single component | seconds | mock signal | Phase Review / PR / merge |
| **IT** (Integration Test) | **backend HTTP API only** | server crate | seconds to tens of seconds | real DB / TempDir | after backend Phase completion / PR / merge |
| **ST** (System Test) | **full-stack of a single feature** (UI action -> backend -> UI update) | UI + server (one feature) | seconds to tens of seconds | real server + fixture | end of target feature Phase / PR / merge |
| **smoke** | boot + wiring (all methods) + type boundaries | entire system | 30s to 2m | none | each Phase Review |
| **E2E** (End-to-End) | **user journey only** | cross-feature | minutes to tens of minutes | real server + complete fixture | Final Gate only |
| **Regression** (cross-cutting type) | prevent recurrence of known bugs | marked **across** all UT/CT/IT/ST/E2E layers | same as each layer | same as each layer | PR / merge (required) |

### Details per Layer

#### UT (Unit Test)
- **What is verified**: spec satisfaction (happy path / boundary) + **absence of out-of-spec behavior** (no mutation / zero side effects / no panic on unexpected input)
- **FIRST principle required**: Fast / Isolated / Repeatable / Self-Validating / Timely
- **External dependencies prohibited**: direct calls to clock / RNG / env / fs / HTTP / DB are prohibited (only allowed via Mocks)
- **Implementation**: Rust uses inline `#[cfg(test)] mod tests`, .NET uses xUnit, Node uses vitest, etc.
- **`_TestFocus` 6 categories**: Happy Path / Boundary Values / Error Handling / Edge Cases / **Negative Assertions** / **Isolation Properties**

#### CT (Component Test)
- **What is verified**: mount the component and confirm reactivity works via signal updates and event dispatch
- **Target**: behavior of Resource / Suspense / on:click / on:submit / Effect inside components in UI frameworks (Leptos / Blazor / React etc.)
- **Implementation options**:
  - Leptos: `wasm-bindgen-test` + `wasm-pack test --headless --chrome` (feasibility POC: `wasm-bindgen-test-leptos-poc.md`)
  - .NET Blazor: bUnit
  - React/Vue: @testing-library
- **Out of scope**: pure logic (UT is sufficient) / real server communication (IT or ST)

#### IT (Integration Test)
- **What is verified**: behavior of backend HTTP API endpoints (status code / response body / DB state changes / authn/authz)
- **Scope**: server crate only. **Do not include the frontend Resource -> server fn boundary** (include via CT or ST)
- **Implementation**: direct Axum Router invocation via `tower::ServiceExt::oneshot` / endpoint tests via TestClient, etc.
- **fixture**: real DB (TempDir / docker-compose.test.yml)
- **Out of scope**: UI actions / DOM verification / pure logic

#### ST (System Test)
- **What is verified**: full-stack behavior of a single feature (user action in UI -> backend response -> UI update)
- **Example targets**: "login feature only", "search feature only", "zoom feature only"
- **Out of scope**: cross-feature flows (E2E responsibility) / pure logic (UT) / component reactivity alone (CT)
- **Implementation**: Playwright / Selenium with a real server started + UI operations

#### smoke
- **What is verified**: 4-layer structure
  - L1 Health: GET to `/health`, `/api/health`, `/healthz`
  - L2 Wiring: extract path / method from each `### API-N:` in design.md. For all method x all endpoint combinations, **must not return 5xx** (POST/PUT/PATCH with empty body `{}`, DELETE with placeholder ID)
  - L3 Auth: send to endpoints marked "Auth: required" in design.md without an Authorization header and expect 401
  - L4 Input boundaries: send **type-boundary values** for each path/query/body field (empty String / maxLength+1 / int overflow / undefined enum value / omitted Optional / invalid UUID) and expect 400/422
- **Out of scope**: business logic (verified in IT / UT) / composite boundaries (UT/IT) / business boundaries (IT/UT) / user journey (E2E)

#### E2E (End-to-End)
- **What is verified**: user journeys spanning multiple features (e.g., login -> search -> click result -> detail -> logout)
- **Out of scope**: per-feature tests (ST responsibility) / single-endpoint response checks (IT or smoke responsibility)
- **When to run**: Final Gate only. Not run inside Phases

#### Regression (cross-cutting type)
- **Position**: not a layer but a **type**. Markers are applied across all UT/CT/IT/ST/E2E layers
- **Naming convention** (see `regression-test-policy/SKILL.md`):
  - Rust: `fn regression_issue_NNN_<description>()` / TypeScript: `it('regression #NNN: ...')`
- **CI gate**: at PR / merge, all regression-marked tests must PASS (planned to be gated by QC16)

### Boundary Violation Patterns (common mistakes)

#### UI verification leaks into IT
- **Wrong**: including `assert dom.querySelector('[data-testid=...]')` in IT-N
- **Correct**: UI verification belongs to CT (component alone), ST (full-stack single feature), or E2E (user journey)
- **Detection**: `spec-test-design/SKILL.md` Step B Check 19 (TEST_LAYER_BOUNDARY)

#### Per-feature tests leak into E2E
- **Wrong**: calling a single-feature test like `e2e-zoom-rotate.spec.ts` an E2E test
- **Correct**: assign to ST (`st-zoom-rotate.spec.ts` or equivalent)
- **Detection**: `spec-test-design/SKILL.md` Step B Check 19

#### Full integration leaks into smoke
- **Wrong**: creating real data in smoke to verify business logic
- **Correct**: smoke is wiring + type boundaries only. Business logic belongs in IT / UT
- **Detection**: smoke runtime exceeds 5 minutes (warned in `spec-implement/SKILL.md` Step 3.5.1.5)

#### ST that could be replaced by CT
- **Question**: claimed "full-stack of a single feature" but the feature can be tested with CT without a real server
- **Decision**: server fn core logic alone -> UT; UI + signal integration -> CT; UI -> server -> UI behavior observation required -> ST
- **Detection**: in spec-test-design self-review, check "is starting the server really necessary?"

### References

- `regression-test-policy/SKILL.md`: Regression naming convention / CI gate / Traceability Matrix
- `spec-test-design/SKILL.md`: per-layer Subagents (A: UT / B: IT / C: E2E / D: CT / E: ST) and Step B Checks
- `.claude/_docs/plans/dapper-hardening-orchestrator.md`: starting point of J-3 and related items (K / I / H / E)

---

## Task-Level Checks (QC1-QC6, QC8-QC9)

Checks run pre-commit and per PR. Embedded into `ci.yml` and `scheduled-quality.yml` generated by `/setup-ci`.

## QC1: rustfmt

> 🔗 **Hook**: `post-edit.sh` (PostToolUse — auto-fix), `format-check-guard.sh` (PreToolUse — commit gate)

```bash
cargo fmt --all -- --check
```

- Targets both `src` and `tests` (do not check only one of them)
- To auto-fix, run without `--check`: `cargo fmt --all`

## QC2: clippy

```bash
cargo clippy --quiet --all-targets -- -D warnings
```

- `--all-targets`: Includes test code, benchmarks, and examples in the check
- `-D warnings`: Treats all warnings as errors
- `--quiet`: Suppresses progress output

## QC3: test

```bash
cargo test --quiet
```

- Runs all tests (unit + integration)
- To run a specific test only: `cargo test --test {test_name} -- --nocapture`

## QC3.5: Doc Comment Coverage (Advisory)

```bash
RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --quiet 2>&1 | head -20 || true
```

- Warns when `pub` items (functions, structs, fields, etc.) lack a doc comment (`///`)
- **Advisory**: Warnings are reported but do not block commits (`|| true`)
- Used as supplementary information when review-worker Category A (Style) checks for the presence of doc comments
- Combined with the doc comment gap analysis of `/generate-api-docs`, this improves natural-language description coverage for API schemas

## QC4: Dependency Analysis (Optional Tools)

Additional checks for dependency hygiene and security. These tools are optional — they run when installed and are skipped when unavailable. Agents must detect availability before running.

> **Note**: sccache (`RUSTC_WRAPPER`) is **not** applied to these commands. `cargo audit` does not invoke the compiler, and `cargo-udeps` uses `+nightly` which has unreliable sccache compatibility.

### cargo-audit (Security — blocking)

> 🔗 **Hook**: `security-audit-guard.sh` (PreToolUse — commit gate)

```bash
cargo audit
```

- Checks dependencies against the RustSec Advisory Database
- **Blocking**: If installed and vulnerabilities are found, the check **fails**. Agents must report findings and stop
- Fast execution (database lookup only, no compilation)
- See also: `.claude-plugin/rules/security.md` section A9

### cargo-udeps (Unused dependencies — advisory)

```bash
cargo +nightly udeps --quiet
```

- Detects unused dependencies declared in `Cargo.toml`
- **Advisory**: Results are reported as warnings but **do not block** commits
- Requires nightly toolchain (`rustup run nightly`)
- Runs the compiler internally, so the project must compile successfully first (place after `cargo test`)

### Detection and availability check

```bash
# cargo-audit
AUDIT_AVAILABLE=false
if command -v cargo-audit >/dev/null 2>&1; then
  AUDIT_AVAILABLE=true
fi

# cargo-udeps (requires nightly)
UDEPS_AVAILABLE=false
if command -v cargo-udeps >/dev/null 2>&1 && rustup run nightly rustc --version >/dev/null 2>&1; then
  UDEPS_AVAILABLE=true
fi
```

| Tool | Installed | Nightly available | Action |
|------|-----------|-------------------|--------|
| cargo-audit | Yes | — | Run `cargo audit`. Fail on vulnerabilities |
| cargo-audit | No | — | Skip with log: "cargo-audit not installed, skipping vulnerability check" |
| cargo-udeps | Yes | Yes | Run `cargo +nightly udeps --quiet`. Warn on findings |
| cargo-udeps | Yes | No | Skip with log: "nightly toolchain unavailable, skipping udeps" |
| cargo-udeps | No | — | Skip silently |

## QC5: Leptos Full-Stack (WASM Frontend) Build Verification

When the project uses `cargo-leptos` (detected by `[package.metadata.leptos]` in `Cargo.toml`), the following additional checks are **required** after the standard checks above.

### cargo-leptos build (preferred)

```bash
cargo leptos build
```

- Builds both SSR (server) and WASM (client) targets in a single command
- Catches WASM compilation errors that `cargo build` / `cargo test` alone cannot detect (they only compile for the host target)
- Must pass before any commit

### WASM-specific clippy (required fallback when cargo-leptos is unavailable)

```bash
cargo clippy --target wasm32-unknown-unknown --no-default-features --features hydrate --quiet -- -D warnings
```

- **Required** when `cargo-leptos` is not installed — WASM verification must not be skipped
- `--features hydrate`: Compiles only the client-side code path
- Detects WASM-incompatible API usage (e.g., `std::fs`, `std::net`, `tokio::spawn`)

### Detection and availability check for agents

Before running quality checks, agents must check for a Leptos full-stack configuration and tool availability:

```bash
# Step 1: Detect Leptos project (match the bracketed header)
grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null

# Step 2: If Leptos detected, check cargo-leptos availability
cargo leptos --version 2>/dev/null
```

| Leptos detected | cargo-leptos available | Action |
|-----------------|----------------------|--------|
| No | — | Skip WASM checks |
| Yes | Yes | Run `cargo leptos build` |
| Yes | No | Run WASM-specific clippy as required fallback |

The full check order becomes:

1. `cargo fmt --all -- --check`
2. `cargo clippy --quiet --all-targets -- -D warnings`
3. `cargo test --quiet`
4. `cargo audit` (if installed — blocking on vulnerabilities)
5. `cargo +nightly udeps --quiet` (if installed — advisory only)
6. `cargo leptos build` OR WASM-specific clippy fallback (Leptos projects only)

## QC6: Node.js Task-Level Quality Checks

> 🔗 **Hook**: `post-edit.sh` (PostToolUse — prettier auto-fix), `format-check-guard.sh` (PreToolUse — commit gate), `security-audit-guard.sh` (PreToolUse — npm audit commit gate)

When the project is Node.js-based (detected by `package.json` existence without Rust indicators), use the following task-level quality checks.

### lint

```bash
npx eslint . --max-warnings=0
```

- Falls back to `npx tsc --noEmit` if eslint is not configured
- If neither eslint nor TypeScript is configured, skip this check

### format

```bash
npx prettier --check .
```

- Skip if prettier is not configured in the project

### test

```bash
npm test
```

- Or `npx vitest run` / `npx jest` depending on the project's test runner
- To run a specific test: `npm test -- --testPathPattern={test_name}`

### type check (conditional)

```bash
npx tsc --noEmit
```

- Only run if `typescript` is in devDependencies
- If eslint is not configured, this serves as the lint fallback (see above)

### build (conditional)

```bash
npm run build
```

- Only run if `scripts.build` exists in package.json
- Skip if no build script is defined (not a failure)

The full check order for Node.js projects:

1. `npx eslint . --max-warnings=0` (or `npx tsc --noEmit` fallback)
2. `npx prettier --check .`
3. `npm test`
4. `npx tsc --noEmit` (if TypeScript configured and not already run as lint fallback)
5. `npm run build` (if build script exists)
6. `npm audit --audit-level=high` (if `package-lock.json` exists — blocking on high/critical)

### dependency audit (Node.js)

```bash
npm audit --audit-level=high
```

- Run only if `package-lock.json` exists
- **Blocking**: Fails if high / critical vulnerabilities are detected
- For `yarn.lock`, use `yarn audit --level high` (Yarn v1) or `yarn npm audit` (Yarn v2+)

### unused code detection (Node.js — advisory)

```bash
npx knip --no-progress 2>&1 | head -50
```

- Run only if `knip` is configured in the project
- **Advisory**: Reports unused files/exports but does not block
- Skipped if not installed (ignore failures from `npx knip`)

## QC12: .NET Task-Level Quality Checks

> 🔗 **Hook**: `post-edit.sh` (PostToolUse — dotnet format auto-fix), `format-check-guard.sh` (PreToolUse — commit gate), `security-audit-guard.sh` (PreToolUse — dotnet vulnerable commit gate)

When the project is .NET-based (detected by `*.sln` or `*.csproj` existence without Rust indicators), use the following task-level quality checks. Target: **.NET 10**.

> **Build Cache**: .NET uses MSBuild incremental builds and NuGet package cache automatically. See `dotnet-build-cache` Skill for details. Use `--no-restore` / `--no-build` flags to skip redundant steps in the chain.

> **Analyzers**: Projects should include .NET Analyzers (CAxxxx), Roslynator, and StyleCop.Analyzers via `Directory.Build.props`. Analyzer warnings are caught by `dotnet build -warnaserror`. See `csproj` Skill.

### format

```bash
dotnet format --verify-no-changes --no-restore
```

- Uses `.editorconfig` rules (must be present at solution root)
- `--no-restore`: Assumes `dotnet restore` has already been run separately (avoids redundant restore within the chain)
- To auto-fix: `dotnet format` (without `--verify-no-changes`)
- Covers both formatting and code style analyzers

### build (lint + compile)

```bash
dotnet build --no-restore -warnaserror
```

- `--no-restore`: Skip restore if already run
- `-warnaserror`: Treat all warnings as errors (Analyzers: CAxxxx + Roslynator + StyleCop.Analyzers + Meziantou.Analyzer)
- Catches compile errors, analyzer violations, and code quality issues in a single pass
- This is the C# equivalent of `cargo clippy`

### test

```bash
dotnet test --no-build --verbosity quiet
```

- Runs all tests (unit + integration) via xUnit
- `--no-build`: Skip build if already run
- To run a specific test: `dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"`

### doc comment coverage (advisory)

```bash
# CS1591 warnings indicate missing XML doc comments on public APIs
dotnet build --no-restore -p:DocumentationFile=docs.xml 2>&1 | grep -c "CS1591" || true
```

- **Advisory**: Reports missing doc comments but does not block commits
- Requires `<DocumentationFile>` in .csproj for full coverage
- DocFX can be used for documentation generation

### dependency analysis

#### Security audit (blocking)

```bash
# dotnet list package --vulnerable always returns exit code 0, so parse the output
OUTPUT=$(dotnet list package --vulnerable --include-transitive 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -qE "(Critical|High)"; then
  echo "Critical or high severity vulnerabilities found"
  exit 1
fi
```

- **Blocking**: If high/critical vulnerabilities are found, the check **fails**
- `--include-transitive`: Checks both direct and transitive dependencies
- Unlike `cargo audit`, this cannot be judged by exit code, so grepping the output is required

#### Redundant dependency detection (advisory)

```bash
# Snitch: detects redundant direct package references (transitive already provides them)
if dotnet tool list | grep -q snitch; then
  dotnet tool run snitch 2>&1 | head -30
fi
```

- **Advisory**: Reports redundant references but does not block commits
- This is the partial C# equivalent of `cargo +nightly udeps`

#### License audit (advisory)

```bash
# dotnet-project-licenses: reports all dependency licenses
if command -v dotnet-project-licenses >/dev/null 2>&1; then
  dotnet-project-licenses --input . 2>&1 | head -30
fi
```

- **Advisory**: Reports license information but does not block commits
- This is the C# equivalent of `cargo deny`

### Detection and availability check

```bash
# Snitch
SNITCH_AVAILABLE=false
if dotnet tool list | grep -q snitch; then
  SNITCH_AVAILABLE=true
fi

# dotnet-project-licenses
LICENSES_AVAILABLE=false
if command -v dotnet-project-licenses >/dev/null 2>&1; then
  LICENSES_AVAILABLE=true
fi
```

| Tool | Installed | Action |
|------|-----------|--------|
| dotnet list package --vulnerable | Always available | Run. Fail on high/critical |
| Snitch | Yes | Run `dotnet tool run snitch`. Warn on findings |
| Snitch | No | Skip with log: "snitch not installed, skipping redundant dependency check" |
| dotnet-project-licenses | Yes | Run. Report licenses |
| dotnet-project-licenses | No | Skip silently |

### QC12.6: Blazor Build Verification (Blazor projects only)

When the project uses Blazor WebAssembly (detected by `Microsoft.AspNetCore.Components.WebAssembly` in .csproj), the following additional checks are **required** after the standard checks above. This is the C# equivalent of QC5 (Leptos WASM verification).

#### dotnet publish with Trim (preferred)

```bash
dotnet publish -c Release -p:PublishTrimmed=true
```

- Builds the WASM output with trimming enabled
- Catches trimming-incompatible code (reflection, dynamic loading) that `dotnet build` alone cannot detect
- Must pass before any commit

#### Trim/AOT warning detection (advisory)

```bash
dotnet publish -c Release -p:PublishTrimmed=true -p:RunAOTCompilation=true 2>&1 | grep -E "(IL2[0-9]{3}|IL3[0-9]{3})" || true
```

- **Advisory**: Reports Trim/AOT warnings (IL2xxx linker warnings, IL3xxx AOT warnings)
- These indicate reflection-dependent code that may break at runtime

### Detection and Blazor check for agents

```bash
# Step 1: Detect Blazor WebAssembly project
BLAZOR_WASM=false
if find . -maxdepth 2 -name '*.csproj' -exec grep -l 'Microsoft.AspNetCore.Components.WebAssembly' {} + 2>/dev/null | head -1 | grep -q .; then
  BLAZOR_WASM=true
fi
```

| Blazor WASM detected | Action |
|---------------------|--------|
| No | Skip Blazor checks |
| Yes | Run `dotnet publish -c Release -p:PublishTrimmed=true` |

The full check order for .NET projects:

1. `dotnet restore`
2. `dotnet format --verify-no-changes`
3. `dotnet build --no-restore -warnaserror` (Analyzers: CAxxxx + Roslynator + StyleCop)
4. `dotnet test --no-build --verbosity quiet`
5. `dotnet list package --vulnerable --include-transitive` (blocking on high/critical)
6. `dotnet tool run snitch` (if installed — advisory)
7. `dotnet publish -c Release -p:PublishTrimmed=true` (Blazor projects only — required)

## QC8: Code Duplication Detection (Advisory)

Detect code duplication. Applicable to all project types.

```bash
npx jscpd --min-lines 10 --min-tokens 50 \
  --ignore '**/target/**,**/node_modules/**,**/dist/**' \
  --reporters consoleFull .
```

- **Advisory**: Duplications are reported but do not block commits
- Skipped if the detection tool is not installed
- Used in combination with Issue creation in the weekly scheduled check (`--with-scheduled`)
- `jscpd` is effective for Rust projects too (text-based duplication detection)

Alternative tools:
- Rust: `cargo install cargo-clone-detection` (when available)
- Python: `pylint --disable=all --enable=duplicate-code`

## QC9: Lockfile Verification (P4-03)

> 🔗 **Hook**: `lockfile-guard.sh` (PreToolUse — commit gate)

Verifies that the package manager's lockfile is committed to the repository.
The absence of a lockfile leads to non-reproducible builds, so this is a **Blocking** check.

### Detection Targets

| Package Manager | Manifest | lockfile |
|-------------------|------------|---------|
| npm | `package.json` | `package-lock.json` |
| yarn | `package.json` | `yarn.lock` |
| pnpm | `package.json` | `pnpm-lock.yaml` |
| Cargo (Rust) | `Cargo.toml` | `Cargo.lock` |
| Go | `go.mod` | `go.sum` |
| NuGet (.NET) | `*.csproj` | `packages.lock.json` |
| Poetry (Python) | `pyproject.toml` | `poetry.lock` |
| Bundler (Ruby) | `Gemfile` | `Gemfile.lock` |

### Check Command

```bash
# Verify the existence of manifest files and their corresponding lockfiles
FAIL=false

# Node.js (any one is OK)
if [ -f package.json ]; then
  if [ ! -f package-lock.json ] && [ ! -f yarn.lock ] && [ ! -f pnpm-lock.yaml ]; then
    echo "FAIL: package.json exists but no lockfile found (package-lock.json, yarn.lock, pnpm-lock.yaml)"
    FAIL=true
  fi
fi

# Rust
if [ -f Cargo.toml ] && [ ! -f Cargo.lock ]; then
  echo "FAIL: Cargo.toml exists but Cargo.lock not found"
  FAIL=true
fi

# Go
if [ -f go.mod ] && [ ! -f go.sum ]; then
  echo "FAIL: go.mod exists but go.sum not found"
  FAIL=true
fi

# .NET (packages.lock.json is only generated when RestorePackagesWithLockFile is enabled)
# When Central Package Management is used, verify the existence of Directory.Packages.props
if find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  if find . -maxdepth 3 \( -name '*.csproj' -o -name 'Directory.Build.props' -o -name 'Directory.*.props' \) -exec grep -lq 'RestorePackagesWithLockFile' {} + 2>/dev/null; then
    if [ ! -f packages.lock.json ] && ! find . -maxdepth 3 -name 'packages.lock.json' -print -quit 2>/dev/null | grep -q .; then
      echo "FAIL: RestorePackagesWithLockFile enabled but packages.lock.json not found"
      FAIL=true
    fi
  fi
fi

# Verify that the file is not excluded by .gitignore
for lockfile in package-lock.json yarn.lock pnpm-lock.yaml Cargo.lock go.sum poetry.lock Gemfile.lock packages.lock.json; do
  if [ -f "$lockfile" ] && git check-ignore -q "$lockfile" 2>/dev/null; then
    echo "FAIL: $lockfile is gitignored — lockfile must be committed for reproducible builds"
    FAIL=true
  fi
done
```

| Condition | Verdict | Action |
|------|------|-----------|
| lockfile exists and is tracked by git | PASS | — |
| lockfile is excluded by `.gitignore` | FAIL | Remove the exclusion from `.gitignore` and commit |
| lockfile is missing (manifest exists) | FAIL | Run the install command to generate the lockfile and commit it |
| manifest itself is missing | SKIP | Out of scope |

> **CI integration**: This check is built into `scheduled-quality-standalone.yml`.
> If a lockfile is not committed, an Issue is automatically created by the weekly scan.

> **Enforcement level**:
> - **Agent/local**: Blocking — blocks commits when the lockfile is not committed
> - **PR CI (`ci.yml`)**: Blocking — fails CI when the lockfile is not committed
> - **Weekly scan (`scheduled-quality.yml`)**: Advisory (`continue-on-error: true`) — automatically creates an Issue on detection but does not stop the entire workflow

## QC10: Documentation Lint (P5-03)

> 🔗 **Hook**: `post-edit.sh` (PostToolUse — markdownlint auto-fix)

Verifies the formatting consistency and link integrity of Markdown files. Common to all project types.

### markdownlint (format check)

```bash
npx markdownlint-cli2 "**/*.md" "#node_modules" "#target" "#dist"
```

- If `.markdownlint.yaml` exists, follow its rules
- If not configured, default rules apply (recommended: disable MD013 line-length)
- Auto-fix: `npx markdownlint-cli2 --fix "**/*.md" "#node_modules" "#target" "#dist"`

### markdown-link-check (link verification)

```bash
find . -name '*.md' -not -path '*/node_modules/*' -not -path '*/target/*' -not -path '*/.spec-workflow/*' | \
  xargs -I {} npx markdown-link-check {} --config .markdown-link-check.json 2>&1 | tee /tmp/link-check-output.txt
```

- If `.markdown-link-check.json` exists, follow its config
- If not configured, defaults apply (recommended: ignore 429 Too Many Requests on external links)

| Condition | Verdict | Action |
|------|------|-----------|
| no format violations & no broken links | PASS | — |
| format violations present | WARN | Can be auto-fixed with `markdownlint-cli2 --fix` |
| broken links present | WARN | Update or remove the link target |

> **Enforcement level**:
> - **Agent/local**: Advisory — reports but does not block commits
> - **PR CI (`ci.yml`)**: Advisory (`continue-on-error: true`) — reports via PR comment
> - **Weekly scan (`scheduled-quality.yml`)**: Advisory — creates an Issue on detection
>
> **Relationship to doc-crossref.md**: QC10 covers mechanical format verification and broken-link detection.
> `doc-crossref.md` covers semantic reference integrity specific to spec-workflow (Requirements Traceability, etc.).

## QC11: SAST / Security-Focused Static Analysis (P6-04)

Run security-focused static code analysis. In addition to the general lints in QC2 (clippy),
explicitly enable security-related lint groups.

### Rust / Leptos

```bash
cargo clippy --all-targets -- -W clippy::suspicious -W clippy::correctness -W clippy::complexity
```

- `clippy::suspicious`: Suspicious code patterns (signs of unintended behavior)
- `clippy::correctness`: Correctness issues (high probability of bugs)
- `clippy::complexity`: Unnecessary complexity (which expands the attack surface)

### Node.js

```bash
# ESLint + security plugin
npx eslint --plugin security --rule 'security/detect-object-injection: warn' .

# Or CodeQL (via GitHub Actions)
# Automatically run by the codeql.yml workflow
```

### .NET

```bash
# .NET Analyzers (CAxxxx) + Roslynator + StyleCop — already run in QC12.2 via dotnet build -warnaserror
# Additional security-focused checks:
dotnet build --no-restore -p:AnalysisLevel=latest-all 2>&1 | grep -E "(CA2[0-9]{3}|CA3[0-9]{3})" || true
```

- `CA2xxx`: Security-related analyzers (SQL injection, XSS, etc.)
- `CA3xxx`: Security design guidelines
- `AnalysisLevel=latest-all`: Enables the latest rules from all categories
- CodeQL is automatically run via GitHub Actions (C# supported)

### Other SAST Tools (alternatives)

| Tool | Supported Languages | Features |
|--------|---------|------|
| CodeQL | JS/TS, Python, Go, Java | Built into GitHub, free for public repositories |
| Semgrep | multi-language | Rule-based, OSS |
| SonarQube | multi-language | Enterprise-oriented |

> **Enforcement level**:
> - **Agent/local**: Advisory — reports but does not block commits
> - **PR CI (`ci.yml`)**: Advisory (`continue-on-error: true`)
> - **Weekly scan**: Automatically run by the CodeQL schedule trigger

---

## Integration-level Verification (QC7)

Integration-level verification run during Phase Review and the Final E2E Gate. Run it as a step independent of task-level checks (QC1-QC6, QC8-QC9), only at Phase completion.

## QC7: Integration Verification (Phase Review / Final E2E Gate)

Integration-level verification run during Phase Review (3.5.1.5) and the Final E2E Gate (section 9) after all Phases complete.
Run it as a step independent of task-level quality checks (rustfmt, clippy, cargo test).

### Project-type detection

Detect in the following order, adopting the first matching type:

```bash
# 1. Leptos full-stack detection (bracketed header avoids false positives)
if grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null; then
  echo "leptos"
# 2. Rust API detection (axum, actix-web, rocket, etc.)
elif grep -qE '(axum|actix-web|rocket)' Cargo.toml 2>/dev/null; then
  echo "rust-api"
# 3. .NET Blazor full-stack detection (Leptos equivalent)
elif find . -maxdepth 2 -name '*.csproj' -exec grep -l 'BlazorWebAssembly\|Microsoft.AspNetCore.Components.WebAssembly' {} + 2>/dev/null | head -1 | grep -q .; then
  echo "dotnet-blazor"
# 4. .NET API detection
elif ls *.sln 2>/dev/null | head -1 | grep -q . || find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  echo "dotnet"
# 5. Node.js detection
elif test -f package.json; then
  echo "nodejs"
# 6. None of the above
else
  echo "generic"
fi
```

### Step B: Build verification (common to all projects, required)

Confirm the build of artifacts succeeds. A build failure is FAIL immediately.

| Type | Command | Notes |
|--------|---------|------|
| Leptos | `cargo leptos build` | Builds both SSR and WASM |
| Rust API | `cargo build` | A release build is not required (debug build suffices) |
| .NET Blazor | `dotnet publish -c Release -p:PublishTrimmed=true` | Includes WASM + Trim verification |
| .NET API | `dotnet build --no-restore -warnaserror` | Treat analyzer warnings as errors |
| Node.js | `npm run build` | Only when a `build` script exists in package.json. If not, SKIP (not FAIL) and log "no build script" |
| Generic | `cargo build` or `dotnet build` or `npm run build` | Run any detectable build command. SKIP if none applies |

### Step C: Run integration tests

Run when integration test files exist. Decision when they do not (in priority order):
- design.md's Excluded Test Environments declares this integration test environment as excluded -> **SKIP (excluded by design)**
- No such exclusion, and test-design.md defines the integration test specification -> **FAIL (missing implementation)** -- the test file must be created
- Neither of the above, and test-design.md does not define the integration test specification -> **SKIP (not required by design)** -- log the reason and supplement via Expert Team Review

**Objective criteria for "test-design.md defines an integration test specification"** (the orchestrator must follow this rule strictly):
- A `## Integration Test Specifications` section heading exists in test-design.md
- AND at least one heading starting with `### IT-` exists within that section (e.g., `### IT-1: API endpoint integration test`)
- The "spec exists" judgment holds only when both conditions are met. Otherwise "spec absent"

```bash
# Rust: existence check for integration tests (.rs files under tests/. Recursively excludes e2e/ and unit/)
# Targets: .rs files under tests/integration*/, or .rs files directly under tests/
find tests -type f -name '*.rs' ! -regex '.*/tests/\(e2e\|unit\)/.*' -print -quit 2>/dev/null

# .NET: existence check for integration test projects
find . -maxdepth 3 \( -name '*Integration*Tests*.csproj' -o -name '*IntegrationTests*.csproj' \) -print -quit 2>/dev/null

# Node.js: existence check for integration test scripts or files
grep -q '"test:integration"' package.json 2>/dev/null || \
  find tests test __tests__ -type f -name 'integration*' -print -quit 2>/dev/null
```

| Type | Command |
|--------|---------|
| Rust | `cargo test --tests --quiet` |
| .NET | `dotnet test --filter "Category=Integration" --no-build --verbosity quiet` (tests must have `[Trait("Category","Integration")]`) |
| Node.js (script present) | `npm run test:integration` |
| Node.js (file only) | `npm test -- --testPathPattern=integration` |

### Step D: Smoke tests (**applies to all project types**, revised in E-1)

> Revised in E-1 (dapper-hardening): the old "API projects only" spec was abolished; project-type-specific smoke definitions and a 4-layer structure (L1-L4) were adopted.
> Smoke is **verification of wiring + type boundaries**, not just ping or just /health (see `Test Taxonomy` section #smoke).

#### Smoke Test Definition (finalized in E-1)

| project-type | Detection | Smoke content |
|------|------|------|
| **API (HTTP server)** | `axum` / `actix-web` / `rocket` in `Cargo.toml` / Web dependency in `*.csproj` / Express, etc. | L1-L4 (below). No 5xx for any method x endpoint |
| **Library (crate / npm package)** | `[lib]` only / `package.json` with `main` only | `cargo build --lib --release` + crate-root doctests / "import + one method call" smoke for the public API |
| **CLI** | Has `[[bin]]` / `bin` in `package.json` | `<binary> --help` / `<binary> --version` + `--help` for major subcommands + non-zero exit code on missing required args |
| **UI / Frontend (CSR / WASM only)** | Trunk / `[package.metadata.leptos]` without SSR | WASM bundle build + initial render in headless browser + all `data-testid` elements appear in the DOM (see QC17 UI Smoke Render) |
| **Full-stack (Leptos SSR / Next.js)** | Has `[package.metadata.leptos]` / `next.config.js`, etc. | Combination of API smoke (L1-L4) + UI smoke (QC17) |
| **Worker / Daemon** | A binary that has no HTTP server but is a long-running process | Start the binary + 30-second crash-loop watch + shutdown |

#### API Smoke 4-layer Structure (L1-L4, E-1)

| Layer | Content | Expected | Meaning of failure |
|---|------|---------|----------|
| **L1: Health** | GET to `/health`, `/api/health`, `/healthz` | 200 | Server failed to start |
| **L2: Wiring smoke** | Extract path / method from each `### API-N:` in design.md. Send a minimal request per method:<br>- **GET**: no query<br>- **POST/PUT/PATCH**: empty body `{}`<br>- **DELETE**: placeholder ID at the end of the path (`/users/00000000-0000-0000-0000-000000000000`) | **Any of 2xx / 3xx / 4xx (no 5xx)** | Wiring bug: handler not wired / DI mismatch / unhandled panic |
| **L3: Auth smoke** | For each endpoint in design.md marked "Auth: required", send without the Authorization header | 401 | Authorization leak (a 200 indicates a security incident) |
| **L4: Input boundary smoke** | From the design.md API definition, generate one **type-boundary value** per argument (path/query/body field):<br>- Required String: empty `""`<br>- String maxLength: limit+1 char<br>- int min/max: +/-1 overflow<br>- enum: undefined value<br>- Optional omitted | **400/422 (no 5xx)** | Insufficient validation: missing deny_unknown_fields / type-conversion panic / missing null handling |

**Boundaries**:
- Happy-path business logic (an entity created via POST is retrievable via GET) -> outside smoke responsibility (verify via IT)
- Composite / business boundaries (e.g., `user.age` 18-120) -> outside smoke responsibility (verify via UT/IT)

#### Differences from the old Step D (E-1)

Extension over the old spec ("API projects only", "`/health` only"):
- Defined smoke per project-type (now also covers Library / CLI / UI / Full-stack / Worker)
- API smoke covers **all methods**, not just GET (L2 Wiring smoke)
- Added auth smoke (L3) and type-boundary smoke (L4)
- When "the Phase has no smoke-able deliverable", **escalate** rather than SKIP (E-2, treated as a Phase Deliverables design problem)

#### Continuing the existing Step D implementation (for API projects)

**Container-based (when docker-compose.yml exists -- preferred):**

```bash
# Start services with docker-compose
docker-compose up -d
sleep 10
```

After running the health check:
```bash
docker-compose down
```

**Direct startup (when docker-compose.yml does not exist -- fallback):**

```bash
# Switch the server start command based on project type
if [ -f Cargo.toml ]; then
  START_CMD="cargo run"
elif SLN=$(ls *.sln 2>/dev/null | head -1) && [ -n "$SLN" ]; then
  # Assumes a single .sln at the repo root
  # Prefer the Web SDK project (class libraries cannot be `dotnet run`)
  ENTRY_PROJECT=$(dotnet sln "$SLN" list 2>/dev/null | tail -n +3 | while read -r proj; do
    [ -f "$proj" ] && grep -q 'Microsoft.NET.Sdk.Web' "$proj" && echo "$proj" && break
  done)
  # Fall back to the first project if no Web SDK is found
  [ -z "$ENTRY_PROJECT" ] && ENTRY_PROJECT=$(dotnet sln "$SLN" list 2>/dev/null | tail -n +3 | head -1)
  START_CMD="dotnet run --project ${ENTRY_PROJECT:-.}"
elif [ -f package.json ]; then
  # Prefer the dev script in package.json if present; otherwise check the start script
  if command -v node >/dev/null 2>&1 && \
     node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.dev ? 0 : 1)" >/dev/null 2>&1; then
    START_CMD="npm run dev"
  elif command -v node >/dev/null 2>&1 && \
       node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.start ? 0 : 1)" >/dev/null 2>&1; then
    START_CMD="npm start"
  else
    echo "Step D: skipping smoke test because the Node.js project has no start / dev script." >&2
    exit 0
  fi
else
  echo "Step D: skipping smoke test because no supported project type (Rust/.NET/Node.js) was found." >&2
  exit 0
fi

# Start the server in the background (new session so we can reliably stop it)
setsid sh -c "$START_CMD" &
SERVER_PID=$!
trap "kill -- -$SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null" EXIT
sleep 5

# Health check (try /health then /api/health)
HEALTH_STATUS="000"
for ENDPOINT in "/health" "/api/health" "/healthz"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT:-3000}${ENDPOINT}" 2>/dev/null)
  if [ "$STATUS" = "200" ]; then
    HEALTH_STATUS="200"
    break
  fi
done

# Cleanup
kill -- -$SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

# PASS/FAIL judgment
if [ "$HEALTH_STATUS" != "200" ]; then
  echo "Step D: health check failed -- no endpoint returned 200." >&2
  exit 1
fi
```

**Smoke test SKIP conditions** (only when the test is unnecessary or impossible by design):
- The health-check endpoint is undefined in the design doc
- The server start command is unknown (e.g., no `[[bin]]` section in Cargo.toml)
- A Node.js project has no `start` / `dev` script
- No supported project type (Rust/.NET/Node.js) is detected

**Environment-deficiency FAIL conditions** (when tools/runtimes are missing -- environment-dependent skips are never allowed):
- Docker / container runtime not installed, or `docker` / `docker-compose` commands absent / unable to run due to insufficient permissions (including failure of `docker-compose up`)
- Chrome / browser not installed
- Tools required to start DB / cache not installed
- Runtimes required to start the server (cargo, dotnet, node, etc.) not installed
- External dependencies (DB, cache, etc.) cannot be started locally (it is the design's responsibility to make them startable via Docker / testcontainers)

On environment-deficiency FAIL, escalate to the user with the missing tools clearly listed. Present the Install Command from the Required Tools table in design.md / test-design.md. In particular, when `docker-compose.yml` exists and the smoke test runs `docker-compose up`, command absence / insufficient permissions / startup failure are all FAIL (environment deficiency) -- STOP immediately and do not treat as SKIP/PASS.

**Test-implementation-omission FAIL conditions**:
- test-design.md defines an E2E test specification but the test file does not exist -> FAIL (missing implementation)
- test-design.md defines an IT specification but the integration test file does not exist -> FAIL (missing implementation)

On SKIP, always log the reason and supplement via Expert Team Review.

### Result judgment for integration verification

| Result | Condition | Action |
|------|------|----------|
| **PASS** | Build succeeded + all tests passed + smoke OK (including SKIP(not required by design)/SKIP(excluded by design)/SKIP(no build command detected)) | Proceed to next step |
| **FAIL (build)** | Build failed | Analyze the build error, identify the root-cause task, and send back |
| **FAIL (integration tests)** | Integration tests failed | Analyze the failing test errors. In-Phase task -> send back; previous Phase -> escalate to the user |
| **FAIL (smoke)** | Health check failed (no SKIP condition) | Analyze startup logs, identify the root cause, and send back |
| **FAIL (environment deficiency)** | Required tool / runtime not installed | Report the missing tools to the user and present the Install Command from the Required Tools table. Stop the implementation (STOP) |
| **FAIL (missing implementation)** | test-design.md has the test specification but no test file exists | Report to the user as missing test implementation |
| **SKIP (not required by design)** | The test specification itself does not exist (undefined in the design doc) | Log the SKIP reason and proceed; supplement via Expert Team Review |
| **SKIP (excluded by design)** | Explicitly excluded under design.md "Excluded Test Environments" | Log the exclusion reason and proceed |

## QC13: Branch Coverage (Advisory -> Phased Gating)

To expose insufficient testing of exception paths and branch coverage, measure line coverage and branch coverage **separately**.
Addresses plan-redesign #3 "Separate gating for branch coverage".

### Measurement commands

#### Rust / Leptos

```bash
# cargo-llvm-cov (recommended; collects line + branch together)
cargo install cargo-llvm-cov --locked
cargo llvm-cov --branch --summary-only
# JSON output enables threshold checks:
# cargo llvm-cov --branch --json --output-path coverage.json
```

#### .NET

```bash
# coverlet (XPlat) for line + branch
dotnet test --collect:"XPlat Code Coverage" \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura
# Extract line-rate / branch-rate from Cobertura XML and compare against thresholds
```

#### Node.js

```bash
# vitest --coverage (V8 provider) for line + branch
npx vitest run --coverage --coverage.reporter=json-summary
# Extract total.lines.pct / total.branches.pct from coverage/coverage-summary.json
```

### Recommended thresholds (initial; raise progressively)

| Stage | line | branch | Where applied | Gating |
|------|:---:|:---:|--------|:------:|
| Initial (advisory) | 70% | 50% | scheduled-quality (weekly) | report-only |
| Mid | 80% | 65% | scheduled-quality + ci.yml | warning |
| Mature | 85% | 75% | ci.yml (on PR) | blocking |

### Phased gating policy

- **Initial stage**: measure only in `scheduled-quality.yml`. Report under-threshold via a weekly Issue (advisory)
- **Mid**: add to `ci.yml` but treat as a warning via `continue-on-error: true`
- **Mature**: blocking in `ci.yml`. `continue-on-error: false` +
  `--fail-under=<line>` / failing the branch threshold causes CI Fail

### Interpretation when branch coverage is lower than line coverage

A strong signal that tests for exception paths / error handling are missing.
Use as grounds for filing a finding in review-worker E (Tests) / E2-4 (Edge cases and error paths are tested).

**Typical examples**:

- line: 85%, branch: 40% -> only the happy path is tested; the branches of `Result::Err` / `match` are untested
- line: 60%, branch: 55% -> simply not enough tests overall

Separating the two metrics catches the state of "lines were exercised but branches were not".

---

## QC14: Component Test (CT) Gate (added in H-1)

> Source: `.claude/_docs/plans/dapper-hardening-orchestrator.md` root cause H (H-1).
> Practicality confirmed in POC `wasm-bindgen-test-leptos-poc.md` (Leptos 0.7 + wasm-bindgen-test, 3 tests PASS in 5 seconds).

### Purpose

Define **CT (Component Test)** as the middle layer between UT (pure logic) and E2E (user journey), and continuously verify component reactivity (mount -> signal -> DOM) within a Phase. Structurally prevents the Phase 4 placeholder-commit anti-pattern (the anti-pattern of marking `[x]` complete with only pure-helper UTs).

### Scope of responsibility

See the `Test Taxonomy` section. CT:

- **Target**: reactivity of a single component (mount -> signal manipulation -> DOM observation)
- **Scope**: 1 UI component
- **Runtime**: seconds/test
- **Fixture**: mock signal (via the declarations in design.md K-3 Architecture for Testability)
- **Out of scope**: pure logic (UT) / real server communication (IT or ST) / user journey (E2E)

### Rust / Leptos

**Setup** (the minimal configuration established in the POC):

```toml
# Cargo.toml
[target.'cfg(target_arch = "wasm32")'.dev-dependencies]
wasm-bindgen-test = "0.3"
gloo-timers = { version = "0.3", features = ["futures"] }
web-sys = { version = "0.3", features = ["Document", "Element", "HtmlElement", "Window"] }
```

```toml
# .cargo/config.toml
[target.wasm32-unknown-unknown]
runner = "wasm-bindgen-test-runner"
```

**Run command**:

```bash
cargo test --target wasm32-unknown-unknown --lib
```

**Test pattern**:

```rust
#[cfg(target_arch = "wasm32")]
#[cfg(test)]
mod tests {
    use super::*;
    use wasm_bindgen_test::*;
    use leptos::mount::mount_to;
    use wasm_bindgen::JsCast;

    wasm_bindgen_test_configure!(run_in_browser);

    fn fresh_wrapper() -> web_sys::Element {
        let document = web_sys::window().unwrap().document().unwrap();
        let test_wrapper = document.create_element("section").unwrap();
        let _ = document.body().unwrap().append_child(&test_wrapper);
        test_wrapper
    }

    async fn tick() {
        gloo_timers::future::TimeoutFuture::new(0).await;
    }

    #[wasm_bindgen_test]
    async fn component_reactivity() {
        let wrapper = fresh_wrapper();
        let _dispose = mount_to(
            wrapper.clone().unchecked_into(),
            || view! { <MyComponent /> },
        );

        // update a signal / trigger an event
        let button = wrapper
            .query_selector("[data-testid='action-btn']")
            .unwrap().unwrap()
            .unchecked_into::<web_sys::HtmlElement>();
        button.click();
        tick().await;

        // DOM observation
        let target = wrapper
            .query_selector("[data-testid='target-value']")
            .unwrap().unwrap();
        assert_eq!(target.text_content().unwrap(), "expected");
    }
}
```

Details: see `tdd-skills-rust/references/leptos-frontend-testing.md` section 6.

### .NET / Blazor

Use **bUnit** (standard tooling, robust):

```csharp
[Fact]
public void Counter_ClickIncrementsValue()
{
    using var ctx = new TestContext();
    var cut = ctx.RenderComponent<Counter>(parameters => parameters
        .Add(p => p.InitialValue, 0));

    cut.Find("[data-testid='btn-inc']").Click();

    Assert.Equal("1", cut.Find("[data-testid='counter-value']").TextContent);
}
```

Details: `tdd-skills-dotnet/references/blazor-component-testing.md` (to be developed later; for now refer to the official bUnit documentation).

### CI integration

```yaml
- name: Component Test (QC14)
  run: |
    # Leptos: install Firefox / geckodriver
    sudo apt-get install -y firefox-esr
    cargo test --target wasm32-unknown-unknown --lib
    # .NET / Blazor:
    dotnet test --filter "Category=ComponentTest"
```

### Phased gating

| Stage | Application |
|------|------|
| Initial (advisory) | Warning for components without a CT (detected by spec-tasks Step 7 Check 17/18) |
| Mid | Require "CT-N PASS" in `_Success` for UI component tasks (H-4 / Check 18) |
| Mature | review-worker Category E files Moderate findings for missing CTs (H-5) |

### Constraints confirmed in the POC

- **wasm-pack is not required** (`cargo test --target wasm32-unknown-unknown` works directly)
- **Firefox + geckodriver or Chromium + chromedriver is required in CI**
- Production-code calls to Resource / server fn must be tested through mocks (declared in design.md K-3)

---

## QC15: UT Properties Gate (added in I-2)

> Source: `.claude/_docs/plans/dapper-hardening-orchestrator.md` root cause I (I-2).
> POC results reflected: see `.claude/_docs/plans/nextest-shuffle-isolation-lints-poc.md`.

### Purpose

Mechanically enforce in CI that UTs satisfy **spec verification** (spec satisfaction + absence of out-of-spec behavior) and guarantee **zero external dependencies + order independence + determinism** (FIRST principles).

Structurally establish the frame that "UT during implementation is verification of the spec, not confirmation that the code runs (cargo test PASS)".

### Composition

#### A. External Dependency Lint (required, blocking)

Adopt **clippy `disallowed-methods` as the main pillar** (operation confirmed in the POC).

Configure the following in `clippy.toml` (or `[workspace.lints.clippy]` in `Cargo.toml`):

```toml
# clippy.toml
disallowed-methods = [
    # Direct Clock calls (only allowed via the MockClock declared in design.md K-3 Architecture for Testability)
    { path = "std::time::SystemTime::now", reason = "use MockClock from design.md Architecture for Testability instead (K-3)" },
    { path = "std::time::Instant::now", reason = "use MockClock instead (K-3)" },
    { path = "chrono::Utc::now", reason = "use MockClock instead (K-3)" },
    { path = "chrono::Local::now", reason = "use MockClock instead (K-3)" },

    # Direct RNG use
    { path = "rand::thread_rng", reason = "use injected MockRng (K-3)" },
    { path = "rand::random", reason = "use injected MockRng (K-3)" },

    # Direct env reads
    { path = "std::env::var", reason = "use injected config (K-3)" },
    { path = "std::env::var_os", reason = "use injected config (K-3)" },

    # Direct fs calls (prefer via tempfile / TestFs)
    { path = "std::fs::read", reason = "use tempfile or injected fs adapter (K-3)" },
    { path = "std::fs::write", reason = "use tempfile or injected fs adapter (K-3)" },
    { path = "std::fs::read_to_string", reason = "use tempfile or injected fs adapter (K-3)" },

    # Direct HTTP calls (via mockito / wiremock)
    { path = "reqwest::get", reason = "use mockito / wiremock (K-3)" },
    { path = "reqwest::blocking::get", reason = "use mockito / wiremock (K-3)" },
]
```

CI run command (blocking):

```bash
cargo clippy --all-targets --workspace -- -D clippy::disallowed_methods
```

**Operation confirmation** (POC):
- Direct calls to `std::time::SystemTime::now` / `std::env::var` -> warnings detected with custom reasons
- Promoted to deny-level via `-D clippy::disallowed_methods` -> CI fails
- Details: see `nextest-shuffle-isolation-lints-poc.md`

**Exceptions (legitimate use in production code)**:

When legitimately needed in production code (e.g., inside the real Clock implementation), allow individually with `#[allow(clippy::disallowed_methods)]`. As a rule, all code should go via Mocks (per the K-3 design).

#### B. Order Independence (advisory, nightly only)

Found in the POC: **on stable Rust, `--shuffle` cannot be required in CI** (`-Z unstable-options` is required).

**stable**: skip. As an alternative, prevent order dependence via code review + test design discipline.

**nightly profile (optional)**:

```bash
cargo +nightly test --tests -- -Z unstable-options --shuffle --test-threads=1
```

In projects whose CI workflow has a nightly profile, run as advisory (failure does not stop CI). When order dependence is uncovered, fix it explicitly under the `Negative Assertions` / `Isolation Properties` categories.

#### C. Determinism Check (advisory)

Forcing clock / RNG mocks is indirectly enforced by disallowed-methods in clippy.toml (deny direct calls -> force going through mocks).

Confirm supplementally in review-worker Category E (Final Check of Test Code) that "tests do not depend on clock / RNG / env" (revised in I-4).

### Retrofit of existing tests

Adding clippy.toml may produce many violations in existing tests. Phased gating:

| Stage | Application |
|------|------|
| Initial (advisory) | `-W clippy::disallowed_methods` (warning only). Report violations |
| Mid | Apply `-D` to new and modified parts; grandfather existing code with `#[allow]` |
| Mature | `-D` blocking in all code. `#[allow]` justified through individual review |

### .NET / Node.js (TBD)

- .NET: `dotnet test --blame-hang` + parallel configuration in `xunit.runner.json` leaves room for order-independence verification. `Stryker.NET` test-isolation check
- Node.js: `vitest --shuffle` (v1.6+) works by default / custom ordering with `jest --testSequencer`

To be finalized in a future POC or I implementation extension. The Rust side is established by this QC15.

### Linkage

- **K-3 (Architecture for Testability)**: design.md declares Mock points / Clock injection / RNG injection / External I/O isolation / Test fixtures. The calls forbidden by the QC15 lint are **only allowed via the Mocks declared in K-3**, establishing the design <-> enforcement round-trip loop
- **I-1 (_TestFocus 6 categories)**: the two categories `Negative Assertions` / `Isolation Properties` directly correspond to QC15. Quality properties are guaranteed from the test design stage
- **review-worker Category E (I-4)**: confirms "tests do not depend on clock / RNG / env"

### Notes

- QC14 (UI Smoke Render, E-3) is not yet implemented
- QC15 is **established by this implementation**
- QC16 (Regression Gate, J-9) is implemented in f7a03f6

---

## QC16: Regression Gate (added in J-9)

> Source: `.claude/_docs/plans/dapper-hardening-orchestrator.md` root cause J (J-9).
> Regression is a cross-cutting type (see `regression-test-policy/SKILL.md`). Tests with regression markers may exist at every layer (UT / CT / IT / ST / E2E).

### Purpose

Mechanically prevent new bugs from being introduced by fixes by requiring all **all-layer + regression-marked tests** to PASS at PR / merge time.

### Naming convention for regression-marked tests

Follow the conventions in `regression-test-policy/SKILL.md`:

| Language / framework | Pattern |
|---|---|
| Rust | `fn regression_issue_NNN_<description>()` |
| TypeScript / JavaScript | `it('regression #NNN: <description>', ...)` |
| C# / .NET | `[Fact] public void Regression_Issue_NNN_<Description>()` |

### Auto-collection and CI integration

Run the following in the PR / merge workflow:

```bash
# Rust: grep and run regression tests
cargo test --workspace -- regression_issue_

# TypeScript / Playwright
npx playwright test --grep "regression #"

# .NET / xUnit
dotnet test --filter "FullyQualifiedName~Regression_Issue_"
```

CI workflow template (generated by `/setup-ci`; revision required for J-9):

```yaml
- name: Regression Gate (QC16)
  run: |
    # Run regression tests across all layers
    cargo test --workspace -- regression_issue_ 2>&1 | tee regression-rust.log
    npx playwright test --grep "regression #" 2>&1 | tee regression-ts.log
    # Fail CI on failure
```

### Confirmation during Phase Review

In `spec-implement/SKILL.md` Step 3.5.2 (review-worker delegation), confirm that regression tests have been implemented for the bug-related tasks fixed in this Phase:

- The task has `_BugFix: true` + `_RegressionBugId: BUG-NNN` (spec-tasks Step 7 Check 21)
- A corresponding regression test exists (confirm by file grep)
- The regression test is PASSING

### Combined use with existing tests

QC16 is **used together** with existing QC3 (test) / QC7 (Integration Verification) / QC13 (Branch Coverage):

- QC3 / QC7 run **all tests**
- QC16 extracts only **tests with the regression marker** and runs them as a separate step (on failure, signals "regression broke")
- QC16 is **always blocking** (not advisory; to immediately detect new bugs introduced by fixes)

### Retrofit of existing specs

Warning when existing bug-fix commits do not follow the `regression_issue_*` naming convention. Required from the next version on for new bug fixes.

### Notes

- QC14 has been implemented as the **Component Test (CT) Gate** (H-1, dapper-hardening). Originally planned for E-3, then re-assigned to H-1
- QC15 (UT Properties Gate, I-2) is implemented
- QC16 is a **CI gate** (blocking on PR / merge). Local execution within Phase Review is indirectly covered by QC3 / QC7
- E-3 UI Smoke Render has been re-assigned to **QC17** (below)

---

## QC17: UI Smoke Render (added in E-3, dapper-hardening)

> Source: `.claude/_docs/plans/dapper-hardening-orchestrator.md` root cause E (E-3).
> CT (QC14) verifies the reactivity of a single component; this QC17 is the **system-wide UI smoke** (start a headless browser via playwright, render the entire AppRoot -> all testid elements appear in the DOM).

### Purpose

While CT (QC14) verifies the reactivity of each component in isolation, an **AppRoot-level smoke** combining all components is needed. Per Phase, verify "no placeholder commit exists" and "all testids appear in the compiled HTML".

Responsible for **detecting at the Phase Review stage** the "pure-helper UT + data-testid skeleton + placeholder view!" anti-pattern that occurred in dapper-hardening Phase 4.

### Verification content

```bash
# Leptos / Trunk / WASM
cargo leptos serve &
SERVER_PID=$!
sleep 5

# Visit / in a headless browser
npx playwright test tests/smoke/ui-smoke.spec.ts

kill $SERVER_PID
```

```typescript
// tests/smoke/ui-smoke.spec.ts (auto-generated example)
import { test, expect } from '@playwright/test';

test('UI smoke: AppRoot renders with required testids', async ({ page }) => {
  await page.goto('/');
  await page.waitForLoadState('networkidle');

  // Extract testids added in this Phase from design.md Phase Deliverables (K-4)
  const requiredTestids = ['folder-tree', 'thumbnail-grid', 'detail-viewer'];

  for (const testid of requiredTestids) {
    await expect(page.locator(`[data-testid="${testid}"]`)).toBeVisible({
      timeout: 5_000,
    });
  }

  // Confirm the count of testids is at or above the expected minimum
  const allTestids = await page.locator('[data-testid]').count();
  expect(allTestids).toBeGreaterThanOrEqual(requiredTestids.length);
});
```

### Per-Phase phased growth

In sync with design.md Phase Deliverables (K-4), the required testid count increases as Phases progress:

| Phase | Required testids (example) | Delta |
|---|---|---|
| Phase 1 (Core domain) | (no UI, QC17 SKIP) | - |
| Phase 2 (HTTP server) | (no UI, QC17 SKIP) | - |
| Phase 3 (UI skeleton) | `app-root` | +1 |
| Phase 4 (component implementation) | `folder-tree`, `thumbnail-grid`, `detail-viewer` | +3 |
| Phase 5 (feature complete) | `info-panel`, `toolbar` | +2 |

### Action on failure

| Result | Action |
|------|----------|
| All testids appear | PASS; continue Phase Review |
| Fewer testids than expected / specific testids missing | **FAIL (placeholder detected)**: revert the implementation task of the affected component to `[-]` and rework (add a new category to the spec-implement Step 3.5.1.5 failure send-back rules) |
| Server failed to start | FAIL (possible environment deficiency; check Required Build Tools) |

### Separation of responsibilities from CT (QC14)

- **QC14 (Component Test)**: reactivity of a single component (mount + signal + DOM) -- runs on each component task in Phase 4
- **QC17 (UI Smoke Render)**: AppRoot-level smoke -- runs in Phase Review (Phase-level quality gate)
- Both are required: CT to confirm each component works, Smoke to confirm the whole composition works

### Implementation stages

- **Initial (advisory)**: warning only. Wait for existing specs to retrofit
- **Mid**: blocking in Phase Review. Send back under the FAIL (placeholder detected) classification
- **Mature**: fully linked to Phase Deliverables (K-4). Phase-level phased growth is mechanically verified in CI
