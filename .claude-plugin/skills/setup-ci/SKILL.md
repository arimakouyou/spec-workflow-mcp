---
name: setup-ci
description: >
  Generate GitHub Actions CI/CD workflows for the project (base 5 files + optional extras, P4-02 compliant).
  Detects project type (Rust/Leptos/Node.js/.NET/Blazor) and creates ci.yml, e2e.yml,
  scheduled-quality.yml, dependabot.yml, release.yml mirroring quality-checks.md.
  Options like --with-sast, --with-auto-merge, --with-auto-fix generate additional workflow files.
  Triggers: 'setup CI', 'add CI workflow', 'create GitHub Actions', 'PR checks',
  'CI/CD を追加', 'CI ワークフロー', 'GitHub Actions を設定'.
argument-hint: "[--with-e2e] [--with-services] [--with-scheduled] [--no-pr-comments] [--with-docs-lint] [--with-sast] [--with-flaky-detection] [--with-auto-merge] [--with-auto-fix]"
user-invokable: true
---

# Setup CI

Generate GitHub Actions CI/CD workflows that mirror the quality check commands defined in `.claude-plugin/rules/quality-checks.md`. Ensures parity between local agent-chain quality checks and external CI.

**P4-02 準拠**: このスキルは基本 5 つの CI/CD 設定ファイルを生成し、harness-maturity-check P4-02 の要件（CI/CD 設定ファイル 5 個以上）を満たす。オプション（`--with-sast` 等）で追加ファイルも生成される。

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

#### .NET / .NET Blazor

| Setting | Detection | Default |
|---------|-----------|---------|
| .NET version | `<TargetFramework>` in .csproj or `global.json` の `sdk.version` | `10.0.x` |
| Solution file | リポジトリルートの `*.sln`（**必須** — 未存在時は `dotnet new sln` + `dotnet sln add` を指示） | — |
| Blazor WASM | .csproj に `Microsoft.AspNetCore.Components.WebAssembly` | false |

#### Common

Read `.spec-workflow/steering/tech.md` if it exists for additional context (language versions, framework choices).

### 3. Select and Customize Templates

Read the reference templates matching the detected project type. **5 ファイルすべて**を生成する:

| # | 出力先 | テンプレート | 目的 |
|---|--------|------------|------|
| 1 | `.github/workflows/ci.yml` | `references/ci-{type}.yml` | PR 品質チェック |
| 2 | `.github/workflows/e2e.yml` | `references/e2e-standalone.yml` | E2E / 統合テスト |
| 3 | `.github/workflows/scheduled-quality.yml` | `references/scheduled-quality-standalone.yml` | 週次品質スキャン |
| 4 | `.github/dependabot.yml` | `references/dependabot.yml` | 依存関係自動更新 |
| 5 | `.github/workflows/release.yml` | `references/release.yml` | リリース / パブリッシュ |

`{type}` は `rust` / `leptos` / `dotnet` / `nodejs` に置換（`dotnet-blazor` は `dotnet` テンプレートを使用し、Blazor 固有ステップを追加）。

Replace placeholders with the values gathered in Step 2:

**Rust / Leptos:**
- `{{TOOLCHAIN}}` → detected toolchain (e.g., `stable`, `nightly`, `1.82`)

**.NET / .NET Blazor:**
- `{{DOTNET_VERSION}}` → detected .NET version (e.g., `10.0.x`)
- 前提: リポジトリルートに `.sln` が1つ存在すること（コマンドは `.sln` パスを指定せず実行）

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

**PR コメントステップ**（全プロジェクトタイプ共通）:
- PR コメント投稿ステップ（"Post CI results to PR"）はデフォルトで全テンプレートに含まれる
- `--no-pr-comments` 指定時は "Post CI results to PR" ステップをテンプレートから除去

### 4. Handle Options

#### `--with-e2e`

`e2e-standalone.yml` テンプレート内の、検出されたプロジェクトタイプに該当するセクションをアンコメントし、プレースホルダを置換する。
- Node.js: setup-node → install → Playwright install → Playwright test → PR コメント
- Rust: rust-toolchain → cargo test --test → PR コメント
- `pull_request` トリガーと `pull-requests: write` 権限もアンコメントする
- このオプションが**指定されない場合**も `e2e.yml` は生成されるが、テスト実行ステップ・`pull_request` トリガー・PR コメント権限はコメントアウトのままとなる（`workflow_dispatch` のみ有効）

