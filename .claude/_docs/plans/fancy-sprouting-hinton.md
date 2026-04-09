# Plan: `setup-ci` スキル — PRトリガーCI ワークフロー生成

## Context

ハーネス成熟度チェックリストで P6(CI/CD) のカバレッジが 23% と最も低い。
根本原因は、プラグインが消費プロジェクトに対して **GitHub Actions CIワークフローを提供する仕組みがない** こと。
現状は agents チェーン内（parallel-worker → review-worker）でのみ品質チェックが実行されるが、
PR 単位の外部 CI が欠如している。

このスキルにより P6-01(PRテスト), P6-02(PRビルド), P6-04(静的解析) を一括改善する。

## 方針

- `/setup-ci` スキルを新設し、消費プロジェクトのタイプに応じた `.github/workflows/ci.yml` を生成する
- `quality-checks.md` のコマンドと完全に一致させ、ローカル品質チェックとCI の parity を保証
- 参照テンプレート (references/) にプロジェクトタイプ別の YAML 雛形を配置

## 新規作成ファイル

### 1. `.claude-plugin/skills/setup-ci/SKILL.md`

スキル本体。以下のステップを定義:

1. **プロジェクトタイプ検出** — `quality-checks.md` と同じ優先順:
   - Cargo.toml に `[package.metadata.leptos]` → **Leptos**
   - Cargo.toml あり → **Rust** (axum/actix-web/rocket で API サブタイプ検出)
   - package.json あり → **Node.js**
2. **プロジェクト固有設定の収集**:
   - Rust: `rust-toolchain.toml` からツールチェーン版、workspace 有無
   - Node.js: `engines.node` バージョン、lockfile 種別 (npm/yarn/pnpm)、eslint/prettier 有無
   - 共通: `.spec-workflow/steering/tech.md` からの追加情報
3. **参照テンプレート選択・カスタマイズ** — 検出結果で placeholder を置換
4. **`.github/workflows/ci.yml` 生成** — 既存ファイルがあれば diff 表示し確認
5. **検証** — 生成 YAML の構文チェック

frontmatter:
```yaml
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
```

### 2. `.claude-plugin/skills/setup-ci/references/ci-rust.yml`

Rust プロジェクト用テンプレート:

```yaml
name: CI

on:
  pull_request:
    branches: [main, master]
  push:
    branches: [main, master]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  CARGO_TERM_COLOR: always

jobs:
  check:
    name: Quality Checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@{{TOOLCHAIN}}
        with:
          components: rustfmt, clippy
      - uses: Swatinem/rust-cache@v2

      - name: Format check
        run: cargo fmt --all -- --check
      - name: Clippy
        run: cargo clippy --quiet --all-targets -- -D warnings
      - name: Tests
        run: cargo test --quiet
      - name: Security audit
        run: cargo install cargo-audit --locked 2>/dev/null || true && cargo audit
```

placeholder: `{{TOOLCHAIN}}` → `stable` or `rust-toolchain.toml` の値

### 3. `.claude-plugin/skills/setup-ci/references/ci-leptos.yml`

Leptos (Rust WASM) 用テンプレート。Rust テンプレートに加え:

```yaml
      # (Rust steps と同じ ... の後に追加)
      - name: Add wasm32 target
        run: rustup target add wasm32-unknown-unknown
      - name: Install cargo-leptos
        run: cargo install cargo-leptos --locked
      - name: Leptos build (SSR + WASM)
        run: cargo leptos build
```

### 4. `.claude-plugin/skills/setup-ci/references/ci-nodejs.yml`

Node.js プロジェクト用テンプレート:

```yaml
name: CI

on:
  pull_request:
    branches: [main, master]
  push:
    branches: [main, master]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  check:
    name: Quality Checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '{{NODE_VERSION}}'
          cache: '{{PACKAGE_MANAGER}}'
      - name: Install dependencies
        run: {{INSTALL_COMMAND}}
      - name: Type check
        run: npx tsc --noEmit
      - name: Lint
        run: npx eslint . --max-warnings=0
      - name: Format check
        run: npx prettier --check .
      - name: Tests
        run: npm test -- --run
      - name: Build
        run: npm run build
```

