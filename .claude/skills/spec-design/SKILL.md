---
name: spec-design
description: "Phase 2 of spec-driven development: create a technical design document for a feature. Use this skill after requirements are approved, when the user wants to create a design doc, define architecture, or plan how to build a feature. Triggers on: 'create design', 'design document', 'technical architecture for X', 'how should we build X', or any request to create a design.md document."
---

# Spec Design (Phase 2)

Create a technical design document that defines **how** to build the feature. This phase follows approved requirements and precedes task breakdown.

設計ドキュメントは **2段階（Wave）** で作成する。Wave 1 でアーキテクチャの方向性をユーザーと合わせてから、Wave 2 で詳細を記述することで、方向性のズレによる手戻りを防ぐ。

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify the prerequisite file exists:

1. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists

If missing — **STOP immediately.** ユーザーに「requirements.md が存在しないため設計を開始できません。先に `/spec-requirements` を実行してください。」と伝えてこのスキルを終了する。

---

Requirements must be approved and cleaned up (Phase 1 complete). If not, use `/spec-requirements` first.

## Inputs

The same **spec name** used in Phase 1 (kebab-case, e.g., `user-authentication`).

## Process

### 1. Load Resources

**テンプレート** — カスタムを優先してフォールバック:
1. `.spec-workflow/user-templates/design-template.md` (custom)
2. `.spec-workflow/templates/design-template.md` (default)

**Steering ドキュメント** — 存在する場合は読み込む:
```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

### 2. Analyze and Research

- 承認済み要件を読む: `.spec-workflow/specs/{spec-name}/requirements.md`
- コードベースを調査して既存パターン・再利用可能コンポーネントを把握する
- web search が使える場合は技術選択のベストプラクティスを調査する
- 全要件に対応する設計ソリューションが揃うことを確認する

---

## Wave 1: アーキテクチャスケルトン

**目的**: 詳細に入る前にアーキテクチャの方向性をユーザーと合わせる。

### 3. Wave 1 ドキュメント作成

以下のセクションのみ記述して `.spec-workflow/specs/{spec-name}/design.md` を作成する。
詳細セクション（API 仕様・エラーハンドリング・トレーサビリティ等）は `(Wave 2 で記述)` のプレースホルダーにとどめる。

**Wave 1 で記述するセクション:**

1. **Overview** — 機能の概要とシステム内での位置づけ
2. **Architecture** — アーキテクチャ図（mermaid）+ 採用パターンの根拠
3. **Component List** — コンポーネント名と1行の役割説明のみ（詳細は Wave 2）
4. **DB Schema** — テーブル定義・カラム・制約（実装の根幹となる重要な意思決定）
5. **Key Design Decisions** — 採用した技術・パターンとその理由（却下した代替案も記載）

**Wave 1 のプレースホルダー例:**
```markdown
## Components and Interfaces
(Wave 2 で記述)

## Data Models
(Wave 2 で記述)

## API Design
(Wave 2 で記述)

## Error Handling
(Wave 2 で記述)

## Requirements Traceability Matrix
(Wave 2 で記述)

## Code Reuse Analysis
(Wave 2 で記述)
```

### 4. アーキテクチャ確認（ユーザーへの提示）

Wave 1 のドキュメントを作成したら、**正式な承認ツールを使わずに**以下をユーザーに提示する:

```
## アーキテクチャ確認

Wave 1 のスケルトンを作成しました。詳細の記述（Wave 2）に進む前に、以下の方向性をご確認ください。

**設計の概要**
{Overview の要約 2〜3文}

**採用アーキテクチャ**
{アーキテクチャ図または構成の概要}

**主要コンポーネント**
{コンポーネント一覧}

**DBスキーマの主要テーブル**
{テーブル一覧}

**重要な設計判断**
{Key Design Decisions の要約}

