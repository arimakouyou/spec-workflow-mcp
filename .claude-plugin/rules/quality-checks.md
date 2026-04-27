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

> spec-test-design / spec-tasks / parallel-worker / review-worker / spec-verify が参照する **テスト分類の正規定義**。
> 出典: `.claude/_docs/plans/dapper-hardening-orchestrator.md` 根本原因 J（J-3）。

各テスト層は **明確な責務範囲** を持ち、責務外のテストは別の層に振る。E2E に個別機能テストを書く / IT に UI 検証を含める / smoke に full integration を入れる、のような責務逸脱は禁止。

### 7 層テスト分類

| 層 | 責務 | 範囲 | 実行時間目安 | fixture | 実行時期 |
|---|------|------|:--------:|:------:|:------:|
| **UT** (Unit Test) | pure logic（仕様充足 + 仕様外不在） | 単関数 | ms | 不要 | TDD サイクル毎 / Phase Review / PR / merge |
| **CT** (Component Test) | component reactivity（mount → signal → DOM 観測） | 単 component | 数秒 | mock signal | Phase Review / PR / merge |
| **IT** (Integration Test) | **backend HTTP API only** | server crate | 秒〜十秒 | 実 DB / TempDir | backend Phase 完了後 / PR / merge |
| **ST** (System Test) | **単一機能の full-stack**（UI 操作 → backend → UI 反映） | UI + server (機能 1 個分) | 数秒〜十秒 | 実 server + fixture | 対象機能 Phase 末尾 / PR / merge |
| **smoke** | boot + wiring（全 method）+ 型境界 | system 全体 | 30s〜2m | 不要 | 各 Phase Review |
| **E2E** (End-to-End) | **user journey only** | 全機能横断 | 分〜十数分 | 実 server + 完全 fixture | Final Gate のみ |
| **Regression** (cross-cutting type) | 既知バグ再発防止 | UT/CT/IT/ST/E2E すべての層に **横断的に** mark | 各層と同じ | 各層と同じ | PR / merge（必須） |

### 各層の詳細

#### UT (Unit Test)
- **検証内容**: 仕様充足（happy path / boundary）+ **仕様外不在**（mutation 禁止 / 副作用ゼロ / 想定外入力で panic しない）
- **FIRST 原則必須**: Fast / Isolated / Repeatable / Self-Validating / Timely
- **外部依存禁止**: clock / RNG / env / fs / HTTP / DB の直接呼出は禁止（Mock 経由のみ許容）
- **実装**: Rust は inline `#[cfg(test)] mod tests`、.NET は xUnit、Node は vitest など
- **`_TestFocus` 6 カテゴリ**: Happy Path / Boundary Values / Error Handling / Edge Cases / **Negative Assertions** / **Isolation Properties**

#### CT (Component Test)
- **検証内容**: component を mount し、signal 操作・event dispatch で reactivity が機能するか
- **対象**: UI フレームワーク (Leptos / Blazor / React など) の component 内部の Resource / Suspense / on:click / on:submit / Effect の挙動
- **実装手段**:
  - Leptos: `wasm-bindgen-test` + `wasm-pack test --headless --chrome`（実用性 POC: `wasm-bindgen-test-leptos-poc.md`）
  - .NET Blazor: bUnit
  - React/Vue: @testing-library
- **責務外**: pure logic（UT で十分）/ 実 server 通信（IT or ST）

#### IT (Integration Test)
- **検証内容**: backend の HTTP API endpoint の動作（status code / response body / DB 状態変化 / 認証認可）
- **責務範囲**: server crate のみ。**フロントの Resource → server fn 境界を含めない**（含めるなら CT or ST）
- **実装**: `tower::ServiceExt::oneshot` で Axum Router 直接呼び出し / TestClient で end-point 試験 など
- **fixture**: 実 DB（TempDir / docker-compose.test.yml）
- **責務外**: UI 操作 / DOM 検証 / pure logic

#### ST (System Test)
- **検証内容**: 単一機能の full-stack 動作（UI でユーザー操作 → backend が応答 → UI に反映）
- **対象機能の例**: 「ログイン機能のみ」「検索機能のみ」「ズーム機能のみ」
- **責務外**: 複数機能の連鎖（E2E 責務）/ pure logic（UT）/ component reactivity 単独（CT）
- **実装**: Playwright / Selenium で実 server 起動 + UI 操作

#### smoke
- **検証内容**: 4 層構造
  - L1 Health: `/health`, `/api/health`, `/healthz` への GET
  - L2 Wiring: design.md の各 `### API-N:` から path / method を抽出。全 method × 全 endpoint で **5xx を出さないこと**（POST/PUT/PATCH は空ボディ `{}`、DELETE はプレースホルダ ID で送信）
  - L3 Auth: design.md で「Auth: required」の endpoint に Authorization なしで送信して 401
  - L4 入力境界: 各 path/query/body field の **型境界値**（String 空文字 / maxLength+1 / int overflow / enum 未定義値 / Optional 省略 / 不正 UUID）で 400/422
- **責務外**: 業務ロジック（IT / UT で検証）/ 複合境界（UT/IT）/ ビジネス境界（IT/UT）/ user journey（E2E）

#### E2E (End-to-End)
- **検証内容**: 複数機能の連鎖を含む user journey（例: ログイン → 検索 → 結果クリック → 詳細 → ログアウト）
- **責務外**: 個別機能のテスト（ST 責務）/ 単一 endpoint の応答確認（IT or smoke 責務）
- **実行時期**: Final Gate のみ。Phase 内では走らない

