---
name: spec-request-spec
description: "スペック駆動開発の Phase 0: ユースケース、技術スタック、実行環境を定義するリクエスト仕様書を作成する。新しいスペックを開始する際、要件定義の前の最初のフェーズとして使用する。トリガー: 'create request spec'、'new spec for X'、'start spec workflow'、'define use cases'、'select tech stack'、またはrequest-spec.mdドキュメントの作成リクエスト。"
---

# スペックリクエスト仕様書（Phase 0）

詳細な要件定義に入る前に、**ユースケース**、**技術スタック**、**実行環境**を定義するリクエスト仕様書を作成する。これはスペック駆動開発ワークフロー（リクエスト仕様 → 要件定義 → 設計 → テスト設計 → タスク → 実装）の最初のフェーズである。

## 入力

**スペック名**を kebab-case で指定する必要がある（例: `user-authentication`、`data-export`）。ユーザーが提供していない場合は確認する。

## プロセス

### 1. コンテキストの収集

ステアリングドキュメントが存在する場合は読み込む — これらにはリクエスト仕様書に反映すべきプロジェクトレベルのガイダンスが含まれている:

```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

`tech.md` が存在する場合、リクエスト仕様書の技術スタックセクションでは**機能固有の追加技術**のみを記述する — プロジェクトレベルのベース技術を重複記載しない。

### 2. テンプレートの読み込み

カスタムテンプレートを最初にチェックする。存在しない場合はデフォルトにフォールバック:

1. `.spec-workflow/user-templates/request-spec-template.md`（カスタム）
2. `.spec-workflow/templates/request-spec-template.md`（デフォルト）

プロジェクト全体の一貫性のため、テンプレート構造に正確に従う。

### 3. 調査と作成

- ユーザーと議論して機能の基本ユースケースを確認する
- 必要な技術スタックを特定する（tech.md が存在する場合は機能固有の追加のみ）
- 実行環境とその制約を確認する
- 明確なスコープ境界を定義する（スコープ内とスコープ外を明示）
- Web 検索が利用可能な場合、関連する技術オプションとベストプラクティスを調査する

### 4. ドキュメントの作成

以下のパスにファイルを書き出す:
```
.spec-workflow/specs/{spec-name}/request-spec.md
```

### 5. サブエージェントによるセルフレビュー（承認前）

承認をリクエストする前に、ドキュメントを**2段階**で検証する。

#### ステップ A: fix（自動的な機械的修正）

プレースホルダー、フォーマット、タイプミスを自動修正する。内容の追加や変更は行わない:

```
Agent({
  subagent_type: "general-purpose",
  description: "リクエスト仕様書の修正（自動修正）",
  prompt: "あなたはスペックドキュメントのレビュアーです。以下のドキュメントの軽微な問題を自動修正してください:
    {project-path}/.spec-workflow/specs/{spec-name}/request-spec.md

    ドキュメントタイプ: request-spec

    自動修正対象（ファイルを直接変更してよい）:
    - プレースホルダーテキストの削除（[describe...]、TODO、TBD）
    - Markdown フォーマットの修正（テーブル整列、見出しレベルなど）
    - 明らかなタイプミスの修正

    自動修正対象外（問題として報告のみ）:
    - セクションの追加・削除
    - 内容の追加・変更（ユースケース、技術選定など）

    モード: fix — 構造化レポートを返す（自動修正項目 + 残存問題）。"
})
```

#### ステップ B: check（内容検証）

fix 完了後、内容の問題を検出する。ファイルは変更しない:

```
Agent({
  subagent_type: "general-purpose",
  description: "リクエスト仕様書のレビュー（チェック）",
  prompt: "あなたはスペックドキュメントのレビュアーです。以下のドキュメントをレビューしてください（ファイルは変更しないでください）:
    {project-path}/.spec-workflow/specs/{spec-name}/request-spec.md

    ドキュメントタイプ: request-spec
    テンプレート: {project-path}/.spec-workflow/templates/request-spec-template.md

    チェック項目:
    1. TEMPLATE: テンプレートのすべてのセクションが実質的な内容で存在する（[describe...] や TODO がない）
    2. USE CASES: Actor、Purpose、Basic Flow、Post-conditions が定義されたユースケースが少なくとも1つ
    3. TECH STACK: 技術選定テーブルに具体的なエントリがある（プレースホルダーなし）
    4. EXECUTION ENVIRONMENT: ターゲット環境と制約が指定されている
    5. SCOPE: 「In Scope」と「Out of Scope」の両セクションに具体的なエントリがある

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
   ループは毎分自動的に承認ステータスを確認し、結果を処理する:
   - **pending**: ポーリング継続（アクション不要）
   - **approved**: クリーンアップが自動的に実行され、ループ停止
   - **needs-revision**: ループ停止、レビュアーのコメントが表示される

3. **needs-revision の処理**（修正リクエストでループが停止した場合）:
   - レビュアーのコメントを読み、それに応じてドキュメントを更新
   - レビューサブエージェントを再度起動（ステップ A + B）
   - 新しい承認リクエストを送信し、新しい `/loop 1m /check-approval <newApprovalId>` を開始

4. **次のフェーズ**: 承認とクリーンアップが成功した後、**自動的に** Phase 1（要件定義）に進む。
   `/spec-requirements` スキルをロードし、ユーザー入力を待たずに即座に開始する。

## ルール

- 機能名は kebab-case を使用する（例: `user-authentication`）
- 一度に1つのスペック
- 承認リクエスト: filePath のみ、内容は含めない
- 口頭での承認は決して受け入れない — ダッシュボード/VS Code 拡張機能のみ
- 承認の削除が失敗した場合は進行しない
- 要件定義に移行する前に、承認済みステータスとクリーンアップの成功が必須
- steering/tech.md が存在する場合、機能固有の技術追加のみを記述する
