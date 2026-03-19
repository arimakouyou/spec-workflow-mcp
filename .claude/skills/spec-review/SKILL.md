---
name: spec-review
description: "Self-review a specification document before requesting user approval. This skill is designed to run as a subagent — spawn it with the Agent tool to keep review details out of the main context. Use automatically after creating or updating any spec document (requirements.md, design.md, tasks.md) and BEFORE requesting approval. Triggers on: any spec document creation, before approval requests, 'review spec', 'check spec quality'."
---

# Spec Review (Subagent)

This skill is designed to run as a **subagent** via the Agent tool.2つのモードがある。

## Mode: check（デフォルト — Approval 前のレビュー）

**ファイルを修正しない。** 問題を検出して一覧を返すだけ。呼び出し元が指摘を見て自分で修正し、再度 check を実行する。内容の追加・変更は行わない（レビュアーが勝手に「発明」しない）。

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "Review spec document (check)",
  prompt: `You are a spec document reviewer. Check the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/{doc-type}.md

    Document type: {doc-type}
    Spec name: {spec-name}
    Mode: check

    Follow the /spec-review skill instructions below:

    1. TEMPLATE COMPLIANCE: Re-read the template at .spec-workflow/templates/{doc-type}-template.md
       and verify every section is present with substantive content (no placeholders like [describe...] or TODO).

    2. CROSS-REFERENCE CHECK:
       - For design.md: verify every requirement in requirements.md has a design solution
       - For tasks.md: verify every requirement has a task, every design component has a task,
         _Requirements references match actual IDs, task ordering respects dependencies

    3. QUALITY CHECK: No placeholder text, no duplicates, consistent naming, testable acceptance criteria,
       realistic error scenarios, task descriptions specific enough for AI implementation.

    4. DO NOT modify the file. List all issues found with their location and suggested fix.

    5. Return a structured report (see Output Format below).`
})
```

呼び出し元のフロー:
1. check モードで spec-review を実行
2. issues が 0 件 → Approval へ進む
3. issues が 1 件以上 → 呼び出し元が issues を見て design.md/tasks.md を修正
4. 再度 check モードで確認（issues 0 になるまで繰り返し、最大3回）

## Mode: fix（軽微な自動修正のみ）

placeholder テキスト削除、フォーマット修正等の**機械的修正のみ**実行する。内容の追加・変更（セクション追加、要件追加、エラーコード追加等）は行わず、issues として報告する。

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "Review spec document (fix)",
  prompt: `You are a spec document reviewer. Check and auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/{doc-type}.md

    Document type: {doc-type}
    Spec name: {spec-name}
    Mode: fix

    Auto-fix の対象（ファイルを直接修正してよい）:
    - placeholder テキストの削除（[describe...], TODO, TBD）
    - マークダウンフォーマットの修正（テーブル整形、見出しレベル等）
    - 明らかな typo

    Auto-fix の対象外（issues として報告のみ）:
    - セクションの追加・削除
    - 内容の追加・変更（要件、設計コンポーネント、エラーコード等）
    - トレーサビリティの不整合

    Return a structured report with auto-fixed items and remaining issues.`
})
```

## Review Checklist by Document Type

### Requirements (`requirements.md`)

**Template compliance:**
- Introduction section with clear feature overview
- Alignment with Product Vision section (references steering docs if they exist)
- Every requirement has User Story: "As a [role], I want [feature], so that [benefit]"
- Every requirement has Acceptance Criteria using EARS pattern (WHEN/IF...THEN...SHALL)
- Non-Functional Requirements: Code Architecture, Performance, Security, Reliability, Usability

**Quality:**
- No placeholder text (`[describe...]`, `TODO`, `TBD`)
- Acceptance criteria are testable and specific
- Requirements are uniquely identified (REQ-1, REQ-2, etc.)

### Design (`design.md`)