#### Regression（cross-cutting type）
- **位置**: 層ではなく **type**。UT/CT/IT/ST/E2E のすべての層に横断的に mark が付く
- **命名規則** (`regression-test-policy/SKILL.md` 参照):
  - Rust: `fn regression_issue_NNN_<description>()` / TypeScript: `it('regression #NNN: ...')`
- **CI gate**: PR / merge 時に regression marked テストの全件 PASS が必須（QC16 で gate 化予定）

### 境界違反パターン（よくある誤り）

#### IT に UI 検証が混入
- **誤り**: IT-N で `assert dom.querySelector('[data-testid=...]')` を含める
- **正しい**: UI 検証は CT (component 単独) か ST (full-stack 単一機能) か E2E (user journey)
- **検出**: `spec-test-design/SKILL.md` Step B Check 19 (TEST_LAYER_BOUNDARY)

#### E2E に個別機能テストが混入
- **誤り**: `e2e-zoom-rotate.spec.ts` のような単一機能テストを E2E と称する
- **正しい**: ST に振る (`st-zoom-rotate.spec.ts` または同等)
- **検出**: `spec-test-design/SKILL.md` Step B Check 19

#### smoke に full integration が混入
- **誤り**: smoke で実データを作成して business logic を検証
- **正しい**: smoke は wiring + 型境界のみ。business logic は IT / UT
- **検出**: smoke 実行時間が 5 分超え（`spec-implement/SKILL.md` Step 3.5.1.5 で警告）

#### ST が CT で代替できる
- **疑問**: 「単一機能の full-stack」と称するが実 server を使わなくても CT で機能テストできる場合
- **判断**: server fn コアロジック単独なら UT、UI + signal 統合なら CT、UI → server → UI の動作観察が必要なら ST
- **検出**: spec-test-design 自己レビューで「server 起動が本当に必要か」をチェック

### 参照

- `regression-test-policy/SKILL.md`: Regression 命名規則 / CI gate / Traceability Matrix
- `spec-test-design/SKILL.md`: 各層の Subagent (A: UT / B: IT / C: E2E / D: CT / E: ST) と Step B Check
- `.claude/_docs/plans/dapper-hardening-orchestrator.md`: J-3 の起点と関連項目（K / I / H / E）

---

## タスクレベルチェック（QC1〜QC6, QC8〜QC9）

コミット前・PR 単位で実行するチェック。`/setup-ci` が生成する `ci.yml` および `scheduled-quality.yml` に組み込まれる。

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

- `pub` なアイテム（関数、構造体、フィールド等）に doc comment (`///`) が欠けている場合に警告を出す
- **Advisory**: 警告は報告するがコミットをブロックしない（`|| true`）
- review-worker のカテゴリ A（Style）で doc comment の有無を確認する際の補助情報として使用
- `/generate-api-docs` の doc comment ギャップ分析と併用することで、API スキーマの自然言語説明カバレッジを向上させる

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
# Step 1: Detect Leptos project（ブラケット付きヘッダでマッチ）
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

- `package-lock.json` が存在する場合のみ実行
- **Blocking**: high / critical の脆弱性が検出された場合は失敗
- `yarn.lock` の場合は `yarn audit --level high`（Yarn v1）または `yarn npm audit`（Yarn v2+）

### unused code detection (Node.js — advisory)

```bash
npx knip --no-progress 2>&1 | head -50
```

