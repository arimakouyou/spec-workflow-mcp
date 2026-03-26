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
    purpose: ...            # このエンドポイントの目的・役割
    location: path/to/file  # 実装されているソースファイル
    requestFormat: ...      # (任意) 主なリクエスト形式
    responseFormat: ...     # (任意) 主なレスポンス形式
components:       # 作成したUIコンポーネント
  - name: ...
    type: ...               # コンポーネントの種類（page, widget等）
    purpose: ...            # コンポーネントの目的・役割
    location: path/to/file  # 実装されているソースファイル
    props: ...              # (任意) 主要なプロパティ
    exports: [...]          # (任意) エクスポートされる名前
functions:        # 作成したユーティリティ関数
  - name: ...
    purpose: ...            # 関数の目的・役割
    location: path/to/file  # 実装されているソースファイル
    signature: ...          # (任意) 関数シグネチャ
    isExported: true/false  # モジュールの公開APIかどうか
classes:          # 作成したクラス
  - name: ...
    purpose: ...            # クラスの目的・役割
    location: path/to/file  # 実装されているソースファイル
    methods: [...]          # (任意) 主要メソッド名
    isExported: true/false  # モジュールの公開APIかどうか
integrations:     # フロントエンド-バックエンド連携パターン
  - description: ...          # 連携の目的・ユースケース
    frontendComponent: ...    # 関連するUIコンポーネント名/パス
    backendEndpoint: ...      # 関連するAPIエンドポイント（method + path）
    dataFlow: ...             # どのAPI/コンポーネント間でどのようにデータが流れるか
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

**ファイル形式**（ダッシュボードの `ImplementationLogManager` パーサーと互換性のある形式）:

```markdown
# Implementation Log: Task {taskId}

**Summary:** {summary}

**Timestamp:** {ISO 8601形式、例: 2026-03-26T13:30:00.000Z}
**Log ID:** {ユニークID、例: task-{taskId}_{YYYYMMDD}_{HHMMSS}}

---

## Statistics

- **Lines Added:** +{linesAdded}
- **Lines Removed:** -{linesRemoved}
- **Files Changed:** {filesModified.length + filesCreated.length}
- **Net Change:** {linesAdded - linesRemoved}

## Files Modified
{filesModified を各行 `- path/to/file` 形式で。なければ `_No files modified_`}

## Files Created
{filesCreated を各行 `- path/to/file` 形式で。なければ `_No files created_`}

---

## Artifacts

{artifacts が空なら `_No artifacts recorded_`}

### API Endpoints
{各エンドポイントを以下の形式で:}
#### {method} {path}
- **Purpose:** {purpose}
- **Location:** {location}
- **Request Format:** {requestFormat}  ← 任意
- **Response Format:** {responseFormat}  ← 任意

### Components
{各コンポーネントを以下の形式で:}
#### {name}
- **Type:** {type}
- **Purpose:** {purpose}
- **Location:** {location}

### Functions
{各関数を以下の形式で:}
#### {name}
- **Purpose:** {purpose}
- **Location:** {location}
- **Exported:** Yes/No

### Classes
{各クラスを以下の形式で:}
#### {name}
- **Purpose:** {purpose}
- **Location:** {location}
- **Exported:** Yes/No

### Integrations
{各連携を以下の形式で:}
#### Integration
- **Description:** {description}
- **Frontend Component:** {frontendComponent}
- **Backend Endpoint:** {backendEndpoint}
- **Data Flow:** {dataFlow}

---

## Review Process

{reviewProcess をJSON形式で記述（パーサーがJSON.parseする）:}

```json
{
  "reworkCount": {reworkCount},
  "outcome": "{reviewOutcome}",
  "findings": [
    {findings があれば各attemptのオブジェクト。なければ空配列}
  ]
}
```
```

### 3. 作成確認

ファイルが正常に作成されたことを確認し、ユーザーに報告する。
