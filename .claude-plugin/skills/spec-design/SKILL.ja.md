---
name: spec-design
description: "仕様駆動開発のフェーズ 2: 機能の技術設計ドキュメントを作成する。要件承認後に使用し、設計ドキュメントの作成、アーキテクチャの定義、機能の構築方法を計画する場合に使用する。トリガー: 'create design', 'design document', 'technical architecture for X', 'how should we build X'、または design.md ドキュメントの作成リクエスト。"
---

# Spec Design（フェーズ 2）

機能の**構築方法**を定義する技術設計ドキュメントを作成する。このフェーズは承認された要件の後、タスク分割の前に行われる。

設計ドキュメントは**2段階（Wave）**で作成される。Wave 1 でユーザーとアーキテクチャの方向性を合わせてから、Wave 2 で詳細を記述する。これにより、方向性のずれによる手戻りを防ぐ。

## 前提条件チェック（必須 — スキップ不可）

他の作業に先立ち、前提ファイルの存在を確認する:

1. `.spec-workflow/specs/{spec-name}/request-spec.md` が存在するか確認
2. `.spec-workflow/specs/{spec-name}/requirements.md` が存在するか確認

**レガシーワークフローの例外**: `request-spec.md` が存在しないが `requirements.md` が既に存在する場合、これはフェーズ 0 導入前に作成されたレガシー仕様である。`request-spec.md` のチェックをスキップして通常通り進める。

`requirements.md` が存在しない場合 — **即座に停止する。** ユーザーに通知: 「requirements.md が存在しないため、設計を開始できません。先に `/spec-requirements` を実行してください。」その後、このスキルを終了する。

| 不足ファイル | 必要なスキル | レガシー時スキップ可？ |
|-------------|---------------|-----------------|
| request-spec.md | `/spec-request-spec` | はい（requirements.md が存在する場合） |
| requirements.md | `/spec-requirements` | いいえ |

---

要件が承認・クリーンアップ済み（フェーズ 1 完了）であること。そうでなければ、先に `/spec-requirements` を使用する。

## 入力

フェーズ 1 と同じ **spec 名**（kebab-case、例: `user-authentication`）。

## プロセス

### 1. リソースの読み込み

**テンプレート** — カスタムを優先し、デフォルトにフォールバック:
1. `.spec-workflow/user-templates/design-template.md`（カスタム）
2. `.spec-workflow/templates/design-template.md`（デフォルト）

**ステアリングドキュメント** — 存在する場合に読み込む:
```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

### 2. 分析と調査

- 承認済みリクエスト仕様を読む: `.spec-workflow/specs/{spec-name}/request-spec.md`
- 承認済み要件を読む: `.spec-workflow/specs/{spec-name}/requirements.md`
- コードベースを探索し、既存のパターンと再利用可能なコンポーネントを把握する
- Web 検索が利用可能な場合、技術選定のベストプラクティスを調査する
- 全要件に対する設計ソリューションが存在することを確認する

---

## Wave 1: アーキテクチャ骨格

**目標**: 詳細に入る前にユーザーとアーキテクチャの方向性を合わせる。

### 3. Wave 1 ドキュメントの作成

以下に列挙するセクションのみを記述し、`.spec-workflow/specs/{spec-name}/design.md` を作成する。
詳細セクション（API 仕様、エラーハンドリング、トレーサビリティ等）は `(Wave 2 で記述)` プレースホルダーとして残す。

**Wave 1 で記述するセクション:**

1. **概要** — 機能の要約とシステム内での位置づけ
2. **アーキテクチャ** — アーキテクチャ図（mermaid）+ 選択したパターンの根拠
3. **コンポーネント一覧** — コンポーネント名と各役割の1行説明のみ（詳細は Wave 2）
4. **DB スキーマ** — テーブル定義、カラム、制約（実装基盤となる重要な決定事項）
5. **主要な設計判断** — 選択した技術とパターンおよびその理由（却下した代替案を含む）

**Wave 1 プレースホルダーの例:**
```markdown
## コンポーネントとインターフェース
(Wave 2 で記述)

## データモデル
(Wave 2 で記述)

## API 設計
(Wave 2 で記述)

## エラーハンドリング
(Wave 2 で記述)

## 要件トレーサビリティマトリクス
(Wave 2 で記述)

## コード再利用分析
(Wave 2 で記述)

## 必須ビルドツール
(Wave 2 で記述)

## 除外テスト環境
(Wave 2 で記述)
```

### 4. アーキテクチャ確認（ユーザーに提示）

Wave 1 ドキュメント作成後、**正式な承認ツールを使用せずに**以下をユーザーに提示する:

```
## アーキテクチャ確認

Wave 1 骨格が完成しました。Wave 2（詳細記述）に進む前に、以下の方向性を確認してください。

**設計概要**
{概要の2-3文の要約}