- `knip` がプロジェクトに設定されている場合のみ実行
- **Advisory**: 未使用ファイル・エクスポートを報告するがブロックしない
- 未導入の場合はスキップ（`npx knip` が失敗したら無視）

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
- `--no-restore`: `dotnet restore` が別途実行済みの前提（チェーン内での冗長 restore を回避）
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
# dotnet list package --vulnerable は常に exit code 0 を返すため、出力をパースする
OUTPUT=$(dotnet list package --vulnerable --include-transitive 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -qE "(Critical|High)"; then
  echo "Critical or high severity vulnerabilities found"
  exit 1
fi
```

- **Blocking**: If high/critical vulnerabilities are found, the check **fails**
- `--include-transitive`: Checks both direct and transitive dependencies
- `cargo audit` と異なり exit code で判定できないため、出力の grep が必須

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

コード重複を検出する。全プロジェクトタイプに適用可能。

```bash
npx jscpd --min-lines 10 --min-tokens 50 \
  --ignore '**/target/**,**/node_modules/**,**/dist/**' \
  --reporters consoleFull .
```

- **Advisory**: 重複は報告するがコミットをブロックしない
- 検出ツール未インストール時はスキップ
- 週次定期チェック（`--with-scheduled`）で Issue 作成と組み合わせて使用
- Rust プロジェクトでも `jscpd` は有効（テキストベースの重複検出）

代替ツール:
- Rust: `cargo install cargo-clone-detection`（利用可能な場合）
- Python: `pylint --disable=all --enable=duplicate-code`

## QC9: Lockfile Verification (P4-03)

> 🔗 **Hook**: `lockfile-guard.sh` (PreToolUse — commit gate)

パッケージマネージャの lockfile がリポジトリにコミットされていることを検証する。
lockfile の欠如は再現不可能なビルドにつながるため、**Blocking** チェックとする。

### 検出対象

| パッケージマネージャ | マニフェスト | lockfile |
|-------------------|------------|---------|
| npm | `package.json` | `package-lock.json` |
| yarn | `package.json` | `yarn.lock` |
| pnpm | `package.json` | `pnpm-lock.yaml` |
| Cargo (Rust) | `Cargo.toml` | `Cargo.lock` |
| Go | `go.mod` | `go.sum` |
| NuGet (.NET) | `*.csproj` | `packages.lock.json` |
| Poetry (Python) | `pyproject.toml` | `poetry.lock` |
| Bundler (Ruby) | `Gemfile` | `Gemfile.lock` |

### チェックコマンド

```bash
# マニフェストファイルと対応する lockfile の存在を確認
FAIL=false

# Node.js (いずれか 1 つで OK)
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

# .NET (packages.lock.json は RestorePackagesWithLockFile 有効時のみ生成される)
# Central Package Management 使用時は Directory.Packages.props の存在を確認
if find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  if find . -maxdepth 3 \( -name '*.csproj' -o -name 'Directory.Build.props' -o -name 'Directory.*.props' \) -exec grep -lq 'RestorePackagesWithLockFile' {} + 2>/dev/null; then
    if [ ! -f packages.lock.json ] && ! find . -maxdepth 3 -name 'packages.lock.json' -print -quit 2>/dev/null | grep -q .; then
      echo "FAIL: RestorePackagesWithLockFile enabled but packages.lock.json not found"
      FAIL=true
    fi
  fi
fi

# .gitignore で除外されていないことを確認
for lockfile in package-lock.json yarn.lock pnpm-lock.yaml Cargo.lock go.sum poetry.lock Gemfile.lock packages.lock.json; do
  if [ -f "$lockfile" ] && git check-ignore -q "$lockfile" 2>/dev/null; then
    echo "FAIL: $lockfile is gitignored — lockfile must be committed for reproducible builds"
    FAIL=true
  fi
done
```

| 条件 | 判定 | アクション |
|------|------|-----------|
| lockfile が存在し git 管理下にある | PASS | — |
| lockfile が `.gitignore` で除外されている | FAIL | `.gitignore` から除外を解除し commit |
| lockfile が存在しない（マニフェストあり） | FAIL | install コマンドを実行し lockfile を生成・commit |
| マニフェスト自体が存在しない | SKIP | 対象外 |

> **CI 連携**: `scheduled-quality-standalone.yml` にこのチェックが組み込まれている。
> lockfile 未コミットの場合は週次スキャンで Issue が自動作成される。

> **執行レベル**:
> - **エージェント/ローカル**: Blocking — lockfile 未コミットの場合はコミットをブロックする
> - **PR CI (`ci.yml`)**: Blocking — lockfile 未コミットの場合は CI を失敗させる
> - **週次スキャン (`scheduled-quality.yml`)**: Advisory (`continue-on-error: true`) — 検出時に Issue を自動作成するが、ワークフロー全体は停止しない

## QC10: Documentation Lint (P5-03)

> 🔗 **Hook**: `post-edit.sh` (PostToolUse — markdownlint auto-fix)

Markdown ファイルのフォーマット整合性とリンク健全性を検証する。全プロジェクトタイプ共通。

### markdownlint（フォーマットチェック）

```bash
npx markdownlint-cli2 "**/*.md" "#node_modules" "#target" "#dist"
```

- `.markdownlint.yaml` が存在すればそのルールに従う
- 未設定時はデフォルトルール適用（推奨: MD013 line-length を無効化）
- 自動修正: `npx markdownlint-cli2 --fix "**/*.md" "#node_modules" "#target" "#dist"`

### markdown-link-check（リンク検証）

```bash
find . -name '*.md' -not -path '*/node_modules/*' -not -path '*/target/*' -not -path '*/.spec-workflow/*' | \
  xargs -I {} npx markdown-link-check {} --config .markdown-link-check.json 2>&1 | tee /tmp/link-check-output.txt
```

- `.markdown-link-check.json` が存在すればその config に従う
- 未設定時はデフォルト（外部リンクの 429 Too Many Requests は無視推奨）

| 条件 | 判定 | アクション |
|------|------|-----------|
| フォーマット違反なし & リンク切れなし | PASS | — |
| フォーマット違反あり | WARN | `markdownlint-cli2 --fix` で自動修正可 |
| リンク切れあり | WARN | リンク先を更新 or 削除 |

> **執行レベル**:
> - **エージェント/ローカル**: Advisory — 報告するがコミットはブロックしない
> - **PR CI (`ci.yml`)**: Advisory (`continue-on-error: true`) — PR コメントで報告
> - **週次スキャン (`scheduled-quality.yml`)**: Advisory — 検出時に Issue 作成
>
> **doc-crossref.md との関係**: QC10 は機械的なフォーマット検証とリンク切れ検出を担当。
> `doc-crossref.md` は spec-workflow 固有のセマンティック参照整合性（Requirements Traceability 等）を対象とする。

## QC11: SAST / Security-Focused Static Analysis (P6-04)

セキュリティに特化した静的コード解析を実行する。QC2 (clippy) の一般 lint に加えて、
セキュリティ関連の lint グループを明示的に有効化する。

### Rust / Leptos

```bash
cargo clippy --all-targets -- -W clippy::suspicious -W clippy::correctness -W clippy::complexity
```

- `clippy::suspicious`: 疑わしいコードパターン（意図しない動作の兆候）
- `clippy::correctness`: 正確性に関する問題（バグの可能性が高い）
- `clippy::complexity`: 不必要な複雑性（攻撃面の拡大につながる）

### Node.js

```bash
# ESLint + security plugin
npx eslint --plugin security --rule 'security/detect-object-injection: warn' .

# または CodeQL（GitHub Actions 経由）
# codeql.yml ワークフローで自動実行
```

### .NET

```bash
# .NET Analyzers (CAxxxx) + Roslynator + StyleCop — QC12.2 の dotnet build -warnaserror で実行済み
# 追加のセキュリティ重点チェック:
dotnet build --no-restore -p:AnalysisLevel=latest-all 2>&1 | grep -E "(CA2[0-9]{3}|CA3[0-9]{3})" || true
```

- `CA2xxx`: Security-related analyzers (SQL injection, XSS, etc.)
- `CA3xxx`: Security design guidelines
- `AnalysisLevel=latest-all`: 全カテゴリの最新ルールを有効化
- CodeQL は GitHub Actions 経由で自動実行（C# 対応）

### 他の SAST ツール（代替）

| ツール | 対応言語 | 特徴 |
|--------|---------|------|
| CodeQL | JS/TS, Python, Go, Java | GitHub 組込み、公開リポジトリ無料 |
| Semgrep | 多言語 | ルールベース、OSS |
| SonarQube | 多言語 | エンタープライズ向け |

> **執行レベル**:
> - **エージェント/ローカル**: Advisory — 報告するがコミットはブロックしない
> - **PR CI (`ci.yml`)**: Advisory (`continue-on-error: true`)
> - **週次スキャン**: CodeQL の schedule トリガーで自動実行

---

## 統合レベル検証（QC7）

Phase Review および Final E2E Gate で実行する統合レベルの検証。タスクレベルチェック（QC1〜QC6, QC8〜QC9）とは独立したステップとして、Phase 完了時にのみ実行する。

## QC7: Integration Verification (Phase Review / Final E2E Gate)

Phase Review (3.5.1.5) および全Phase完了後の Final E2E Gate (セクション9) で実行する統合レベルの検証。
タスク単位の品質チェック（rustfmt, clippy, cargo test）とは独立したステップとして実行する。

### プロジェクトタイプ検出

以下の順で検出し、最初にマッチしたタイプを採用する:

```bash
# 1. Leptos フルスタック検出（ブラケット付きヘッダで誤検出を防止）
if grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null; then
  echo "leptos"
# 2. Rust API 検出（axum, actix-web, rocket 等）
elif grep -qE '(axum|actix-web|rocket)' Cargo.toml 2>/dev/null; then
  echo "rust-api"
# 3. .NET Blazor フルスタック検出（Leptos 相当）
elif find . -maxdepth 2 -name '*.csproj' -exec grep -l 'BlazorWebAssembly\|Microsoft.AspNetCore.Components.WebAssembly' {} + 2>/dev/null | head -1 | grep -q .; then
  echo "dotnet-blazor"
# 4. .NET API 検出
elif ls *.sln 2>/dev/null | head -1 | grep -q . || find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  echo "dotnet"
# 5. Node.js 検出
elif test -f package.json; then
  echo "nodejs"
# 6. いずれにも該当しない
else
  echo "generic"
fi
```

### Step B: ビルド検証（全プロジェクト共通・必須）

成果物のビルドが成功することを確認する。ビルド失敗は即座に FAIL とする。

| タイプ | コマンド | 備考 |
|--------|---------|------|
| Leptos | `cargo leptos build` | SSR + WASM 両方をビルド |
| Rust API | `cargo build` | リリースビルドは不要（デバッグビルドで十分） |
| .NET Blazor | `dotnet publish -c Release -p:PublishTrimmed=true` | WASM + Trim 検証を含む |
| .NET API | `dotnet build --no-restore -warnaserror` | Analyzer 警告をエラー化 |
| Node.js | `npm run build` | `build` スクリプトが package.json に存在する場合のみ。存在しない場合は SKIP（FAIL ではない）とし、ログに「build スクリプトなし」と記録 |
| Generic | `cargo build` or `dotnet build` or `npm run build` | 検出可能なビルドコマンドを実行。該当コマンドがない場合は SKIP とする |

### Step C: 統合テスト実行

統合テストファイルが存在する場合に実行する。存在しない場合の判定（優先順）:
- design.md の Excluded Test Environments に当該統合テスト環境の除外宣言がある → **SKIP（設計時除外）**
- 上記の除外宣言はなく、test-design.md に当該統合テスト仕様が定義されている → **FAIL（実装漏れ）** — テストファイルの作成が必要
- 上記いずれにも該当せず、test-design.md に当該統合テスト仕様が未定義 → **SKIP（設計上不要）** — ログに理由を記録し Expert Team Review で補完

**「test-design.md に統合テスト仕様が定義されている」の客観的判定基準**（オーケストレータはこのルールに厳密に従うこと）:
- test-design.md 内に `## Integration Test Specifications` セクション見出しが存在する
- かつ、そのセクション内に `### IT-` で始まる見出しが 1 件以上存在する（例: `### IT-1: APIエンドポイント統合テスト`）
- 上記 2 条件を共に満たす場合のみ「仕様あり」とみなす。条件を満たさない場合は「仕様なし」

```bash
# Rust: 統合テストの存在確認（tests/ ディレクトリ内の .rs ファイル。e2e/ と unit/ は再帰的に除外）
# 検出対象: tests/integration*/ 配下の .rs ファイル、または tests/ 直下の .rs ファイル
find tests -type f -name '*.rs' ! -regex '.*/tests/\(e2e\|unit\)/.*' -print -quit 2>/dev/null

# .NET: 統合テストプロジェクトの存在確認
find . -maxdepth 3 \( -name '*Integration*Tests*.csproj' -o -name '*IntegrationTests*.csproj' \) -print -quit 2>/dev/null

# Node.js: 統合テストスクリプトまたはファイルの存在確認
grep -q '"test:integration"' package.json 2>/dev/null || \
  find tests test __tests__ -type f -name 'integration*' -print -quit 2>/dev/null
```

| タイプ | コマンド |
|--------|---------|
| Rust | `cargo test --tests --quiet` |
| .NET | `dotnet test --filter "Category=Integration" --no-build --verbosity quiet`（テストに `[Trait("Category","Integration")]` 必須） |
| Node.js（スクリプトあり） | `npm run test:integration` |
| Node.js（ファイルのみ） | `npm test -- --testPathPattern=integration` |

### Step D: スモークテスト（API プロジェクトのみ）

API サーバを一時的に起動し、ヘルスチェックエンドポイントへの疎通を確認する。

**コンテナベース（docker-compose.yml が存在する場合 — 優先）:**

```bash
# docker-compose でサービスを起動
docker-compose up -d
sleep 10
```

ヘルスチェック実行後:
```bash
docker-compose down
```

**直接起動（docker-compose.yml が存在しない場合 — フォールバック）:**

```bash
# プロジェクトタイプに応じてサーバ起動コマンドを切り替え
if [ -f Cargo.toml ]; then
  START_CMD="cargo run"
elif SLN=$(ls *.sln 2>/dev/null | head -1) && [ -n "$SLN" ]; then
  # .sln がルートに存在する前提（単一 .sln）
  # Web SDK プロジェクトを優先（クラスライブラリは dotnet run 不可）
  ENTRY_PROJECT=$(dotnet sln "$SLN" list 2>/dev/null | tail -n +3 | while read -r proj; do
    [ -f "$proj" ] && grep -q 'Microsoft.NET.Sdk.Web' "$proj" && echo "$proj" && break
  done)
  # Web SDK が見つからなければ先頭プロジェクトにフォールバック
  [ -z "$ENTRY_PROJECT" ] && ENTRY_PROJECT=$(dotnet sln "$SLN" list 2>/dev/null | tail -n +3 | head -1)
  START_CMD="dotnet run --project ${ENTRY_PROJECT:-.}"
elif [ -f package.json ]; then
  # package.json に dev スクリプトがあれば優先的に使用し、なければ start スクリプトを確認
  if command -v node >/dev/null 2>&1 && \
     node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.dev ? 0 : 1)" >/dev/null 2>&1; then
    START_CMD="npm run dev"
  elif command -v node >/dev/null 2>&1 && \
       node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.start ? 0 : 1)" >/dev/null 2>&1; then
    START_CMD="npm start"
  else
    echo "Step D: Node.js プロジェクトで start / dev スクリプトが存在しないため、スモークテストをスキップします。" >&2
    exit 0
  fi
else
  echo "Step D: 対応するプロジェクトタイプ（Rust/.NET/Node.js）が見つからないため、スモークテストをスキップします。" >&2
  exit 0
fi

# バックグラウンドでサーバ起動（新しいセッションで確実に停止可能にする）
setsid sh -c "$START_CMD" &
SERVER_PID=$!
trap "kill -- -$SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null" EXIT
sleep 5

# ヘルスチェック（/health と /api/health を順に試行）
HEALTH_STATUS="000"
for ENDPOINT in "/health" "/api/health" "/healthz"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT:-3000}${ENDPOINT}" 2>/dev/null)
  if [ "$STATUS" = "200" ]; then
    HEALTH_STATUS="200"
    break
  fi
done

# クリーンアップ
kill -- -$SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

# PASS/FAIL 判定
if [ "$HEALTH_STATUS" != "200" ]; then
  echo "Step D: ヘルスチェック失敗 — いずれのエンドポイントからも 200 が返りませんでした。" >&2
  exit 1
fi
```

**スモークテストの SKIP 条件**（設計上テストが不要・不可能な場合のみ）:
- ヘルスチェックエンドポイントが設計書に未定義
- サーバ起動コマンドが不明（Cargo.toml に `[[bin]]` セクションがない等）
- Node.js プロジェクトで `start` / `dev` スクリプトが存在しない
- 対応するプロジェクトタイプ（Rust/.NET/Node.js）が検出されない

**環境不備の FAIL 条件**（ツール・ランタイム不足の場合 — 環境依存のスキップは一切許可しない）:
- Docker/コンテナランタイムが未インストール、または `docker` / `docker-compose` コマンドが存在しない・権限不足で実行できない（`docker-compose up` の起動失敗を含む）
- Chrome/ブラウザが未インストール
- DB/キャッシュ起動に必要なツールが未インストール
- サーバ起動に必要なランタイム（cargo, dotnet, node 等）が未インストール
- 外部依存（DB、キャッシュ等）が必要でローカル起動できない（Docker/testcontainers で起動できるようにするのが設計の責務）

環境不備 FAIL 時は、不足ツールを明示してユーザーにエスカレートする。design.md / test-design.md の Required Tools テーブルの Install Command を提示すること。特に `docker-compose.yml` が存在しスモークテストで `docker-compose up` を実行する場合、コマンド未存在・実行権限不足・起動失敗はいずれも FAIL（環境不備）として直ちに STOP し、SKIP/PASS として扱わないこと。

**テスト実装漏れの FAIL 条件**:
- test-design.md に E2E テスト仕様が定義されているのにテストファイルが存在しない → FAIL（実装漏れ）
- test-design.md に IT 仕様が定義されているのに統合テストファイルが存在しない → FAIL（実装漏れ）

SKIP 時は必ずログに理由を記録し、Expert Team Review で補完する。

### 統合検証の結果判定

| 結果 | 条件 | アクション |
|------|------|----------|
| **PASS** | ビルド成功 + 全テストパス + スモーク OK（SKIP(設計上不要)/SKIP(設計時除外)/SKIP(ビルドコマンド未検出) を含む） | 次ステップに進む |
| **FAIL (ビルド)** | ビルド失敗 | ビルドエラーを分析し、根本原因タスクを特定して差し戻し |
| **FAIL (統合テスト)** | 統合テスト失敗 | 失敗テストのエラーを分析。Phase内タスク → 差し戻し、前Phase → ユーザーエスカレート |
| **FAIL (スモーク)** | ヘルスチェック失敗（SKIP条件に該当しない場合） | 起動ログを分析し根本原因を特定して差し戻し |
| **FAIL (環境不備)** | 必須ツール・ランタイム未インストール | 不足ツールをユーザーに報告し、Required Tools テーブルの Install Command を提示。実装を停止（STOP） |
| **FAIL (実装漏れ)** | test-design.md にテスト仕様ありだがテストファイルなし | テスト実装の漏れとしてユーザーに報告 |
| **SKIP (設計上不要)** | テスト仕様自体が存在しない（設計書に未定義） | ログに SKIP 理由を記録し、次ステップに進む。Expert Team Review で補完 |
| **SKIP (設計時除外)** | design.md の「Excluded Test Environments」で明示的に除外 | 除外理由をログに記録し、次ステップに進む |

## QC13: Branch Coverage (Advisory → 段階的 Gate 化)

例外パス・分岐網羅の不足を露呈するため、line coverage と branch coverage を**別々に**計測する。
plan-redesign #3「分岐カバレッジ別ゲート化」に対応。

### 計測コマンド

#### Rust / Leptos

```bash
# cargo-llvm-cov (推奨、line + branch を同時取得)
cargo install cargo-llvm-cov --locked
cargo llvm-cov --branch --summary-only
# JSON 出力で threshold check 可能:
# cargo llvm-cov --branch --json --output-path coverage.json
```

#### .NET

```bash
# coverlet (XPlat) で line + branch
dotnet test --collect:"XPlat Code Coverage" \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura
# Cobertura XML から line-rate / branch-rate を抽出して threshold 比較
```

#### Node.js

```bash
# vitest --coverage (V8 provider) で line + branch
npx vitest run --coverage --coverage.reporter=json-summary
# coverage/coverage-summary.json から total.lines.pct / total.branches.pct を抽出
```

### 推奨 Threshold (初期、段階的に引き上げ)

| 段階 | line | branch | 適用先 | gate 化 |
|------|:---:|:---:|--------|:------:|
| 初期 (advisory) | 70% | 50% | scheduled-quality (週次) | report-only |
| 中期 | 80% | 65% | scheduled-quality + ci.yml | warning |
| 成熟 | 85% | 75% | ci.yml (PR 時) | blocking |

### 段階的 gate 化の方針

- **初期段階**: `scheduled-quality.yml` でのみ計測。閾値未達は週次 Issue で報告（advisory）
- **中期**: `ci.yml` に追加するが `continue-on-error: true` で warning 扱い
- **成熟**: `ci.yml` でブロッキング。`continue-on-error: false` +
  `--fail-under=<line>` / branch threshold 失敗で CI Fail

### Branch coverage が line coverage より低い場合の解釈

例外パス・エラーハンドリングのテストが不足している強い signal。
review-worker の E (Tests) / E2-4 (Edge cases and error paths are tested) で
finding を起票する根拠として使う。

**典型例**:

- line: 85%, branch: 40% → happy path のみテスト、`Result::Err` / `match` の各分岐がテストされていない
- line: 60%, branch: 55% → 単純にテスト総量が不足

両指標を分離して見ることで「コード行は通したが分岐は通していない」状態を捕捉できる。

---

## QC14: Component Test (CT) Gate (H-1 で新設)

> 出典: `.claude/_docs/plans/dapper-hardening-orchestrator.md` 根本原因 H（H-1）。
> POC `wasm-bindgen-test-leptos-poc.md` で実用性確認済（Leptos 0.7 + wasm-bindgen-test、5 秒で 3 tests PASS）。

### 目的

UT (pure logic) と E2E (user journey) の中間層として **CT (Component Test)** を定義し、component reactivity（mount → signal → DOM）を Phase 内で継続検証する。Phase 4 placeholder commit パターン（pure helper UT のみで `[x]` 完了する反パターン）を構造的に防ぐ。

### 責務範囲

`Test Taxonomy` セクション参照。CT は:

- **対象**: 単 component の reactivity（mount → signal 操作 → DOM 観測）
- **範囲**: UI 1 component
- **実行時間**: 数秒/test
- **fixture**: mock signal（design.md K-3 Architecture for Testability の宣言を経由）
- **責務外**: pure logic（UT）/ 実 server 通信（IT or ST）/ user journey（E2E）

### Rust / Leptos の場合

**Setup**（POC で確立した最小構成）:

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

**実行コマンド**:

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

        // signal を更新 / event を trigger
        let button = wrapper
            .query_selector("[data-testid='action-btn']")
            .unwrap().unwrap()
            .unchecked_into::<web_sys::HtmlElement>();
        button.click();
        tick().await;

        // DOM 観測
        let target = wrapper
            .query_selector("[data-testid='target-value']")
            .unwrap().unwrap();
        assert_eq!(target.text_content().unwrap(), "expected");
    }
}
```

詳細: `tdd-skills-rust/references/leptos-frontend-testing.md` セクション 6 参照。

### .NET / Blazor の場合

**bUnit** を使用（標準ツール、堅牢）:

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

詳細: `tdd-skills-dotnet/references/blazor-component-testing.md`（後続で整備、現時点では bUnit 公式ドキュメント参照）

### CI 統合

```yaml
- name: Component Test (QC14)
  run: |
    # Leptos: Firefox / geckodriver を install
    sudo apt-get install -y firefox-esr
    cargo test --target wasm32-unknown-unknown --lib
    # .NET / Blazor:
    dotnet test --filter "Category=ComponentTest"