placeholders:
- `{{NODE_VERSION}}` → `engines.node` or `20`
- `{{PACKAGE_MANAGER}}` → `npm` / `yarn` / `pnpm` (lockfile 検出)
- `{{INSTALL_COMMAND}}` → `npm ci` / `yarn install --frozen-lockfile` / `pnpm install --frozen-lockfile`

### 5. `.claude-plugin/skills/setup-ci/references/job-e2e.yml`

`--with-e2e` 指定時に追加する E2E テストジョブスニペット:

- Rust API: docker-compose + `cargo test --test '*'` (integration tests)
- Node.js: Playwright install + `npx playwright test`

### 6. `.claude-plugin/skills/setup-ci/references/job-services.yml`

`--with-services` 指定時に追加する PostgreSQL/Redis サービスコンテナ定義スニペット。

## 既存ファイルの変更

### 1. `.claude-plugin/skills/spec-tasks/SKILL.md` — Step 2.7 追加

Step 2.6 (Detect Container Requirements) の直後に **Step 2.7: Detect CI Workflow Requirements** を追加。
既存の Step 2.5 (Git 初期化) / Step 2.6 (コンテナ) と同じパターンで、
`.github/workflows/ci.yml` が未作成の場合に Phase 0 へ CI セットアップタスクを自動挿入する。

```markdown
### 2.7 Detect CI Workflow Requirements

`.github/workflows/` 配下に PR トリガーの CI ワークフローが存在するか確認する。

**検出ロジック:**
1. `.github/workflows/` ディレクトリ内の YAML ファイルに `pull_request` トリガーが定義されているか

\```bash
grep -rl 'pull_request' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null
\```

**PR トリガーの CI ワークフローが存在しない場合**、Phase 0 に以下のタスクを追加する
（Git 初期化 → コンテナ → CI の順）:

- [ ] 0.N Create CI workflow
  - File: .github/workflows/ci.yml
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: /setup-ci スキルを使用して、
    プロジェクトタイプに応じた PR トリガーの GitHub Actions CI ワークフローを生成する。
    quality-checks.md に定義された品質チェックコマンドと同一のステップを含めること |
    Restrictions: シークレットをワークフローにハードコードしない。
    既存の CI ワークフロー（npm-publish.yml 等）を変更しない |
    Success: PR 作成時に CI が自動実行され、品質チェック（lint, test, build）が通る_

**PR トリガーの CI ワークフローが既に存在する場合**: タスクを追加しない。
```

### 2. `.claude-plugin/rules/quality-checks.md`

先頭の概要セクションに1行追加:

```
> These commands are also used by the `/setup-ci` skill to generate CI workflow YAML.
> Re-run `/setup-ci` after updating this file to keep CI in sync.
```

## SKILL.md の主要ロジック（擬似コード）

```
1. プロジェクトタイプ検出:
   - grep -q '[package.metadata.leptos]' Cargo.toml → leptos
   - test -f Cargo.toml → rust
   - test -f package.json → nodejs
   - else → error "サポート外"

2. 設定収集:
   - Rust: rust-toolchain.toml → TOOLCHAIN, [workspace] 有無
   - Node.js: package.json engines.node → NODE_VERSION,
              lockfile 種別 → PACKAGE_MANAGER / INSTALL_COMMAND,
              devDependencies に eslint/prettier → 該当ステップの有無

3. references/ からテンプレート読み込み
4. placeholder 置換
5. 該当しないステップの削除 (例: eslint未導入なら Lint ステップ除外)
6. --with-e2e / --with-services があれば追加ジョブ挿入
7. .github/workflows/ci.yml に Write
8. 生成結果をサマリ表示
```

## 検証方法

1. プラグインを導入済みの Rust / Leptos / Node.js プロジェクトで `/setup-ci` を実行
2. 生成された `.github/workflows/ci.yml` が `quality-checks.md` のコマンドと一致することを確認
3. 生成 YAML を GitHub にプッシュし、PR を作成して CI が正常に走ることを確認
4. `--with-e2e` オプション付きで実行し、E2E ジョブが追加されることを確認
5. 既に ci.yml が存在する状態で再実行し、上書き確認フローが動くことを確認