**Template compliance:**
- Overview with architectural description
- Steering Document Alignment (tech.md, structure.md)
- Code Reuse Analysis（下記の専用チェック参照）
- Architecture section with diagram
- Components/Interfaces: Purpose, Interfaces, Dependencies, Reuses
- Data Models with concrete field definitions
- Error Handling with specific scenarios
- Requirements Traceability Matrix（下記の専用チェック参照）

**Code Reuse Analysis（具体パス必須）:**
- テーブル形式で「再利用対象 / パス / 用途」が記載されているか
- パスが具体的なファイルパス（`src/middleware/auth.rs` 等）であり、抽象的な記述（「既存ミドルウェアを活用」等）でないか
- パスが実在するか（コードベースに存在するファイルか）
- Phase 3 で各タスクの `_Leverage` にそのまま転記できる粒度か

**Requirements Traceability Matrix:**
- 全要件 ID（REQ-1, REQ-2, ...）がマトリクスに含まれているか
- 各要件に対応する設計コンポーネントが明記されているか
- 逆方向: 設計コンポーネントに対応する要件がないもの（要件なき設計）がないか
- Testing Strategy: Unit, Integration, E2E

**Cross-reference (read requirements.md):**
- Every requirement has a corresponding design solution
- No design component without a backing requirement
- Data models cover all entities from requirements

**DB Schema review（設計承認後の変更を防ぐため厳密に検証）:**
- 全テーブルにカラム名・型・制約（NOT NULL, UNIQUE, DEFAULT 等）が明記されている
- 主キー・外部キー・インデックスが定義されている
- **FK ごとに `ON DELETE` 動作（CASCADE / RESTRICT / SET NULL）が明記されている**（未指定は不可。ビジネスロジックに直結する設計判断のため必ず明示すること）
- テーブル間のリレーション（1:1, 1:N, N:M）とカーディナリティが明確
- マイグレーション戦略（カラム追加/削除の順序、データ移行の有無）が記載されている
- 正規化レベルが適切（不要な冗長性がないか、パフォーマンスのための非正規化は根拠があるか）
- **NULL 許容カラムの意味が明確**（なぜ NULL を許容するか、DEFAULT 値がある場合はその意味を記載）
- タイムスタンプカラム（created_at, updated_at）の有無
- ソフトデリート vs ハードデリートの方針が明記されている（該当する場合）

**API Design review（設計承認後の変更を防ぐため厳密に検証）:**
- 全エンドポイントの HTTP メソッド、パス、説明が一覧化されている
- 各エンドポイントのリクエストボディ/クエリパラメータの型・必須/任意・バリデーションルールが定義されている
- 各エンドポイントのレスポンス型（成功時 + エラー時）と HTTP ステータスコードが定義されている
- エラーレスポンスのフォーマットが統一されている（例: `{ "error": { "code": "...", "message": "..." } }`）
- **エラーコード一覧がテーブル形式で定義されている**（エラーコード名、HTTP Status、発生条件の3列）。実装時に一覧にないエラーコードの追加を防ぐため網羅的に列挙されていること
- 認証・認可の要否がエンドポイントごとに明記されている
- ページネーション・フィルタリング・ソートのパラメータ設計（該当する場合）
- RESTful 規約の準拠（リソース名の複数形、適切な HTTP メソッドの使用）

**Data Model review（設計承認後の変更を防ぐため厳密に検証）:**
- DB Model（Queryable 等）と DTO（リクエスト/レスポンス型）が分離して定義されている
- DTO のフィールドが API Design のリクエスト/レスポンス定義と一致している
- Model → DTO の変換で公開すべきでないフィールド（password_hash 等）が除外されている
- バリデーションルールがリクエスト DTO に定義されている
- 列挙型（ステータス、ロール等）の値が網羅されている

**Quality:**
- No placeholder text
- Consistent component naming
- Error scenarios cover realistic failure modes
- DB Schema / API / Data Model が十分な具体性を持ち、実装者が設計を解釈する余地が最小限であること

### Tasks (`tasks.md`)