```

### 段階的 gate 化

| 段階 | 適用 |
|------|------|
| 初期（advisory） | CT が無い component には warning（spec-tasks Step 7 Check 17/18 で検出） |
| 中期 | UI component task の `_Success` に「CT-N PASS」を必須化（H-4 / Check 18） |
| 成熟 | review-worker Category E で CT 不在を Moderate finding として起票（H-5） |

### POC で確認した制約

- **wasm-pack は不要**（cargo test --target wasm32-unknown-unknown で直接動作）
- **Firefox + geckodriver / Chromium + chromedriver のいずれかが CI に必要**
- production code の Resource / server fn 呼び出しは mock を介してテスト（design.md K-3 で宣言）

---

## QC15: UT Properties Gate (I-2 で新設)

> 出典: `.claude/_docs/plans/dapper-hardening-orchestrator.md` 根本原因 I（I-2）。
> POC 結果反映: `.claude/_docs/plans/nextest-shuffle-isolation-lints-poc.md` 参照。

### 目的

UT が **仕様の検証**（仕様充足 + 仕様外不在）を満たし、**外部依存ゼロ + 順序非依存 + 決定性**（FIRST 原則）を保証していることを CI で機械的に enforce する。

「実装時の UT は cargo test PASS（コードが動く）の確認ではなく、仕様の検証である」という frame を構造的に成立させる。

### 構成

#### A. External Dependency Lint（必須、blocking）

**clippy `disallowed-methods` を主柱**として採用（POC で動作確認済）。

`clippy.toml`（または `Cargo.toml` の `[workspace.lints.clippy]`）に以下を設定:

```toml
# clippy.toml
disallowed-methods = [
    # Clock 直接呼出（design.md K-3 Architecture for Testability で宣言された MockClock 経由のみ許可）
    { path = "std::time::SystemTime::now", reason = "use MockClock from design.md Architecture for Testability instead (K-3)" },
    { path = "std::time::Instant::now", reason = "use MockClock instead (K-3)" },
    { path = "chrono::Utc::now", reason = "use MockClock instead (K-3)" },
    { path = "chrono::Local::now", reason = "use MockClock instead (K-3)" },

    # RNG 直接使用
    { path = "rand::thread_rng", reason = "use injected MockRng (K-3)" },
    { path = "rand::random", reason = "use injected MockRng (K-3)" },

    # env 直接読取
    { path = "std::env::var", reason = "use injected config (K-3)" },
    { path = "std::env::var_os", reason = "use injected config (K-3)" },

    # fs 直接呼出（tempfile / TestFs 経由が望ましい）
    { path = "std::fs::read", reason = "use tempfile or injected fs adapter (K-3)" },
    { path = "std::fs::write", reason = "use tempfile or injected fs adapter (K-3)" },
    { path = "std::fs::read_to_string", reason = "use tempfile or injected fs adapter (K-3)" },

    # HTTP 直接呼出（mockito / wiremock 経由）
    { path = "reqwest::get", reason = "use mockito / wiremock (K-3)" },
    { path = "reqwest::blocking::get", reason = "use mockito / wiremock (K-3)" },
]
```

CI 実行コマンド（blocking）:

```bash
cargo clippy --all-targets --workspace -- -D clippy::disallowed_methods
```

**動作確認** (POC):
- `std::time::SystemTime::now` / `std::env::var` を直接呼出 → custom reason 付きで warning 検出
- `-D clippy::disallowed_methods` で deny-level 化 → CI fail
- 詳細: `nextest-shuffle-isolation-lints-poc.md` 参照

**例外（production code の legitimate 使用）**:

production code で正当に必要な場合（例: 実 Clock 実装内）は `#[allow(clippy::disallowed_methods)]` で個別許可。原則として全コードで Mock 経由（K-3 設計に従う）。