**選択したアーキテクチャ**
{アーキテクチャ図または構成の要約}

**主要コンポーネント**
{コンポーネント一覧}

**主要 DB スキーマテーブル**
{テーブル一覧}

**主要な設計判断**
{主要な設計判断の要約}

---
方向性に問題なければ「continue」と返信してください。変更が必要な場合は具体的な指示をお願いします。
```

ユーザーのフィードバックに基づいて分岐:

- **「continue」/ 承認**: Wave 2 に進む
- **修正指示**: design.md の Wave 1 セクションを更新し、再度確認を提示する。合意後、Wave 2 に進む

---

## Wave 2: 詳細記述

**目標**: 確定したアーキテクチャに基づいて全詳細を記入し、正式な承認を得る。

### 5. Wave 2 ドキュメントの完成

Wave 1 で `(Wave 2 で記述)` としたすべてのセクションを記入する。

#### コンポーネントとインターフェース

各コンポーネントを以下のフォーマットで記述する:
```markdown
### ComponentName
- **目的:** [このコンポーネントが担当する責務]
- **インターフェース:** [公開メソッド / API シグネチャ]
- **依存関係:** [依存するコンポーネント / 外部サービス]
- **再利用:** [活用する既存コード（具体的なパス付き）]
```

#### データモデル

すべてのエンティティを型定義またはスキーマ形式で記述する。

#### API 設計（該当する場合）

各エンドポイントについて記述する:
- HTTP メソッド、パス、説明
- リクエスト / レスポンス型（フィールド、型、必須 / オプション）
- エラーレスポンス

#### コード再利用分析フォーマット

grep/glob でコードベースを検索し、再利用する既存コードを**具体的なファイルパス**で列挙する。フェーズ 3 で各タスクの `_Leverage` フィールドにコピーされるため、抽象的な記述（例: 「既存の認証ミドルウェアを使用」）は不可。

```markdown
| 再利用対象 | パス | 用途 |
|-------------|------|---------|
| Auth middleware | `src/middleware/auth.rs` | エンドポイントの保護 |
| AppError | `src/error.rs` | 統一エラーレスポンス |
| TestContext | `tests/integration/helpers/context.rs` | テストセットアップ |
```

#### 要件トレーサビリティマトリクスフォーマット

要件と設計コンポーネントのマッピング。**1行に1コンポーネント**を列挙する（`+` で結合しない）。「対象タスク ID」列はフェーズ 3 (spec-tasks) 完了後に遡って記入する。

```markdown
| 要件 ID | 設計コンポーネント | 対象タスク ID | 備考 |
|---------------|-----------------|---------------|-------|
| REQ-1 | UserHandler | (フェーズ 3 後に記入) | CRUD エンドポイント |
| REQ-1 | UserRepository | (フェーズ 3 後に記入) | DB アクセス |
| REQ-2 | AuthMiddleware | (フェーズ 3 後に記入) | 認証チェック |
```

#### エラーハンドリングフォーマット

全エラーコードをテーブル形式で列挙する。設計準拠ルールにより、実装時にこのリスト外のエラーコードの追加が禁止されるため、想定されるすべてのエラーケースを網羅的に定義する。

```markdown
## エラーハンドリング

エラーレスポンス形式: `{ "error": { "code": "...", "message": "..." } }`

| エラーコード | HTTP ステータス | 発生条件 |
|-----------|-------------|------------------|
| NotFound | 404 | リソースが存在しない |
| BadRequest | 400 | バリデーション失敗、不正な入力 |
| Unauthorized | 401 | 認証失敗、無効/期限切れトークン |
| Forbidden | 403 | 認可失敗、権限不足 |
| Conflict | 409 | 重複キー、楽観的ロック競合 |
| Internal | 500 | 予期しない内部エラー |
```

#### 必須ビルドツール

Wave 1 の主要な設計判断に基づき、プロジェクトのビルド、テスト、実行に必要なすべての CLI ツールを列挙する。コードベースを検索して現在のツールバージョンを検出する。

```markdown
## 必須ビルドツール

| ツール | 最小バージョン | 用途 | 確認コマンド | インストールコマンド | 必須 |
|------|-------------|---------|---------------|-----------------|----------|
| cargo | >= 1.82 | Rust ビルドシステム | cargo --version | rustup update | Yes |
| docker | >= 24.0 | コンテナランタイム | docker --version | apt install docker.io | Yes |
```

導出ルール:
1. 主要な設計判断の技術選定 → 対応するビルドツール（Rust → cargo, Node.js → node+npm 等）
2. コンテナアーキテクチャ → docker / podman
3. テスト戦略概要 → ビルドや基本テストに必要なツール（E2E ブラウザテスト用の playwright/chromium 等は test-design.md の Required Test Tools に記載）
4. 確認コマンドは、ツールがインストール済みなら exit 0 になる単一コマンド
5. 必須列: `Yes`（必須）または `Recommended`（推奨）のみ。E2E テストに必要なツール（Playwright, Chrome等）は設計時に Required=Yes として明記すること

#### 除外テスト環境

特定環境でのみ実行可能なテスト（特殊ハードウェア依存等）がある場合に、除外理由と代替検証方法を明記する。

```markdown
## 除外テスト環境