---
方向性に問題がなければ「続けて」、修正が必要な場合は具体的な指示をお願いします。
```

ユーザーのフィードバックに応じて分岐:

- **「続けて」/ 承認**: Wave 2 へ進む
- **修正指示**: design.md の Wave 1 セクションを修正して、再度確認を提示する。合意が取れたら Wave 2 へ進む

---

## Wave 2: 詳細記述

**目的**: 確定したアーキテクチャを基に全詳細を記述し、正式承認を得る。

### 5. Wave 2 ドキュメント補完

Wave 1 で `(Wave 2 で記述)` としたセクションを全て埋める。

#### Components and Interfaces

各コンポーネントを以下の形式で記述:
```markdown
### ComponentName
- **Purpose:** [このコンポーネントが担う責務]
- **Interfaces:** [公開メソッド/API シグネチャ]
- **Dependencies:** [依存するコンポーネント/外部サービス]
- **Reuses:** [活用する既存コード（具体パス）]
```

#### Data Models

全エンティティを型定義またはスキーマ形式で記述する。

#### API Design（該当する場合）

エンドポイントごとに以下を記述:
- HTTP メソッド・パス・説明
- リクエスト/レスポンス型（フィールド・型・必須/任意）
- エラーレスポンス

#### Code Reuse Analysis フォーマット

コードベースを grep/glob で調査し、再利用すべき既存コードを**具体的なファイルパス**で列挙する。Phase 3 で `_Leverage` フィールドに転記されるため、抽象的な記述（「既存の認証ミドルウェアを使う」等）は不可。

```markdown
| 再利用対象 | パス | 用途 |
|-----------|------|------|
| 認証ミドルウェア | `src/middleware/auth.rs` | エンドポイント保護 |
| AppError | `src/error.rs` | エラーレスポンス統一 |
| TestContext | `tests/integration/helpers/context.rs` | テストセットアップ |
```

#### Requirements Traceability Matrix フォーマット

要件→設計コンポーネントのマッピング。**コンポーネントは1行1つ**で列挙する（`+` で結合しない）。「対象タスク ID」列は Phase 3 (spec-tasks) 完了後に逆記入する。

```markdown
| Requirement ID | 設計コンポーネント | 対象タスク ID | 備考 |
|---------------|-------------------|-------------|------|
| REQ-1 | UserHandler | (Phase 3 後に記入) | CRUD エンドポイント |
| REQ-1 | UserRepository | (Phase 3 後に記入) | DB アクセス |
| REQ-2 | AuthMiddleware | (Phase 3 後に記入) | 認証チェック |
```

#### Error Handling フォーマット

全エラーコードをテーブル形式で列挙する。実装時にこの一覧外のエラーコードを追加することは design-conformance ルールで禁止されるため、想定される全エラーケースを網羅的に定義すること。

```markdown
## Error Handling

エラーレスポンスフォーマット: `{ "error": { "code": "...", "message": "..." } }`

| エラーコード | HTTP Status | 発生条件 |
|-------------|-------------|---------|
| NotFound | 404 | リソースが存在しない |
| BadRequest | 400 | バリデーション失敗、不正な入力 |
| Unauthorized | 401 | 認証失敗、トークン無効/期限切れ |
| Forbidden | 403 | 認可失敗、権限不足 |
| Conflict | 409 | 重複キー、楽観的ロック競合 |
| Internal | 500 | 予期しない内部エラー |
```

### 6. Self-Review via Subagent (before approval)

Wave 2 完了後、サブエージェントでレビューしてから正式承認を依頼する:

```
Agent({
  subagent_type: "general-purpose",
  description: "Review design spec",
  prompt: "You are a spec document reviewer. Review and fix the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Document type: design
    Template: {project-path}/.spec-workflow/templates/design-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no placeholders or '(Wave 2 で記述)' remaining)
    2. CROSS-REFERENCE: Read requirements.md — every requirement must have a corresponding design solution.
       No design component should exist without a backing requirement.
    3. Must include: Overview, Architecture diagram, Component details (Purpose/Interfaces/Dependencies/Reuses),
       Data Models, Error Handling table, Requirements Traceability Matrix, Code Reuse Analysis with concrete paths
    4. Data models must cover all entities referenced in requirements
    5. Error Handling must have a complete table (not just scenario descriptions)

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

サブエージェントの完了を待ち、指摘があれば修正してから承認へ進む。

### 7. Approval Workflow

正式な承認 — 口頭承認は受け付けない。

1. **Request approval**: `approvals` ツール、`action: 'request'`、filePath のみ（content を含めない）
2. **Poll status**: `approvals` ツール、`action: 'status'`、status が変わるまでポーリング
3. **Handle result**:
   - **needs-revision**: レビューコメントを読んでドキュメントを更新、サブエージェントレビューを再実行、NEW な承認リクエストを送信
   - **approved**: クリーンアップへ
4. **Cleanup**: `approvals` ツール、`action: 'delete'` — 必ず成功させる
   - delete 失敗時: STOP、ポーリングに戻る
5. **Next phase**: クリーンアップ成功後、Phase 3 (Tasks) へ進む。`/spec-tasks` スキルを使用。

## Rules

- Feature names use kebab-case
- One spec at a time
- **Wave 1 完了前に Wave 2 を開始しない** — ユーザーの確認が必須
- **Wave 1 の口頭確認は許可** — 正式承認ツール不要
- **Wave 2 完了後の正式承認は必須** — 口頭承認は不可
- Approval requests: filePath only, never content
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before moving to tasks