#### B. Order Independence（advisory、nightly のみ）

POC で判明: **stable Rust では `--shuffle` を CI で必須化できない**（`-Z unstable-options` 必須）。

**stable**: skip。代替として code review + test design discipline で order 依存を防ぐ。

**nightly profile（オプション）**:

```bash
cargo +nightly test --tests -- -Z unstable-options --shuffle --test-threads=1
```

CI workflow に nightly profile を持つプロジェクトでは advisory として実行（fail しても CI は止めない）。順序依存が判明したら `Negative Assertions` / `Isolation Properties` カテゴリで明示的に修正。

#### C. Determinism Check（advisory）

clock / RNG モックの強制は clippy.toml の disallowed-methods で間接的に enforce される（直接呼出を deny → mock 経由を強制）。

review-worker の Category E (Final Check of Test Code) で「test が clock / RNG / env に依存していないか」を補強的に確認（I-4 で改訂）。

### 既存テストの retrofit

clippy.toml を新設 → 既存 test で violation 多数発生する可能性あり。段階的 gate 化:

| 段階 | 適用 |
|------|------|
| 初期 (advisory) | `-W clippy::disallowed_methods`（warning のみ）。violation を report |
| 中期 | 新規・改修部分に `-D` 適用、既存は `#[allow]` で grandfathered |
| 成熟 | 全コードで `-D` blocking。`#[allow]` は個別 review で justify |