**Template compliance:**
- Every task has `- [ ]` checkbox marker
- Every task specifies target file path(s)
- Every task has `_Leverage` field
- Every task has `_Requirements` field
- Every task has `_Prompt` field with: Role, Task, Restrictions, Success
- `_Prompt` starts with "Implement the task for spec {spec-name}, first run spec-workflow-guide..."
- Tasks are atomic (1-3 files each)

**Cross-reference (read requirements.md and design.md):**
- Every requirement has at least one implementing task
- Every design component has at least one creating task
- `_Requirements` IDs match actual requirement IDs
- `_Leverage` paths are plausible（design.md の Code Reuse Analysis テーブルのパスと一致しているか）
- Task ordering respects dependencies (interfaces before implementations, models before services)

**Traceability Matrix 逆記入の検証（design.md を Read）:**
- design.md の Requirements Traceability Matrix の「対象タスク ID」列が全行埋まっているか
- 「対象タスク ID」が tasks.md に実在するタスク ID と一致しているか
- 空欄のコンポーネント行がある場合は tasks.md にタスク追加 + マトリクス更新が必要

**_TDDSkip と Interface-only task の検証:**
- `_TDDSkip: true` のタスクが適切か（テスト不可能なタスクにのみ付与されているか）
  - OK: プロジェクト初期化、Dockerfile、マイグレーション、設定ファイル（単独で完結するタスク）
  - NG: trait/struct 定義のみのタスク（単独で完結しない → 実装タスクにマージすべき）
- Interface-only task（`_TestFocus` 全カテゴリ「該当なし」＋ Success が「コンパイルが通る」のみ＋ `_TDDSkip` なし）を検出した場合:
  - `_TDDSkip: true` を付与するか、最初に `_Leverage` で参照するタスクにマージする
  - 判定基準: 「そのタスク単独で完結するか」→ Yes なら `_TDDSkip`、No ならマージ

**_TestFocus フォーマット検証:**
- 全非PhaseReview タスクの `_TestFocus` が4カテゴリ構造（正常系 / 境界値 / 例外処理 / エッジケース）で記述されているか
- 自由記述（"CRUD success/failure, validation boundaries" 等）になっていないか
- 該当しないカテゴリが「該当なし」と明記されているか（省略されていないか）
- 各カテゴリの内容が具体的か（「正常系: 成功パス」のような抽象記述ではなく、「正常系: 全 CRUD 操作の成功パス」のように対象を特定しているか）

**単一責務の検証:**
- `_Prompt` の Task フィールドが "and" で複数の動作を繋いでいないか
- Task を1文で説明できるか（複数文が必要 → 分割を検討）
- Success 基準が独立した複数の条件を含んでいないか（「A compiles and B validates and C works」→ 3タスクに分割）
- 分割が必要なタスクを検出した場合は分割して tasks.md を修正する

**Quality:**
- No placeholder text
- Task descriptions specific enough for AI agent implementation
- No duplicate tasks

## Output Format

### check モード

```
## Spec Review: {spec-name}/{doc-type}.md (check)

### Checks Performed
- Template compliance: {PASS / N issues}
- Cross-references: {PASS / N issues / N/A for requirements}
- Quality: {PASS / N issues}

### Issues (呼び出し元が修正すること)
1. [category: Template/CrossRef/Quality] {問題の説明} — location: {セクション名 or 行番号} — suggested fix: {具体的な修正案}
2. ...

### Items for User Attention
- [any gaps requiring human judgment, if any]

### Result: {PASS (issues 0) / FAIL (issues N件)}
```

### fix モード

```
## Spec Review: {spec-name}/{doc-type}.md (fix)

### Auto-Fixed
- [list of auto-fixed items with before/after]

### Remaining Issues (呼び出し元が修正すること)
1. [category] {問題の説明} — location: {セクション名} — suggested fix: {修正案}
2. ...

### Result: {PASS (remaining 0) / FAIL (remaining N件)}
```
