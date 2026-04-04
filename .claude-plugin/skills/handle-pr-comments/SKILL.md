---
name: handle-pr-comments
description: "PRレビューコメントを取得し、カテゴリ分類して対応する。コード修正が必要なコメントは修正を実施し、質問には回答、承認は記録。修正後は品質チェックを実行しプッシュ。Triggers on: 'handle PR comments', 'address review comments', 'fix PR feedback', 'PR #N comments', 'レビュー対応', 'PRコメント対応', '/handle-pr-comments'."
user-invokable: true
argument-hint: "<pr-number>"
---

# PR コメント対応 — レビューコメントワークフロー

PR のレビューコメントを取得・分類し、体系的に対応する。

## 入力

- **pr**: PR 番号（例: `#123`, `123`）または PR URL。`$ARGS` の最初の引数として受け取る。

**呼び出し形式**: `/handle-pr-comments <pr-number>` （例: `/handle-pr-comments 123` または `/handle-pr-comments #123`）

引数が未指定の場合はユーザーに PR 番号を確認する。

**入力の正規化**: 引数が URL 形式（`https://github.com/.../pull/123` 等）の場合は、`gh pr view "$ARG" --json number -q .number` で PR 番号を抽出する。`#123` 形式の場合は `#` を除去して数値のみにする。以降の手順では正規化された数値 PR 番号を `{number}` として使用する。

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
# API コール用に owner と repo を分割
OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"
```

失敗時: 「GitHub リポジトリのルートディレクトリで実行してください」と案内して STOP。

以降の API コール（`gh api repos/${OWNER}/${REPO_NAME}/...`）では `${OWNER}/${REPO_NAME}` を使用する。

### 3. PR 状態確認

```bash
gh pr view {number} --json state,headRefName,baseRefName -q '.state'
```

- `MERGED` の場合 → 「この PR は既にマージ済みです」と警告し、続行するか確認
- `CLOSED` の場合 → 「この PR はクローズ済みです」と警告し、続行するか確認

### 4. ワーキングツリー確認

```bash
git status --porcelain
```

未コミットの変更がある場合: 「ワーキングツリーに未コミットの変更があります。コミットまたは stash してから再実行してください」と案内して STOP。

### 5. PR ブランチへの切り替え

```bash
gh pr checkout {number}
```

切り替え失敗時: ブランチ名を表示し、手動チェックアウトを案内する。

## 手順

### 1. PR 情報とコメントの取得

以下の API コールで PR の全コメントと resolved 状態を取得する。

```bash
# PR のメタ情報
gh pr view {number} --json title,body,state,headRefName,baseRefName,reviewDecision,reviews,comments

# インラインコードコメント（レビューコメント）
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/comments --paginate

# レビューサマリー
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/reviews --paginate

# レビュースレッドの resolved 状態（GraphQL 経由）
gh pr view {number} --json reviewThreads -q '.reviewThreads[] | {id: .id, isResolved: .isResolved, comments: [.comments[] | {id: .id, databaseId: .databaseId, createdAt: .createdAt, path: .path, line: .line, body: .body}]}'
```

`${OWNER}/${REPO_NAME}` は前提条件チェック 2 で取得・分割した値を使用する。

**取得する情報**:
- REST: 各コメントの `id`、`body`、`path`（ファイル）、`line`（行番号）、`user`、`created_at`
- GraphQL (`reviewThreads`): 各スレッドの `isResolved` と、スレッド内コメントの `id`、`databaseId`、`createdAt`、`path`、`line`
- レビューの決定ステータス（`APPROVED`、`CHANGES_REQUESTED`、`COMMENTED`）

**resolved 判定**: REST API (`pulls/{number}/comments`) ではスレッドの resolved 状態を取得できないため、`gh pr view --json reviewThreads` を使用する。resolved 状態を REST のコメントへマッピングする際は、`reviewThreads` 側で取得したコメントの `id` / `databaseId` を最優先で突合に用いる。これらが直接使えない場合のみ、`createdAt` + `path` + `line` などの複合キーで対応付ける。`body` 文字列だけで突合してはならない（同一文面のコメントで誤マッピングが発生するため）。

### 2. コメントのカテゴリ分類

取得した各コメントを以下の5カテゴリに分類する。

| カテゴリ | 判定基準 | アクション |
|---------|---------|-----------|
| **コード修正必須** | 具体的なコード変更を要求している（「〜に変更して」「〜を修正して」「〜を削除して」） | 修正を実施 |
| **質問・確認** | 「なぜ〜？」「〜の意図は？」「〜で合っていますか？」形式 | コメントで回答 |
| **スタイル・フォーマット** | 命名規則、インデント、フォーマット、コメント追加の指摘 | 修正を実施 |
| **承認・LGTM** | 「LGTM」「いいですね」「問題なし」等の肯定的コメント | 記録のみ |
| **提案（任意）** | "nit:", "suggestion:", "考慮:", "optional:", "余裕があれば" | ユーザーに判断を委ねる |

**分類ルール**:
- `resolved` 済みのコメントはスキップ（対応済みとして記録のみ）
- `APPROVED` レビューに付随するコメントは優先度を下げる
- 1つのコメントが複数カテゴリに該当する場合は、より高い対応レベルのカテゴリを採用

### 3. 対応計画の提示

分類結果をユーザーに提示し、**実行前に必ず確認を取る**。

```
## PR #{number} レビューコメント対応計画

