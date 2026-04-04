---
name: create-pr
description: "テスト結果とUIスクリーンショットを含むPRを作成する。IT/E2Eテスト実行→UI変更検出→スクリーンショット取得→PRボディ構築→gh pr create。単独でも他スキルからの参照でも使用可能。Triggers on: 'create PR', 'PRを作成', 'PR作成', '/create-pr'."
user-invokable: true
argument-hint: "[--title <title>] [--closes <issue-number>] [--spec <spec-name>] [--skip-tests] [--base <branch>]"
---

# PR 作成 — テスト結果・スクリーンショット付き

テスト結果と UI スクリーンショットを含む PR を作成する。単独でも、`/handle-issue` や `/spec-implement` からの参照でも使用可能。

## 実行コンテキスト

このスキルは以下の2つのコンテキストで使用される。コミット/プッシュの責務が異なる点に注意:

| コンテキスト | コミット/プッシュの責務 |
|-------------|----------------------|
| **スタンドアロン実行** (`/create-pr` を直接実行) | このスキル自身がコミット/プッシュを実行する |
| **spec-implement からの呼び出し** (Step 10 経由) | review-worker がこのスキルを実行する。コミット/プッシュは review-worker の責務 |

`/handle-issue` の 4B パスから呼び出される場合はスタンドアロン実行と同じ扱い。

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

## 引数パース

`$ARGS` 文字列から以下の変数を抽出する。Claude が `$ARGS` を意味的に解析し、各変数に値を設定する。

| 変数 | 対応引数 | デフォルト |
|------|---------|-----------|
| `TITLE_ARG` | `--title <value>` | `""` （省略時はブランチ名から自動生成） |
| `CLOSES_ARG` | `--closes <number>` | `""` |
| `SPEC_ARG` | `--spec <name>` | `""` |
| `BASE_ARG` | `--base <branch>` | `""` |
| `SKIP_TESTS` | `--skip-tests` | `false` |

**パース規則**: `--title` など値にスペースを含む引数は、引用符で囲まれた部分を1つの値として扱う（例: `--title "Fix null pointer in parser"` → `TITLE_ARG="Fix null pointer in parser"`）。Claude はシェルの `set --` による分割ではなく、`$ARGS` 文字列を直接読み取って意味的に解析すること。

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
# リモート追跡ブランチを最新化して差分を正確に算出する
git fetch origin "${BASE_BRANCH}" --quiet 2>/dev/null
COMMIT_COUNT=$(git rev-list --count "origin/${BASE_BRANCH}..HEAD")
```

差分が 0 コミットの場合: 「ベースブランチとの差分がありません」と案内して STOP。

以降のベースブランチとの比較コマンド（`git diff`, `git rev-list`, `git log` 等）でも `origin/${BASE_BRANCH}` を使用する。

### 6. ブランチ名のサニタイズ

ブランチ名に `/` が含まれるとディレクトリパスがネストして壊れるため、ファイルシステム用の slug を生成する:

```bash
BRANCH_SLUG=$(echo "$BRANCH" | tr '/' '-')
```

**使い分け:**
- **ファイルシステムパス**（スクリーンショット保存先等）: `${BRANCH_SLUG}` を使用
- **GitHub URL の ref 部分**（`blob/{ref}/...`）: `${BRANCH}` を使用（`blob/` 形式では `/` を含む ref を正しく解釈する）
- **git 操作・`gh pr create`**: `${BRANCH}` を使用

## 手順

### 1. テスト結果の収集

`--skip-tests` が指定されている場合はこのステップをスキップし、Step 1.5 の既存レポート読み取りのみ実行する。

#### 1.1 プロジェクトタイプ検出

`quality-checks.md` のプロジェクトタイプ検出ロジックに準拠する:

```bash
# 1. Leptos フルスタック検出
if grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null; then
  PROJECT_TYPE="leptos"
# 2. Rust API 検出（axum, actix-web, rocket 等）
elif grep -qE '(axum|actix-web|rocket)' Cargo.toml 2>/dev/null; then
  PROJECT_TYPE="rust-api"
# 3. Node.js 検出
elif test -f package.json; then
  PROJECT_TYPE="nodejs"
# 4. いずれにも該当しない
else
  PROJECT_TYPE="generic"
fi
```

#### 1.2 ユニットテスト実行・結果キャプチャ

```bash
# 変数を明示初期化（環境値の誤拾い防止）
unset UT_EXIT; UT_RESULT=""; UT_OUTPUT=""

# Rust（rust-api, leptos を含む）— IT と重複しないよう lib テスト優先
# bin-only クレート（src/lib.rs なし）では cargo test --lib が失敗するためフォールバック
if [[ "$PROJECT_TYPE" =~ ^(rust-api|leptos)$ ]]; then
  if [ -f src/lib.rs ] || grep -qE '^\s*\[lib\]' Cargo.toml 2>/dev/null; then
    UT_OUTPUT=$(cargo test --lib --quiet 2>&1) ; UT_EXIT=$?
  else
    UT_OUTPUT=$(cargo test --quiet 2>&1) ; UT_EXIT=$?
  fi

