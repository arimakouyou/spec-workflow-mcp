---
name: log-implementation
description: "タスク実装完了後にMarkdown形式の実装ログを記録する。必須: specName, taskId, summary, filesModified, filesCreated, statistics, artifacts。タスクを [x] にする前に必ず呼び出すこと。Triggers on: /log-implementation invocation, or when implementation logging is needed after task completion."
---

# Log Implementation — 実装ログ記録

タスク実装完了後に、実装内容をMarkdownファイルとして構造化記録する。

## 重要ルール

**タスクを `[x]` にマークする前に、必ずこのスキルを実行すること。** ログのないタスク完了は許可されない。

## 入力

以下の情報を収集してからログを作成する:

| 項目 | 必須 | 説明 |
|------|:---:|------|
| specName | Yes | スペック名（kebab-case） |
| taskId | Yes | タスクID（例: "1", "1.2", "3.1.4"） |
| summary | Yes | 実装概要（1行） |
| filesModified | Yes | 変更したファイル一覧 |
| filesCreated | Yes | 作成したファイル一覧 |
| statistics | Yes | `linesAdded` と `linesRemoved` |
| artifacts | Yes | 構造化データ（下記参照） |
| reviewProcess | No | レビュー品質メトリクス |

### artifacts 構造

```yaml
apiEndpoints:     # 作成/変更したAPIエンドポイント
  - method: GET/POST/PUT/DELETE
    path: /api/...
    description: ...
components:       # 作成したUIコンポーネント
  - name: ...
    path: ...
functions:        # 作成したユーティリティ関数
  - name: ...
    path: ...
    description: ...
classes:          # 作成したクラス
  - name: ...
    path: ...
integrations:     # フロントエンド-バックエンド連携パターン
  - description: ...
```

### reviewProcess 構造（オプション）

```yaml
reworkCount: 0      # 差し戻し回数（0 = 初回レビュー通過）
reviewOutcome: commit  # commit | escalated
findings:           # reworkCount > 0 の場合のみ
  - attempt: 1
    categories: [...]
    summary: ...
    action: rework | commit | escalate
```

## 手順

### 1. タスク存在チェック

`.spec-workflow/specs/{specName}/tasks.md` を読み、`{taskId}` が存在するか確認する。

### 2. ログファイル作成

**パス**: `.spec-workflow/specs/{specName}/Implementation Logs/task-{taskId}_{YYYYMMDD}_{HHMMSS}.md`

**ディレクトリが存在しない場合は作成する。**

**ファイル形式**:

```markdown
# Task {taskId}: {summary}

**Date**: {YYYY-MM-DD HH:MM:SS}
**Spec**: {specName}

## Summary
{summary}

## Files Modified
{filesModified をリスト形式で}

## Files Created
{filesCreated をリスト形式で}

## Statistics
- Lines added: {linesAdded}
- Lines removed: {linesRemoved}

## Artifacts

### API Endpoints
{apiEndpoints をテーブル形式で}

### Components
{components をリスト形式で}

### Functions
{functions をリスト形式で}

### Classes
{classes をリスト形式で}

### Integrations
{integrations をリスト形式で}

## Review Process
- Rework count: {reworkCount}
- Outcome: {reviewOutcome}
{findings があれば各attemptの詳細}
```

### 3. 作成確認

ファイルが正常に作成されたことを確認し、ユーザーに報告する。