### 自動対応（コード修正必須 + スタイル）: {N}件
| # | ファイル | 行 | レビュアー | 内容要約 | 対応方針 |
|---|---------|-----|----------|---------|---------|
| 1 | {path} | {line} | {user} | {summary} | {plan} |
| ... | | | | | |

### 質問への回答: {N}件
| # | ファイル | 行 | レビュアー | 質問内容 | 回答案 |
|---|---------|-----|----------|---------|--------|
| 1 | {path} | {line} | {user} | {question} | {answer} |
| ... | | | | | |

### ユーザー判断が必要（提案）: {N}件
| # | ファイル | 行 | レビュアー | 提案内容 |
|---|---------|-----|----------|---------|
| 1 | {path} | {line} | {user} | {suggestion} |
| ... | | | | |

### スキップ（解決済み / 承認）: {N}件

**上記の計画で進めてよいですか？**
```

ユーザーが「提案」カテゴリの対応を決定し、計画を承認するまで待機する。

### 4. コメント対応の実施

ユーザー承認後、以下の順序で対応する。

#### 4.1 矛盾するフィードバックの検出

対応開始前に、矛盾するフィードバックがないかチェックする:

- **同一ファイル・同一行範囲**に対する複数レビュアーからの相反する指摘
- **同一トピック**に対する対立する意見（例: 「この関数を分割すべき」vs「この関数はこのままで良い」）

矛盾を検出した場合:
1. 矛盾するコメントのペアをユーザーに提示
2. 各レビュアーのレビューステータス（`APPROVED` / `CHANGES_REQUESTED`）を参考情報として表示
3. どちらのフィードバックを優先するかユーザーの判断を待つ

#### 4.2 コード修正（コード修正必須 + スタイル + 承認された提案）

各コメントに対して:

1. 対象ファイルの該当箇所を Read で読み取る
2. コメントの要求に従って修正を実施
3. 修正が正しいことを確認

全ての修正が完了したら、まとめて品質チェック（手順 5）に進む。

#### 4.3 質問への回答

各質問コメントに対する回答を `gh api` で投稿する:

```bash
# インラインコメントへの返信
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/comments/{comment_id}/replies \
  -f body="{回答内容}"

# 一般コメントへの返信
gh api repos/${OWNER}/${REPO_NAME}/issues/{number}/comments \
  -f body="{回答内容}"
```

### 5. 品質チェック

プロジェクトの `quality-checks.md` ルールに従った品質チェックを実行する。

品質チェック失敗時:
1. 失敗原因を分析し自動修正を試行（最大3回）
2. 自動修正で解決できない場合はユーザーに報告し対応を相談

### 6. コミットとプッシュ

```bash
git add {修正したファイル}
git commit -m "fix: レビューコメント対応 — {変更内容の要約}

対応コメント:
- {コメント1の要約}
- {コメント2の要約}
..."
git push
```

**コミットルール**:
- 修正内容が多岐にわたる場合は、関連性でグループ化して複数コミットに分ける
- 各コミットメッセージにどのレビューコメントに対応したかを記載

### 7. レビュアーへの返信

コード修正を伴うコメントに対し、対応完了を通知する:

```bash
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/comments/{comment_id}/replies \
  -f body="対応しました。{変更内容の簡潔な説明}"
```

### 8. 完了レポート

全ての対応が完了したら、サマリーを表示する:

```
## PR #{number} レビューコメント対応完了

### 対応サマリー
- コード修正: {N}件 完了
- 質問回答: {N}件 完了
- スタイル修正: {N}件 完了
- 提案対応: {N}件（{M}件採用、{K}件見送り）
- スキップ: {N}件（解決済み/承認）

### コミット
- {commit-hash}: {commit-message}
- ...

### 品質チェック結果: {PASS/FAIL}

### 未対応（ある場合）
- {未対応コメントの説明と理由}
```

## ルール

- 対応計画は実行前に必ずユーザーに提示し確認を取る
- 矛盾するフィードバックはユーザーにエスカレートし、独断で判断しない
- `resolved` 済みのコメントは再対応しない
- `APPROVED` レビューのコメントは優先度を下げる（ブロッキングではない）
- プッシュ前に品質チェックが PASS していることを確認する
- 各コミットメッセージに対応したレビューコメントを記載する
- コメント返信は修正プッシュ後に行う（プッシュ前に返信しない）
- PR が `MERGED` / `CLOSED` の場合は原則として対応しない（ユーザーの明示的指示がある場合のみ続行）