# Node.js
elif [ "$PROJECT_TYPE" = "nodejs" ]; then
  UT_OUTPUT=$(npm test 2>&1) ; UT_EXIT=$?

# テストランナー未検出（generic 等）
else
  UT_RESULT="SKIP"
  UT_OUTPUT="ユニットテストなし"
fi

# ランナー実行時の結果判定
if [ -n "$UT_EXIT" ]; then
  if [ "$UT_EXIT" -eq 0 ]; then UT_RESULT="PASS"; else UT_RESULT="FAIL"; fi
fi
```

#### 1.3 統合テスト実行・結果キャプチャ

`quality-checks.md` の「Step C: 統合テスト実行」の検出ロジックに従う:

```bash
# Rust: 統合テストの存在確認（tests/ 配下の .rs。e2e/ と unit/ は -path で除外）
IT_EXISTS=$(find tests -path 'tests/e2e' -prune -o -path 'tests/unit' -prune -o -type f -name '*.rs' -print -quit 2>/dev/null)

# Node.js: 統合テストスクリプトまたはファイルの存在確認
IT_SCRIPT=$(grep -q '"test:integration"' package.json 2>/dev/null && echo "yes")
IT_FILES=$(find tests test __tests__ -type f -name 'integration*' -print -quit 2>/dev/null)
```

`IT_EXISTS`、`IT_SCRIPT`、`IT_FILES` のいずれかが非空の場合のみテストを実行する:

```bash
# 変数を明示初期化
unset IT_EXIT; IT_RESULT=""; IT_OUTPUT=""

if [ -n "$IT_EXISTS" ]; then
  # Rust
  IT_OUTPUT=$(cargo test --tests --quiet 2>&1) ; IT_EXIT=$?

elif [ "$IT_SCRIPT" = "yes" ]; then
  # Node.js（スクリプトあり）
  IT_OUTPUT=$(npm run test:integration 2>&1) ; IT_EXIT=$?

elif [ -n "$IT_FILES" ]; then
  # Node.js（ファイルパターンのみ — スクリプトなし）
  IT_OUTPUT=$(npm test -- --testPathPattern=integration 2>&1) ; IT_EXIT=$?

else
  # 統合テストが存在しない
  IT_RESULT="SKIP"
  IT_OUTPUT="統合テストなし"
fi

# ランナー実行時の結果判定
if [ -n "$IT_EXIT" ]; then
  if [ "$IT_EXIT" -eq 0 ]; then IT_RESULT="PASS"; else IT_RESULT="FAIL"; fi
fi
```

#### 1.4 E2E テスト実行・結果キャプチャ

```bash
# 変数を明示初期化
unset E2E_EXIT; E2E_RESULT=""; E2E_OUTPUT=""

# Playwright
if test -f playwright.config.ts || test -f playwright.config.js; then
  E2E_OUTPUT=$(npx playwright test 2>&1) ; E2E_EXIT=$?

# Rust E2E（tests/e2e/ 配下のみ対象 — IT と範囲が重複しないよう --test で個別指定）
elif test -d tests/e2e; then
  E2E_RS_COUNT=$(find tests/e2e -maxdepth 1 -name '*.rs' -type f 2>/dev/null | wc -l)
  if [ "$E2E_RS_COUNT" -eq 0 ]; then
    # ディレクトリは存在するが .rs ファイルがない場合は SKIP
    E2E_RESULT="SKIP"
    E2E_OUTPUT="tests/e2e/ にテストファイルなし"
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

`--spec` が指定されている場合（`SPEC_ARG` が非空）、引数パースで得た spec 名を使ってレポートパスを構築し、`final-e2e-gate.md` が存在すれば結果を読み取る:

```bash
if [ -n "$SPEC_ARG" ]; then
  GATE_REPORT=".spec-workflow/specs/${SPEC_ARG}/reviews/final-e2e-gate.md"
  if test -f "$GATE_REPORT"; then
    # レポートの Results テーブル、Verdict、Notes を抽出
    # テスト再実行の代わりにレポートの内容を PR ボディに転記
  fi
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
UI_FILES=$(git diff --name-only "origin/${BASE_BRANCH}...HEAD" -- \
  '*.tsx' '*.jsx' '*.vue' '*.svelte' \
  '*.css' '*.scss' '*.less' '*.pcss' '*.html')

# UI 関連ディレクトリ内の変更検出
UI_DIR_FILES=$(git diff --name-only "origin/${BASE_BRANCH}...HEAD" | \
  grep -E '(components|pages|dashboard_frontend|webview|frontend|ui)/')

# Leptos: view! マクロを含む Rust ファイルの変更検出
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
# Playwright を使った手動スクリーンショット取得（パスには BRANCH_SLUG を使用）
npx playwright screenshot --browser chromium "http://localhost:${PORT:-5173}" \
  "docs/screenshots/pr-evidence/${BRANCH_SLUG}/page.png"
```

**優先度 3: いずれも不可の場合**
- スクリーンショット取得をスキップ
- PR ボディに「UI 変更を検出しましたが、スクリーンショットの自動取得ができませんでした。手動で確認してください。」と注記

#### 3.2 スクリーンショットの保存とコミット

