---
name: create-pr
description: "テスト結果とUIスクリーンショットを含むPRを作成する。IT/E2Eテスト実行→UI変更検出→スクリーンショット取得→PRボディ構築→gh pr create。単独でも他スキルからの参照でも使用可能。Triggers on: 'create PR', 'PRを作成', 'PR作成', '/create-pr'."
user-invokable: true
argument-hint: "[--title <title>] [--closes <issue-number>] [--spec <spec-name>] [--skip-tests] [--base <branch>]"
---

# PR 作成 — テスト結果・スクリーンショット付き

テスト結果と UI スクリーンショットを含む PR を作成する。単独でも、`/handle-issue` や `/spec-implement` からの参照でも使用可能。

## 入力

`$ARGS` から以下の引数を解析する。全て省略可能。

| 引数 | 必須 | 説明 |
|------|:----:|------|
| `--title <title>` | NO | PR タイトル。省略時はブランチ名から自動生成（kebab-case → スペース区切り、先頭大文字化） |
| `--closes <issue-number>` | NO | 関連 Issue 番号。指定時は PR ボディ末尾に `Closes #{number}` を追加 |
| `--spec <spec-name>` | NO | Spec 名。指定時は Spec ドキュメントリンクを PR ボディに追加し、`final-e2e-gate.md` から結果を読み取る |
| `--skip-tests` | NO | テスト実行をスキップ。品質チェック/Final E2E Gate 実行済みの場合に使用 |
| `--base <branch>` | NO | ベースブランチ。省略時は自動検出 |

**呼び出し例**:
- `/create-pr --title "Fix null pointer in parser" --closes 42`
- `/create-pr --spec user-export --skip-tests`
- `/create-pr`（引数なし — 全自動）

## 前提条件チェック（MANDATORY）

以下のチェックを順番に実行する。いずれかが失敗した場合は **STOP** し、対処方法を案内する。

### 1. gh CLI 認証確認

```bash
gh auth status
```

失敗時: 「`gh auth login` を実行して GitHub CLI を認証してください」と案内して STOP。

### 2. リポジトリ確認

```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
```

失敗時: 「GitHub リポジトリのルートディレクトリで実行してください」と案内して STOP。

### 3. ワーキングツリー確認

```bash
git status --porcelain
```

未コミットの変更がある場合: 警告を表示し、コミットするか stash するか確認する。未コミットの変更を残したまま PR 作成に進まない。

### 4. ベースブランチの特定

```bash
# --base 未指定時の自動検出
BASE_BRANCH=${BASE_ARG:-$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')}
# フォールバック
BASE_BRANCH=${BASE_BRANCH:-main}
```

### 5. 差分の確認

```bash
BRANCH=$(git branch --show-current)
COMMIT_COUNT=$(git rev-list --count ${BASE_BRANCH}..HEAD)
```

差分が 0 コミットの場合: 「ベースブランチとの差分がありません」と案内して STOP。

## 手順

### 1. テスト結果の収集

`--skip-tests` が指定されている場合はこのステップをスキップし、Step 1.4 の既存レポート読み取りのみ実行する。

#### 1.1 プロジェクトタイプ検出

`quality-checks.md` のプロジェクトタイプ検出ロジックに従う:

```bash
if grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null; then
  PROJECT_TYPE="leptos"
elif grep -qE '(axum|actix-web|rocket)' Cargo.toml 2>/dev/null; then
  PROJECT_TYPE="rust-api"
elif test -f Cargo.toml; then
  PROJECT_TYPE="rust"
elif test -f package.json; then
  PROJECT_TYPE="nodejs"
else
  PROJECT_TYPE="generic"
fi
```

#### 1.2 ユニットテスト実行・結果キャプチャ