| テストカテゴリ | 除外テスト | 理由 | 代替検証 |
|--------------|---------------|--------|------------------------|
| E2E | E2E-3 (iOS Safari 検証) | CI に iOS デバイスがない | BrowserStack で手動検証 |
```

**重要**: 設計時に明示的に除外宣言されていないテストは、すべて実装フェーズで実行必須。Docker/Chrome/サーバー起動/DB 等の不足は除外理由にならない（design.md/test-design.md の Required Tools で対応すべき）。除外テストがない場合はテーブルを空にする（セクション自体は残す）。

### 6. サブエージェントによるセルフレビュー（承認前）

Wave 2 完了後、正式な承認をリクエストする前に **2ステップ**でレビューする。

#### ステップ A: fix（自動的な機械的修正）

プレースホルダー、フォーマット、タイプミスを自動修正する。内容の追加や変更は行わない:

```
Agent({
  subagent_type: "general-purpose",
  description: "Fix design spec (auto-fix)",
  prompt: "You are a spec document reviewer. Auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Document type: design

    Auto-fix targets (you may edit the file directly):
    - Remove placeholder text ([describe...], TODO, TBD, '(to be written in Wave 2)', etc.)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Obvious typos

    Do NOT auto-fix (report as issues only):
    - Adding or removing sections
    - Adding or changing content (design components, error codes, DB schema, etc.)
    - Traceability inconsistencies

    Mode: fix — Return a structured report (auto-fixed items + remaining issues)."
})
```

#### ステップ B: check（内容の検証）

fix 完了後、内容上の問題を検出する。ファイルを変更しない:

```
Agent({
  subagent_type: "general-purpose",
  description: "Review design spec (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Document type: design
    Template: {project-path}/.spec-workflow/templates/design-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no placeholders or '(to be written in Wave 2)' remaining)
    2. CROSS-REFERENCE: Read requirements.md — every requirement must have a corresponding design solution.
       No design component should exist without a backing requirement.
    3. Must include: Overview, Architecture diagram, Component details (Purpose/Interfaces/Dependencies/Reuses),
       Data Models, Error Handling table, Requirements Traceability Matrix, Code Reuse Analysis with concrete paths,
       Required Build Tools table, Excluded Test Environments section
    4. Data models must cover all entities referenced in requirements
    5. Error Handling must have a complete table (not just scenario descriptions)
    6. Required Build Tools section must exist with at least one tool entry in table format (Tool, Min Version, Purpose, Check Command, Install Command, Required columns)
    7. Excluded Test Environments section must exist (table may be empty if no exclusions, but section must be present)

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

check が FAIL を返した場合、自分で問題を修正し、check を再実行する（最大3回）。PASS になったら承認に進む。

### 7. 承認ワークフロー

正式な承認 — 口頭での承認は受け付けない。

1. **承認をリクエスト**: `approvals` ツール、`action: 'request'`、filePath のみ（content は含めない）。返された `approvalId` を保存する。

2. **自動ポーリング**: 自動ステータス確認を開始:
   ```
   /loop 1m /check-approval <approvalId>
   ```
   ループは毎分自動的に承認ステータスを確認し、結果を処理する:
   - **pending**: ポーリング継続（アクション不要）
   - **approved**: クリーンアップが自動的に実行され、ループが停止
   - **needs-revision**: ループが停止し、レビューアのコメントが表示される

3. **needs-revision のハンドリング**（修正要求でループが停止した場合）:
   - レビューコメントを読み、ドキュメントを更新し、サブエージェントレビューを再実行する
   - 新しい承認リクエストを送信し、新しい `/loop 1m /check-approval <newApprovalId>` を開始する

4. **次のフェーズ**: 承認とクリーンアップが成功したら、**自動的に**フェーズ 3（テスト設計）に進む。
   `/spec-test-design` スキルを読み込み、即座に開始する — ユーザーの入力を待たない。

## ルール

- 機能名は kebab-case を使用
- 一度に1つの spec のみ
- **Wave 1 完了前に Wave 2 を開始しない** — ユーザーの確認が必要
- **Wave 1 では口頭確認も可** — 正式な承認ツールは不要
- **Wave 2 完了後は正式な承認が必要** — 口頭での承認は不可
- 承認リクエスト: filePath のみ、content は含めない
- 承認の削除に失敗した場合は進まない
- タスクに移る前に、承認済みステータスとクリーンアップの成功が必要