```bash
# 保存先ディレクトリ（パスには BRANCH_SLUG を使用）
SCREENSHOT_DIR="docs/screenshots/pr-evidence/${BRANCH_SLUG}"
mkdir -p "$SCREENSHOT_DIR"

# 収集したスクリーンショットのパスを配列で保持する
# （優先度 1 or 2 の手順で取得できた実ファイルパスを格納する）
COLLECTED_SCREENSHOTS=(
  # 例: "test-results/screenshot-1.png"
  # 例: "docs/screenshots/pr-evidence/.../page.png"
)

# スクリーンショットが1枚以上収集できた場合のみコピー・コミット
if [ "${#COLLECTED_SCREENSHOTS[@]}" -gt 0 ]; then
  cp "${COLLECTED_SCREENSHOTS[@]}" "$SCREENSHOT_DIR/"

  # コミットとプッシュ
  git add docs/screenshots/pr-evidence/
  git commit -m "docs: PR用スクリーンショットを追加"
  git push
fi
```

スクリーンショットが 0 枚の場合はコピー・コミット・プッシュを行わず、PR ボディに「UI 変更を検出しましたが、スクリーンショットの自動取得ができませんでした。手動で確認してください。」と注記する（優先度 3 と同じ扱い）。

### 4. PR ボディ構築

以下のテンプレートに従って PR ボディを構築する。セクションはコンテキストに応じて動的に組み立てる。

#### 4.1 概要セクション

| 条件 | 概要テキスト |
|------|-------------|
| `--closes` 指定あり | `Issue #${CLOSES_ARG} の修正。` |
| `--spec` 指定あり | `Spec: ${SPEC_ARG} の実装。` |
| いずれも未指定 | ブランチの変更概要を `git log --oneline origin/${BASE_BRANCH}..HEAD` から生成 |

#### 4.2 変更内容セクション

```bash
git log --oneline origin/${BASE_BRANCH}..HEAD
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

### Notes
{final-e2e-gate.md の Notes セクションをそのまま転記。SKIP 理由、設計時除外の根拠等を含む}
```

Notes セクションが空または存在しない場合は Notes セクション自体を省略する。

#### 4.4 UI スクリーンショットセクション（`HAS_UI_CHANGES=true` の場合のみ）

```markdown
## UI スクリーンショット
| 画面 | スクリーンショット |
|------|------------------|
| {画面名} | ![{画面名}](https://github.com/{REPO}/blob/{BRANCH}/docs/screenshots/pr-evidence/{BRANCH_SLUG}/{filename}.png?raw=1) |
```

スクリーンショット取得がスキップされた場合:

```markdown
## UI 変更
UI 変更を検出しましたが、スクリーンショットの自動取得ができませんでした。
変更ファイル:
- {UI_FILES の一覧}
```

#### 4.5 Spec ドキュメントセクション（`--spec` 指定時のみ）

引数パースで得た `SPEC_ARG` を使ってリンク先を確定させる:

```markdown
## Spec ドキュメント
- [Requirements](.spec-workflow/specs/${SPEC_ARG}/requirements.md)
- [Design](.spec-workflow/specs/${SPEC_ARG}/design.md)
- [Test Design](.spec-workflow/specs/${SPEC_ARG}/test-design.md)
- [Tasks](.spec-workflow/specs/${SPEC_ARG}/tasks.md)
```

#### 4.6 フッター

```markdown
{CLOSES_ARG が非空の場合}
Closes #${CLOSES_ARG}
```

### 5. PR 作成

構築した PR ボディを一時ファイルに書き出し、`--body-file` で渡す（改行や引用符を含むボディでもクォート崩れを防止）:

```bash
PR_BODY_FILE="$(mktemp)"
cat > "${PR_BODY_FILE}" <<'PRBODY'
{4.1〜4.6 で構築したボディ}
PRBODY

gh pr create \
  --title "{title}" \
  --body-file "${PR_BODY_FILE}" \
  --base "${BASE_BRANCH}" \
  --assignee @me

rm -f "${PR_BODY_FILE}"
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
- **関連 Issue**: #${CLOSES_ARG}
{--spec 指定時}
- **Spec**: ${SPEC_ARG}
```

## ルール

- 未コミットの変更がある状態で PR を作成しない
- テスト失敗時は必ずユーザーに確認を取る（自動で FAIL のまま PR を作成しない）
- スクリーンショットは `docs/screenshots/pr-evidence/` に保存する（既存の `docs/screenshots/` は変更しない）
- 出力が長い場合は末尾 50 行に切り詰め、`<details>` タグで折りたたむ
- `--skip-tests` 指定時でもテスト結果セクションは省略しない（既存レポートから転記、またはレポートがない場合は「手動確認が必要」と記載）
- PR ボディ内のスクリーンショット URL には `blob/{BRANCH}/...?raw=1` 形式を使用する（`/` を含むブランチ名でも ref が正しく解釈される）
- ファイルパスにブランチ名を使う場合は `BRANCH_SLUG`（`/` → `-` 置換済み）を使用する
- プロジェクトタイプの検出は `quality-checks.md` のロジックに準拠する