```bash
# Rust
if [[ "$PROJECT_TYPE" =~ ^(rust|rust-api|leptos)$ ]]; then
  UT_OUTPUT=$(cargo test --quiet 2>&1) ; UT_EXIT=$?

# Node.js
elif [ "$PROJECT_TYPE" = "nodejs" ]; then
  UT_OUTPUT=$(npm test -- --run 2>&1) ; UT_EXIT=$?
fi

if [ "${UT_EXIT:-1}" -eq 0 ]; then UT_RESULT="PASS"; else UT_RESULT="FAIL"; fi
```

テストランナーが存在しない場合: `UT_RESULT="SKIP"`, `UT_OUTPUT="ユニットテストなし"`

#### 1.3 統合テスト実行・結果キャプチャ

`quality-checks.md` の「Step C: 統合テスト実行」の検出ロジックに従う:

```bash
# Rust: 統合テストの存在確認
IT_EXISTS=$(find tests -type f -name '*.rs' ! -regex '.*/tests/\(e2e\|unit\)/.*' -print -quit 2>/dev/null)

# Node.js: 統合テストスクリプトまたはファイルの存在確認
IT_SCRIPT=$(grep -q '"test:integration"' package.json 2>/dev/null && echo "yes")
```

統合テストが存在する場合:

```bash
# Rust
IT_OUTPUT=$(cargo test --tests --quiet 2>&1) ; IT_EXIT=$?

# Node.js（スクリプトあり）
IT_OUTPUT=$(npm run test:integration 2>&1) ; IT_EXIT=$?

# Node.js（ファイルパターン）
IT_OUTPUT=$(npm test -- --testPathPattern=integration 2>&1) ; IT_EXIT=$?

if [ "${IT_EXIT:-1}" -eq 0 ]; then IT_RESULT="PASS"; else IT_RESULT="FAIL"; fi
```

統合テストが存在しない場合: `IT_RESULT="SKIP"`, `IT_OUTPUT="統合テストなし"`

#### 1.4 E2E テスト実行・結果キャプチャ

```bash
# Playwright
if test -f playwright.config.ts || test -f playwright.config.js; then
  E2E_OUTPUT=$(npx playwright test 2>&1) ; E2E_EXIT=$?

# Rust E2E
elif test -d tests/e2e; then
  E2E_OUTPUT=$(cargo test --tests --quiet 2>&1) ; E2E_EXIT=$?

# Node.js E2E スクリプト
elif grep -q '"test:e2e"' package.json 2>/dev/null; then
  E2E_OUTPUT=$(npm run test:e2e 2>&1) ; E2E_EXIT=$?

else
  E2E_RESULT="SKIP"
  E2E_OUTPUT="E2Eテストなし"
fi

if [ -n "$E2E_EXIT" ]; then
  if [ "$E2E_EXIT" -eq 0 ]; then E2E_RESULT="PASS"; else E2E_RESULT="FAIL"; fi
fi
```

#### 1.5 Spec 指定時の既存レポート読み取り

`--spec` が指定されている場合、`final-e2e-gate.md` が存在すれば結果を読み取る:

```bash
GATE_REPORT=".spec-workflow/specs/{spec-name}/reviews/final-e2e-gate.md"
if test -f "$GATE_REPORT"; then
  # レポートの Results テーブルと Verdict を抽出
  # テスト再実行の代わりにレポートの内容を PR ボディに転記
fi
```

`--skip-tests` が指定されている場合はこの読み取り結果のみを使用する。レポートも存在しない場合は、テスト結果セクションに「テスト結果: 手動確認が必要」と記載する。

#### 1.6 テスト失敗時の振る舞い

いずれかのテスト結果が `FAIL` の場合:

1. 失敗したテストの結果をユーザーに提示する
2. 以下の選択肢を提示する:
   - A) テスト失敗のまま PR を作成する（PR ボディに FAIL が記載される）
   - B) PR 作成を中止し、テスト修正を行う
3. ユーザーが B を選択した場合は PR 作成をスキップして STOP

### 2. UI 変更検出