### .NET / Node.js 系（未確定）

- .NET: `dotnet test --blame-hang` + `xunit.runner.json` の parallel 設定で order independence 検証の余地。`Stryker.NET` のテスト独立性チェック
- Node.js: `vitest --shuffle` (v1.6+) は標準で動作 / `jest --testSequencer` でカスタム順序

将来別 POC または I 実装拡張時に確定する。Rust 側は本 QC15 で確立。

### 連携

- **K-3 (Architecture for Testability)**: design.md で Mock points / Clock injection / RNG injection / External I/O isolation / Test fixtures が宣言される。QC15 の lint で禁止される call は **K-3 で宣言された Mock 経由のみ許可** されるという design ↔ enforcement の往復ループが成立
- **I-1 (_TestFocus 6 カテゴリ)**: `Negative Assertions` / `Isolation Properties` の 2 カテゴリが QC15 と直接呼応。test 設計時から品質特性を担保
- **review-worker Category E (I-4)**: 「テストが clock / RNG / env に依存していないか」を確認

### 注意

- QC14 (UI Smoke Render, E-3) は未実装
- QC15 は **本実装で確立**
- QC16 (Regression Gate, J-9) は f7a03f6 で実装済

---

## QC16: Regression Gate (J-9 で新設)

> 出典: `.claude/_docs/plans/dapper-hardening-orchestrator.md` 根本原因 J（J-9）。
> Regression は cross-cutting type（`regression-test-policy/SKILL.md` 参照）。すべての層（UT / CT / IT / ST / E2E）に regression marker を付けた tests が含まれ得る。