#### `--with-services`

`e2e.yml` のサービスコンテナセクションをアンコメントする。
プロジェクトの依存関係（`docker-compose.yml`、`design.md` Container Architecture、`Cargo.toml` の `diesel`/`redis` 等）から必要なサービスを検出して有効化。

#### `--no-pr-comments`

PR コメントフィードバックステップを削除する:
- `ci.yml` から "Post CI results to PR" ステップを削除
- `e2e.yml` から "Post E2E results to PR" ステップを削除
- 各ワークフローの `permissions` ブロックから `pull-requests: write` を削除

デフォルトでは PR コメントフィードバックは**有効**。このオプションで明示的にオプトアウトする。

#### `--with-sast`

セキュリティ特化の静的解析（SAST）を有効化する（P6-04）:
- **Rust / Leptos**: `ci.yml` のセキュリティ特化 clippy lint セクションをアンコメント
  (`-W clippy::suspicious -W clippy::correctness -W clippy::complexity`)
- **.NET / .NET Blazor**: `ci.yml` に `AnalysisLevel=latest-all` セキュリティ Analyzer ステップを追加
  (`CA2xxx` セキュリティ系、`CA3xxx` セキュリティ設計ガイドライン）。CodeQL C# も利用可能
- **Node.js**: `codeql.yml` ワークフローファイルを追加生成（`javascript-typescript`）
  - CodeQL は GitHub の無料 SAST ツールで、公開リポジトリでは無制限に使用可能
  - Rust 向け CodeQL は 2025 年時点でベータ段階のため、clippy security lints を推奨

生成時にプロジェクトタイプが Node.js の場合のみ `codeql.yml` を生成する。

#### `--with-flaky-detection`

flaky test 対策設定を有効化する（P6-08/P6-09）:
- `ci.yml` のテストリトライセクション（`nick-fields/retry@v3`）をアンコメント
- リトライ回数: 3（2回目以降の成功は flaky 候補として警告）
- flaky test 管理ポリシーは `flaky-test-management` Skill を参照

#### `--with-auto-merge`

自動マージワークフローを生成する（P6-10/P6-11）:
- `auto-merge.yml` を `.github/workflows/` に生成
- dependabot PR と `auto-merge` ラベル付き PR を自動マージ
- **前提条件**: GitHub リポジトリ設定で以下を有効化する必要あり:
  - "Require status checks to pass before merging"（必須ステータスチェック）
  - "Allow auto-merge"（自動マージ許可）

**自動マージ条件（P6-11）:**

| PR ソース | 必須チェック | 必須承認 | 自動マージ |
|-----------|------------|---------|----------|
| dependabot | CI 全パス | 不要（bot PR） | Yes |
| human + `auto-merge` ラベル | CI 全パス | 1人以上 | Yes |
| human（ラベルなし） | CI 全パス | 1人以上 | No（手動） |

#### `--with-auto-fix`

品質 Issue 検出時にエージェントが自動修正 PR を生成するワークフローを追加する（P8-07）:
- `auto-fix-quality.yml` を `.github/workflows/` に生成
- `[quality]` + `[automated]` ラベル付き Issue が作成されたときに Claude Code を起動し、`/handle-issue` で自動修正
- **前提条件**:
  - GitHub リポジトリに `ANTHROPIC_API_KEY` シークレットが設定されていること
  - `anthropics/claude-code-action@v1` が利用可能であること

**自動修正フロー（P8-07）:**

1. `scheduled-quality.yml` が品質違反を検出し `[quality]` + `[automated]` ラベル付き Issue を作成
2. `auto-fix-quality.yml` が Issue 作成イベントで起動
3. Claude Code が `/handle-issue {issue-number}` を実行
4. 修正を実装し `/create-pr --closes {issue-number}` で PR を作成
5. CI + review-worker による品質検証
6. `--with-auto-merge` が有効なら `auto-merge` ラベルで自動マージ

**自動修正の対象範囲:**

| 問題種別 | 自動修正 | 理由 |
|---------|---------|------|
| フォーマット違反 | Yes | `cargo fmt` / `prettier --write` で機械的に修正可能 |
| 未使用依存 | Yes | `Cargo.toml` / `package.json` から削除 |
| doc comment 不足 | Yes | `/generate-api-docs` の提案を適用 |
| Stale ドキュメント | Yes | 内容を現状に合わせて更新 |
| セキュリティ脆弱性 | No | Issue コメントで報告のみ（人間の判断が必要） |
| 設計逸脱 | No | Issue コメントで報告のみ（人間の判断が必要） |

#### `--with-docs-lint`

`ci.yml` および `scheduled-quality.yml` のドキュメント Lint セクション（QC10 / P5-03）をアンコメントする:
- markdownlint-cli2 によるフォーマットチェック
- markdown-link-check によるリンク検証（scheduled-quality.yml のみ）
- いずれも `continue-on-error: true`（Advisory）

#### `--with-scheduled`

`scheduled-quality-standalone.yml` テンプレート内の、検出されたプロジェクトタイプに該当する品質チェックセクションをアンコメントする:
- Node.js: npm audit, jscpd コード重複検出
- Rust: cargo audit, cargo udeps, clippy
- このオプションが**指定されない場合**も `scheduled-quality.yml` は生成されるが、lockfile 検証とドキュメント鮮度チェックのみ有効


### 5. Generate Workflow Files

以下の 5 ファイルをすべて生成する（P4-02 準拠のため常に 5 ファイル）:

1. `.github/workflows/` ディレクトリが存在しなければ作成
2. 各ファイルについて順に処理:
   - `.github/workflows/ci.yml` — `ci-{type}.yml` テンプレートから生成
   - `.github/workflows/e2e.yml` — `e2e-standalone.yml` テンプレートから生成
   - `.github/workflows/scheduled-quality.yml` — `scheduled-quality-standalone.yml` テンプレートから生成
   - `.github/dependabot.yml` — `dependabot.yml` テンプレートから生成
   - `.github/workflows/release.yml` — `release.yml` テンプレートから生成
3. 各ファイルが既に存在する場合:
   - 既存ファイルとの差分を表示
   - ユーザーに上書き確認を求める
   - 確認なしの上書きは行わない
4. `dependabot.yml` は検出されたプロジェクトタイプに応じたエコシステムをアンコメント:
   - Node.js → `npm` セクション
   - Rust / Leptos → `cargo` セクション
   - `github-actions` セクションは常に有効

### 6. Verify and Report

After writing all files, report:

```
CI/CD workflows generated (P4-02 compliant):
  1. .github/workflows/ci.yml          — PR 品質チェック
  2. .github/workflows/e2e.yml         — E2E テスト
  3. .github/workflows/scheduled-quality.yml — 週次品質スキャン
  4. .github/dependabot.yml            — 依存関係自動更新
  5. .github/workflows/release.yml     — リリース

Total CI/CD config files: 5 (P4-02 requires ≥ 5)

Project type: {detected type}
Quality checks (ci.yml):
  - {list of enabled check steps}

Options applied:
  - E2E tests: {active/commented-out (--with-e2e)}
  - Service containers: {yes/no (--with-services)}
  - Scheduled quality checks: {active/minimal (--with-scheduled)}
  - PR コメントフィードバック: {有効/無効 (--no-pr-comments)}
  - ドキュメント Lint: {有効/無効 (--with-docs-lint)}
  - SAST: {有効/無効 (--with-sast)}
  - Flaky test リトライ: {有効/無効 (--with-flaky-detection)}
  - Auto-merge: {有効/無効 (--with-auto-merge)}
  - Auto-fix: {有効/無効 (--with-auto-fix)}

Next steps:
  - Commit and push to verify the workflows run correctly
  - Configure repository secrets if publishing or integration tests require them
  - E2E テストが未設定なら /setup-ci --with-e2e で有効化
```

## Source of Truth

The CI workflow commands MUST match `.claude-plugin/rules/quality-checks.md` exactly.
CI-specific setup steps (tool installation etc.) are permitted as prerequisites, but the quality check commands themselves must be identical.
If `quality-checks.md` is updated, re-running `/setup-ci` regenerates the workflow with updated commands.

## Notes

- The generated YAML includes a header comment noting it was generated by `/setup-ci`
- This skill is also invoked automatically when `/spec-tasks` detects a new project without CI (Step 2.7)
- GitHub Actions only (V1). GitLab CI / other providers may be added in future versions