変更されたファイルから UI 関連の変更を検出する。

```bash
# フロントエンド関連ファイルの変更検出
UI_FILES=$(git diff --name-only ${BASE_BRANCH}...HEAD -- \
  '*.tsx' '*.jsx' '*.vue' '*.svelte' \
  '*.css' '*.scss' '*.less' '*.pcss' '*.html')

# UI 関連ディレクトリ内の変更検出
UI_DIR_FILES=$(git diff --name-only ${BASE_BRANCH}...HEAD | \
  grep -E '(components|pages|dashboard_frontend|webview|frontend|ui)/')

# Leptos: view! マクロを含む Rust ファイルの変更検出
if [ "$PROJECT_TYPE" = "leptos" ]; then
  LEPTOS_UI=$(git diff --name-only ${BASE_BRANCH}...HEAD -- '*.rs' | \
    xargs grep -l 'view!' 2>/dev/null)
fi
```

**判定**: `UI_FILES`、`UI_DIR_FILES`、`LEPTOS_UI` のいずれかが非空 → `HAS_UI_CHANGES=true`

`HAS_UI_CHANGES=false` の場合は Step 3 をスキップ。

### 3. スクリーンショット取得

`HAS_UI_CHANGES=true` の場合のみ実行する。

#### 3.1 スクリーンショット収集方針

以下の優先順位で取得を試みる:

**優先度 1: E2E テスト実行済みの場合**
- Playwright が生成したスクリーンショットを収集する
- `test-results/` ディレクトリ内の `.png` ファイル
- `docs/screenshots/` ディレクトリ内の新規・更新ファイル（`git diff --name-only` で検出）

**優先度 2: dev サーバーが起動可能な場合**
- E2E テスト未実行だが UI 変更がある場合に使用

```bash
# dev サーバーの起動コマンドを検出
if grep -q '"dev:dashboard"' package.json 2>/dev/null; then
  DEV_CMD="npm run dev:dashboard"
elif grep -q '"dev"' package.json 2>/dev/null; then
  DEV_CMD="npm run dev"
elif [ "$PROJECT_TYPE" = "leptos" ]; then
  DEV_CMD="cargo leptos watch"
fi
```

dev サーバー起動 → Playwright で変更された UI 画面を巡回しスクリーンショット取得 → dev サーバー停止

```bash
# Playwright を使った手動スクリーンショット取得
npx playwright screenshot --browser chromium "http://localhost:${PORT:-5173}" \
  "docs/screenshots/pr-evidence/${BRANCH}/page.png"
```

**優先度 3: いずれも不可の場合**
- スクリーンショット取得をスキップ
- PR ボディに「UI 変更を検出しましたが、スクリーンショットの自動取得ができませんでした。手動で確認してください。」と注記

#### 3.2 スクリーンショットの保存とコミット

```bash
# 保存先ディレクトリ
SCREENSHOT_DIR="docs/screenshots/pr-evidence/${BRANCH}"
mkdir -p "$SCREENSHOT_DIR"

# 収集したスクリーンショットをコピー（優先度 1 or 2 の結果）
cp {collected-screenshots} "$SCREENSHOT_DIR/"

# コミットとプッシュ
git add docs/screenshots/pr-evidence/
git commit -m "docs: PR用スクリーンショットを追加"
git push
```

### 4. PR ボディ構築

以下のテンプレートに従って PR ボディを構築する。セクションはコンテキストに応じて動的に組み立てる。

#### 4.1 概要セクション

| 条件 | 概要テキスト |
|------|-------------|
| `--closes` 指定あり | `Issue #{number} の修正。` |
| `--spec` 指定あり | `Spec: {spec-name} の実装。` |
| いずれも未指定 | ブランチの変更概要を `git log --oneline ${BASE_BRANCH}..HEAD` から生成 |

#### 4.2 変更内容セクション

```bash
git log --oneline ${BASE_BRANCH}..HEAD
```