### 目的

PR / merge 時に **全層 + regression marked テスト** の全件 PASS を必須化することで、修正による新規バグの流入を機械的に防ぐ。

### Regression marked テストの命名規則

`regression-test-policy/SKILL.md` の規約に従う:

| 言語 / フレームワーク | パターン |
|---|---|
| Rust | `fn regression_issue_NNN_<description>()` |
| TypeScript / JavaScript | `it('regression #NNN: <description>', ...)` |
| C# / .NET | `[Fact] public void Regression_Issue_NNN_<Description>()` |

### 自動収集と CI 統合

PR / merge workflow で以下を実行:

```bash
# Rust: regression test を grep して run
cargo test --workspace -- regression_issue_

# TypeScript / Playwright
npx playwright test --grep "regression #"

# .NET / xUnit
dotnet test --filter "FullyQualifiedName~Regression_Issue_"
```

CI workflow テンプレ（`/setup-ci` で生成、J-9 で改訂対応必要）:

```yaml
- name: Regression Gate (QC16)
  run: |
    # 全層 regression テスト実行
    cargo test --workspace -- regression_issue_ 2>&1 | tee regression-rust.log
    npx playwright test --grep "regression #" 2>&1 | tee regression-ts.log
    # 失敗したら CI fail
```

### Phase Review 時の確認

