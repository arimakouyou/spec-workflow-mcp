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

> **Build Cache**: When running these commands, apply the Rust build cache configuration as described in `.claude-plugin/rules/rust-build-cache.md` (e.g., by using a single Bash snippet that both configures the cache and runs the `cargo` commands, or by using a per-command `RUSTC_WRAPPER=sccache cargo ...` prefix).

---

## タスクレベルチェック（QC1〜QC6, QC8〜QC9）

コミット前・PR 単位で実行するチェック。`/setup-ci` が生成する `ci.yml` および `scheduled-quality.yml` に組み込まれる。

## QC1: rustfmt

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

When the project is .NET-based (detected by `*.sln` or `*.csproj` existence without Rust indicators), use the following task-level quality checks. Target: **.NET 10**.

> **Build Cache**: .NET uses MSBuild incremental builds and NuGet package cache automatically. See `.claude-plugin/rules/dotnet-build-cache.md` for details. Use `--no-restore` / `--no-build` flags to skip redundant steps in the chain.

> **Analyzers**: Projects should include .NET Analyzers (CAxxxx), Roslynator, and StyleCop.Analyzers via `Directory.Build.props`. Analyzer warnings are caught by `dotnet build -warnaserror`. See `.claude-plugin/rules/csproj.md`.

### format

```bash
dotnet format --verify-no-changes
```

- Uses `.editorconfig` rules (must be present at solution root)
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
dotnet list package --vulnerable --include-transitive
```

- **Blocking**: If high/critical vulnerabilities are found, the check **fails**
- `--include-transitive`: Checks both direct and transitive dependencies
- This is the C# equivalent of `cargo audit`

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
  if grep -rq 'RestorePackagesWithLockFile' Directory.Build.props 2>/dev/null; then
    if [ ! -f packages.lock.json ] && ! find . -maxdepth 3 -name 'packages.lock.json' -print -quit 2>/dev/null | grep -q .; then
      echo "FAIL: RestorePackagesWithLockFile enabled but packages.lock.json not found"
      FAIL=true
    fi
  fi
fi

# .gitignore で除外されていないことを確認
for lockfile in package-lock.json yarn.lock pnpm-lock.yaml Cargo.lock go.sum poetry.lock Gemfile.lock; do
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
find . -maxdepth 3 -name '*Integration*Tests*.csproj' -o -name '*IntegrationTests*.csproj' -print -quit 2>/dev/null

# Node.js: 統合テストスクリプトまたはファイルの存在確認
grep -q '"test:integration"' package.json 2>/dev/null || \
  find tests test __tests__ -type f -name 'integration*' -print -quit 2>/dev/null
```

| タイプ | コマンド |
|--------|---------|
| Rust | `cargo test --tests --quiet` |
| .NET | `dotnet test --filter "Category=Integration" --no-build --verbosity quiet` |
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
elif ls *.sln 2>/dev/null | head -1 | grep -q . || find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  START_CMD="dotnet run"
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
  echo "Step D: 対応するプロジェクトタイプ（Rust/Node.js）が見つからないため、スモークテストをスキップします。" >&2
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
