---
name: spec-requirements
description: "スペック駆動開発の Phase 1: 機能の要件ドキュメントを作成する。ユーザーが新しいスペックの開始、要件の定義、または機能のスペックワークフロー開始を望む場合に使用する。トリガー: 'create requirements'、'new spec for X'、'start spec workflow'、'define what to build'、またはrequirements.mdドキュメントの作成リクエスト。"
---

# スペック要件定義（Phase 1）

ユーザーのニーズに基づいて**何を**構築するかを定義する要件ドキュメントを作成する。これはスペック駆動開発ワークフロー（リクエスト仕様 → 要件定義 → 設計 → テスト設計 → タスク → 実装）の2番目のフェーズである。

## 前提条件チェック（必須 — スキップ禁止）

他のことを行う前に、前提条件ファイルの存在を確認する:

1. `.spec-workflow/specs/{spec-name}/request-spec.md` が存在するかチェック

**レガシーワークフローの例外**: `request-spec.md` が存在しないが、スペックディレクトリに `requirements.md` が既に存在する場合、これは Phase 0 が導入される前に作成されたレガシースペックである。この場合、request-spec の前提条件をスキップして通常通り進行する。

存在せず、かつ下流ドキュメントも存在しない場合 — **直ちに停止する。** ユーザーに伝える: 「request-spec.md が存在しないため要件定義を開始できません。先に `/spec-request-spec` を実行してください。」そしてこのスキルを終了する。

---

リクエスト仕様書が承認・クリーンアップ済み（Phase 0 完了）であること。そうでない場合は先に `/spec-request-spec` を使用する。

## 入力

**スペック名**を kebab-case で指定する必要がある（例: `user-authentication`、`data-export`）。ユーザーが提供していない場合は確認する。

## プロセス

### 1. コンテキストの収集

承認済みのリクエスト仕様書とステアリングドキュメント（存在する場合）を読み込む:

```
.spec-workflow/specs/{spec-name}/request-spec.md
```

```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

### 2. テンプレートの読み込み

カスタムテンプレートを最初にチェックする。存在しない場合はデフォルトにフォールバック:

1. `.spec-workflow/user-templates/requirements-template.md`（カスタム）
2. `.spec-workflow/templates/requirements-template.md`（デフォルト）

プロジェクト全体の一貫性のため、テンプレート構造に正確に従う。

### 3. 調査と作成

- Web 検索が利用可能な場合、現在の市場の期待とベストプラクティスを調査する
- EARS 基準（Event、Action、Response、State）を使用してユーザーストーリーとして要件を生成する
- すべての機能要件と非機能要件をカバーする
- 包括的であること — 設計フェーズは完全な要件に依存する

### 4. ドキュメントの作成

以下のパスにファイルを書き出す:
```
.spec-workflow/specs/{spec-name}/requirements.md
```

### 5. サブエージェントによるセルフレビュー（承認前）

承認をリクエストする前に、ドキュメントを**2段階**で検証する。

#### ステップ A: fix（自動的な機械的修正）

プレースホルダー、フォーマット、タイプミスを自動修正する。内容の追加や変更は行わない:

```
Agent({
  subagent_type: "general-purpose",
  description: "要件仕様書の修正（自動修正）",
  prompt: "あなたはスペックドキュメントのレビュアーです。以下のドキュメントの軽微な問題を自動修正してください:
    {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    ドキュメントタイプ: requirements

    自動修正対象（ファイルを直接変更してよい）:
    - プレースホルダーテキストの削除（[describe...]、TODO、TBD）
    - Markdown フォーマットの修正（テーブル整列、見出しレベルなど）
    - 明らかなタイプミスの修正

    自動修正対象外（問題として報告のみ）:
    - セクションの追加・削除
    - 内容の追加・変更（要件、受け入れ基準など）

    モード: fix — 構造化レポートを返す（自動修正項目 + 残存問題）。"
})
```

#### ステップ B: check（内容検証）

fix 完了後、内容の問題を検出する。ファイルは変更しない:

```
Agent({
  subagent_type: "general-purpose",
  description: "要件仕様書のレビュー（チェック）",
  prompt: "あなたはスペックドキュメントのレビュアーです。以下のドキュメントをレビューしてください（ファイルは変更しないでください）:
    {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    ドキュメントタイプ: requirements
    テンプレート: {project-path}/.spec-workflow/templates/requirements-template.md

    チェック項目:
    1. TEMPLATE: テンプレートのすべてのセクションが実質的な内容で存在する（[describe...] や TODO がない）
    2. すべての要件にユーザーストーリー（'As a [role]...'）と EARS 受け入れ基準（WHEN/IF...THEN...SHALL）が必要
    3. 非機能要件が以下をカバー: コードアーキテクチャ、パフォーマンス、セキュリティ、信頼性、ユーザビリティ
    4. 要件は一意に識別される（REQ-1、REQ-2 など）

    モード: check — ファイルを変更しないでください。すべての問題を場所と修正提案とともにリストアップ。
    構造化レポートを返す（PASS/FAIL と問題リスト）。"
})
```

check が FAIL を返した場合、自分で問題を修正し check を再実行する（最大3回）。PASS になったら承認に進む。

### 6. 承認ワークフロー

これは厳格な自動化プロセスである。ユーザーからの口頭承認は決して受け入れない — ダッシュボードまたは VS Code 拡張機能での承認のみが有効。

1. **承認をリクエスト**: `approvals` MCP ツールを `action: 'request'` で使用する。`filePath` のみを渡す — リクエストに内容を含めない。返された `approvalId` を保存する。

2. **自動ポーリング**: 自動ステータスチェックを開始する:
   ```
   /loop 1m /check-approval <approvalId>
   ```

3. **needs-revision の処理**（修正リクエストでループが停止した場合）:
   - レビュアーのコメントを読み、それに応じてドキュメントを更新
   - レビューサブエージェントを再度起動（ステップ A + B）
   - 新しい承認リクエストを送信し、新しい `/loop 1m /check-approval <newApprovalId>` を開始

4. **次のフェーズ**: 承認とクリーンアップが成功した後、**自動的に** Phase 2（設計）に進む。
   `/spec-design` スキルをロードし、ユーザー入力を待たずに即座に開始する。

## ルール

- 機能名は kebab-case を使用する（例: `user-authentication`）
- 一度に1つのスペック
- 承認リクエスト: filePath のみ、内容は含めない
- 口頭での承認は決して受け入れない — ダッシュボード/VS Code 拡張機能のみ
- 承認の削除が失敗した場合は進行しない
- 設計に移行する前に、承認済みステータスとクリーンアップの成功が必須