`spec-implement/SKILL.md` Step 3.5.2 (review-worker delegation) で、当該 Phase で修正したバグ系 task に対応する regression test が実装済みか確認:

- task に `_BugFix: true` + `_RegressionBugId: BUG-NNN` がある（spec-tasks Step 7 Check 21）
- 対応する regression test が存在する（ファイル grep で確認）
- regression test が PASS している

### 既存テストとの併用

QC16 は既存の QC3 (test) / QC7 (Integration Verification) / QC13 (Branch Coverage) と **併用**する:

- QC3 / QC7 は **すべてのテスト**を実行
- QC16 は **regression marker を持つテスト**だけを抽出して別 step として実行（fail 時に「regression が壊れた」と明示）
- QC16 は **必ず blocking**（advisory ではない。修正による新バグの流入を即検出するため）

### 既存 spec の retrofit

既存の bug fix commit で `regression_issue_*` 命名規則が適用されていない場合は warning。次バージョンから新規バグ修正は必須化。

### 注意

- QC14 (UI Smoke Render, E-3) と QC15 (UT Properties Gate, I-2) は **未実装**。本 QC16 は J-9 として先行実装
- QC16 は **CI gate**（PR / merge 時の blocking）。Phase Review 内のローカル実行は QC3 / QC7 で間接的にカバー