各コミットメッセージを箇条書きで列挙する。

#### 4.3 テスト結果セクション

各テストカテゴリの結果を以下のフォーマットで構築する:

**PASS/FAIL の場合**（出力を折りたたみで表示）:

```markdown
### ユニットテスト
{UT_RESULT}: {pass数} passed, {fail数} failed

### 統合テスト (IT)
<details>
<summary>{IT_RESULT}: {概要行}</summary>

```
{IT_OUTPUT の末尾50行}
```
</details>

### E2E テスト
<details>
<summary>{E2E_RESULT}: {概要行}</summary>

```
{E2E_OUTPUT の末尾50行}
```
</details>
```

**SKIP の場合**（簡略表示）:

```markdown
### 統合テスト (IT)
SKIP — 統合テストなし
```

**Spec 指定 + final-e2e-gate.md 存在時**（レポート転記）:

```markdown
### Final E2E Gate
| Step | Result | Details |
|------|--------|---------|
{final-e2e-gate.md の Results テーブルをそのまま転記}

**Verdict**: {PASS / PASS(SKIP含む)}
```

#### 4.4 UI スクリーンショットセクション（`HAS_UI_CHANGES=true` の場合のみ）

```markdown
## UI スクリーンショット
| 画面 | スクリーンショット |
|------|------------------|
| {画面名} | ![{画面名}](https://raw.githubusercontent.com/{REPO}/{BRANCH}/docs/screenshots/pr-evidence/{BRANCH}/{filename}.png) |
```

スクリーンショット取得がスキップされた場合:

```markdown
## UI 変更
UI 変更を検出しましたが、スクリーンショットの自動取得ができませんでした。
変更ファイル:
- {UI_FILES の一覧}
```

#### 4.5 Spec ドキュメントセクション（`--spec` 指定時のみ）

```markdown
## Spec ドキュメント
- [Requirements](.spec-workflow/specs/{spec-name}/requirements.md)
- [Design](.spec-workflow/specs/{spec-name}/design.md)
- [Test Design](.spec-workflow/specs/{spec-name}/test-design.md)
- [Tasks](.spec-workflow/specs/{spec-name}/tasks.md)
```

#### 4.6 フッター

```markdown
{--closes 指定時}
Closes #{number}
```

### 5. PR 作成

構築した PR ボディで `gh pr create` を実行する:

```bash
gh pr create \
  --title "{title}" \
  --body "{4.1〜4.6 で構築したボディ}" \
  --base "${BASE_BRANCH}" \
  --assignee @me
```

PR 作成後、**PR の URL をユーザーに報告する**。

### 6. 完了レポート

```
## PR 作成完了

- **PR**: {PR URL}
- **タイトル**: {title}
- **ベース**: {BASE_BRANCH} ← {BRANCH}
- **テスト結果**: UT={UT_RESULT}, IT={IT_RESULT}, E2E={E2E_RESULT}
- **UI スクリーンショット**: {あり（N枚）/ なし / スキップ}
{--closes 指定時}
- **関連 Issue**: #{number}
{--spec 指定時}
- **Spec**: {spec-name}
```

## ルール

- 未コミットの変更がある状態で PR を作成しない
- テスト失敗時は必ずユーザーに確認を取る（自動で FAIL のまま PR を作成しない）
- スクリーンショットは `docs/screenshots/pr-evidence/` に保存する（既存の `docs/screenshots/` は変更しない）
- 出力が長い場合は末尾 50 行に切り詰め、`<details>` タグで折りたたむ
- `--skip-tests` 指定時でもテスト結果セクションは省略しない（既存レポートから転記、またはレポートがない場合は「手動確認が必要」と記載）
- PR ボディ内のスクリーンショット URL にはブランチ名を使用する（PR マージ前に参照可能にするため）
- プロジェクトタイプの検出は `quality-checks.md` のロジックに準拠する
