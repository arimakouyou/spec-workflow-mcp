---
name: spec-design
description: "Phase 2 of spec-driven development: create a technical design document for a feature. Use this skill after requirements are approved, when the user wants to create a design doc, define architecture, or plan how to build a feature. Triggers on: 'create design', 'design document', 'technical architecture for X', 'how should we build X', or any request to create a design.md document."
---

# Spec Design (Phase 2)

Create a technical design document that defines **how** to build the feature. This phase follows approved requirements and precedes task breakdown.

The design document is created in **two stages (Waves)**. Wave 1 aligns the architectural direction with the user before Wave 2 fills in the details, preventing rework caused by misaligned direction.

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify the prerequisite files exist:

1. Check `.spec-workflow/specs/{spec-name}/request-spec.md` exists
2. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists

**Legacy workflow exception**: If `request-spec.md` does not exist but `requirements.md` already exists, this is a legacy spec created before Phase 0. Skip the `request-spec.md` check and proceed normally.

If `requirements.md` is missing — **STOP immediately.** Inform the user: "requirements.md does not exist; cannot begin design. Please run `/spec-requirements` first." Then exit this skill.

| Missing File | Required Skill | Skip if legacy? |
|-------------|---------------|-----------------|
| request-spec.md | `/spec-request-spec` | Yes (if requirements.md exists) |
| requirements.md | `/spec-requirements` | No |

---

Requirements must be approved and cleaned up (Phase 1 complete). If not, use `/spec-requirements` first.

### Steering Documents Check (推奨)

以下の steering doc が存在するか確認する。存在しない場合はユーザーに `/steering-doc` の実行を推奨する（ブロックはしない）:

| ファイル | 目的 | 必須度 |
|---------|------|--------|
| `.spec-workflow/steering/structure.md` | アーキテクチャ概要（モジュール構成・リクエストフロー） | 強く推奨 |
| `.spec-workflow/steering/tech.md` | 技術スタック・環境変数・ビルドツール | 推奨 |
| `.spec-workflow/steering/product.md` | プロダクト方針・ユーザーストーリー | 任意 |

> **P1-01 対応**: アーキテクチャ概要（`structure.md`）が存在することで、エージェントがコードベース全体像を把握できる。未作成の場合は `/steering-doc` で生成すること。

## Inputs

The same **spec name** used in Phase 1 (kebab-case, e.g., `user-authentication`).

## Process

### 1. Load Resources

**Template** — prefer custom, fall back to default:
1. `.spec-workflow/user-templates/design-template.md` (custom)
2. `.spec-workflow/templates/design-template.md` (default)

**Steering documents** — load if they exist:
```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

### 2. Analyze and Research

- Read the approved request spec: `.spec-workflow/specs/{spec-name}/request-spec.md`
- Read the approved requirements: `.spec-workflow/specs/{spec-name}/requirements.md`
- Explore the codebase to understand existing patterns and reusable components
- If web search is available, research best practices for technology choices
- Confirm that design solutions exist for all requirements

---

## Wave 1: Architecture Skeleton

**Goal**: Align the architectural direction with the user before diving into details.

### 3. Create Wave 1 Document

Write only the sections listed below and create `.spec-workflow/specs/{spec-name}/design.md`.
Leave the detail sections (API spec, error handling, traceability, etc.) as `(to be written in Wave 2)` placeholders.

**Frontmatter (required for new specs, per `.claude-plugin/rules/spec-dependency-graph.md` SD2-SD3):**

Include the following YAML frontmatter at the top of the file. Populate `depends_on.refs` with the `REQ-N` IDs from requirements.md that this design implements:

```yaml
---
spec_id: {spec-name}
phase: design
version: 1
depends_on:
  - file: requirements.md
    refs: [REQ-1, REQ-2]  # REQ-N (whole requirement) or REQ-N.M (specific Acceptance Criterion)
---
```

**Sections to write in Wave 1:**

1. **Overview** — Summary of the feature and its place in the system
2. **Architecture** — Architecture diagram (mermaid) + rationale for the chosen pattern
3. **Component List** — Component names with a one-line description of each role only (details in Wave 2)
4. **DB Schema** — Table definitions, columns, and constraints (critical decisions that form the implementation foundation)
5. **Key Design Decisions** — Technologies and patterns chosen and why (include rejected alternatives)

**Wave 1 placeholder examples:**
```markdown
## Components and Interfaces
(to be written in Wave 2)

## Data Models
(to be written in Wave 2)

## API Design
(to be written in Wave 2)

## Error Handling
(to be written in Wave 2)

## Requirements Traceability Matrix
(to be written in Wave 2)

## Code Reuse Analysis
(to be written in Wave 2)

## Required Build Tools
(to be written in Wave 2)

## Excluded Test Environments
(to be written in Wave 2)
```

### 3.5 Version Freshness Verification (MANDATORY)

Key Design Decisions の記述後、記載した全てのライブラリ・フレームワークのバージョンが最新安定版であることを検証する。AI の学習データに基づくバージョンは古い可能性がある。

#### 3.5.1 バージョン情報の抽出

Key Design Decisions セクションから技術名＋バージョンのペアを全て収集する（例: 「Leptos 0.7」「Diesel 2.2」「Axum 0.8」）。

#### 3.5.2 最新安定版の確認

収集した各ライブラリについて、以下の優先順で最新安定版を確認する:

1. **WebSearch**（推奨）:
   - 検索: "{ライブラリ名} latest stable release"
   - 検索: "{ライブラリ名} crates.io"（Rust）/ "{パッケージ名} npm"（Node.js）

2. **context7 MCP**（補助）:
   - resolve-library-id でライブラリを特定
   - query-docs で最新バージョンやチェンジログを確認

3. **レジストリ CLI フォールバック**（Web ツール利用不可時、crates.io / npm パッケージのみ）:
   ```bash
   # Node.js
   npm view {package_name} version
   # Rust（crate 名の完全一致を確認すること）
   cargo search {crate_name} --limit 1 | grep "^{crate_name} ="
   ```
   crates.io / npm 以外のツール（docker, chromium 等）は WebSearch で公式リリースページを確認する。

#### 3.5.3 バージョン更新

検証結果をテーブルにまとめ、Key Design Decisions を更新する:

| Library | Design Version | Latest Stable | Action |
|---------|---------------|---------------|--------|
| {name} | {old} | {new} | Updated / Kept (理由) |

- Key Design Decisions のバージョンを最新安定版に更新
- **例外**: steering ドキュメント（tech.md 等）が互換性のため特定バージョンを指定している場合は維持し理由を注記
- **メジャーバージョン変更**: 設計版と最新版のメジャーバージョンが異なる場合、Architecture Confirmation (step 4) でユーザーに報告

### 3.6 Generate ADRs from Key Design Decisions

Key Design Decisions セクションの各決定事項から ADR (Architecture Decision Record) を自動生成する。

1. `.claude/_docs/adr/` ディレクトリが存在するか確認。なければ作成する
2. Key Design Decisions の各項目について:
   - 「代替案と比較して選択した」技術・パターン・アプローチを ADR 候補として抽出
   - 既存の ADR と重複しないか INDEX.md を確認
3. 各候補について `/adr` スキルの手順に従い ADR ファイルを作成:
   - `status: Accepted`（設計承認プロセスが意思決定承認を兼ねるため）
   - **Context**: design.md の該当 Key Design Decision のコンテキスト
   - **Decision**: 選択した技術・パターン
   - **Alternatives Considered**: 検討した代替案と棄却理由（Key Design Decisions に記載されていれば転記）
   - **Consequences**: 設計への影響
4. INDEX.md を更新

**ADR 生成の判断基準** — 以下に該当する決定のみ ADR を作成:
- フレームワーク・言語・データベースの選択（例: Axum, PostgreSQL, Leptos）
- アーキテクチャパターンの選択（例: レイヤードアーキテクチャ、イベント駆動）
- 重大なトレードオフを伴う決定（例: パフォーマンス vs 保守性）

**ADR 不要な決定** — 以下は ADR を作成しない:
- ライブラリのバージョン選択（バージョンは Key Design Decisions で管理）
- 業界標準で代替案のない選択


### 4. Architecture Confirmation (Present to User)

After creating the Wave 1 document, present the following to the user **without using the formal approval tool**:

```
## Architecture Confirmation

The Wave 1 skeleton is ready. Please review the direction below before proceeding to Wave 2 (detailed writing).

**Design Overview**
{2–3 sentence summary of the Overview}

**Chosen Architecture**
{Architecture diagram or configuration summary}

**Key Components**
{Component list}

**Main DB Schema Tables**
{Table list}

**Key Design Decisions**
{Summary of Key Design Decisions}

---
If the direction looks good, reply "continue". If changes are needed, please provide specific instructions.
```

Branch based on user feedback:

- **"continue" / approval**: Proceed to Wave 2
- **Revision instructions**: Update the Wave 1 sections in design.md and present the confirmation again. Once agreed, proceed to Wave 2

---

## Wave 2: Detailed Writing

**Goal**: Fill in all details based on the finalized architecture and obtain formal approval.

### 5. Complete Wave 2 Document

Fill in all sections left as `(to be written in Wave 2)` from Wave 1.

#### Components and Interfaces

Describe each component in this format. Use `### DES-N: ComponentName` headings (per `.claude-plugin/rules/spec-dependency-graph.md` SD1) so downstream specs can reference them:

```markdown
### DES-1: ComponentName
- **Purpose:** [Responsibility this component owns]
- **Interfaces:** [Public method / API signatures]
- **Dependencies:** [Components / external services depended on]
- **Reuses:** [Existing code to leverage (with concrete paths)]
- **Satisfies:** [REQ-N.M list that this component addresses]
```

Data Models should use `### MOD-N: ModelName` and API sections (if present) should use `### API-N: EndpointName`.

#### Data Models

Describe all entities in type definition or schema format.

> **バリデーションガイダンス**: リクエスト DTO は `#[serde(deny_unknown_fields)]` を付与し、未知フィールドを拒否すること（`api-validation.md` AV-R1 参照）。各フィールドの必須/任意（`Option<T>`）、文字列長制限、Enum 許容値を設計段階で定義しておくこと。

#### API Design (if applicable)

For each endpoint, describe:
- HTTP method, path, and description
- Request / response types (fields, types, required / optional)
- Error responses

> **OpenAPI 生成ガイダンス**: OpenAPI スキーマの自動生成（`/generate-api-docs`）のため、リクエスト/レスポンス型の各フィールドにはフィールドレベルの説明を doc comment で記述すること。設計段階で説明を定義しておくことで、実装時の doc comment と OpenAPI の `description` フィールドが一貫する。
>
> 記述例:
> ```rust
> struct UserResponse {
>     /// ユーザーの一意識別子
>     id: Uuid,
>     /// 表示用ユーザー名（2-50文字）
>     display_name: String,
>     /// アカウント作成日時（UTC）
>     created_at: DateTime<Utc>,
> }
> ```

#### Code Reuse Analysis Format

Search the codebase with grep/glob and list existing code to reuse with **concrete file paths**. Because these are copied into the `_Leverage` field in Phase 3, abstract descriptions (e.g., "use the existing auth middleware") are not acceptable.

```markdown
| Reuse Target | Path | Purpose |
|-------------|------|---------|
| Auth middleware | `src/middleware/auth.rs` | Protect endpoints |
| AppError | `src/error.rs` | Unified error responses |
| TestContext | `tests/integration/helpers/context.rs` | Test setup |
```

#### Requirements Traceability Matrix Format

Mapping of requirements to design components. **List one component per row** (do not join with `+`). The "Target Task ID" column is filled in retrospectively after Phase 3 (spec-tasks) is complete.

```markdown
| Requirement ID | Design Component | Target Task ID | Notes |
|---------------|-----------------|---------------|-------|
| REQ-1 | UserHandler | (fill in after Phase 3) | CRUD endpoints |
| REQ-1 | UserRepository | (fill in after Phase 3) | DB access |
| REQ-2 | AuthMiddleware | (fill in after Phase 3) | Auth check |
```

#### Error Handling Format

List all error codes in table format. Because the design-conformance rule prohibits adding error codes outside this list during implementation, define all anticipated error cases exhaustively.

```markdown
## Error Handling

Error response format: `{ "error": { "code": "...", "message": "..." } }`

| Error Code | HTTP Status | Trigger Condition |
|-----------|-------------|------------------|
| NotFound | 404 | Resource does not exist |
| BadRequest | 400 | Validation failure, invalid input |
| Unauthorized | 401 | Auth failure, invalid / expired token |
| Forbidden | 403 | Authorization failure, insufficient permissions |
| Conflict | 409 | Duplicate key, optimistic lock conflict |
| Internal | 500 | Unexpected internal error |
```

#### Module Boundaries

プロジェクトのレイヤー構造と依存方向ルールを定義する。`/generate-arch-tests` によるアーキテクチャ不変条件テストの自動生成に使用される。

> **アーキテクチャテスト連携**: このセクションを記述することで、実装フェーズ後に `/generate-arch-tests` を実行してレイヤー間の依存方向違反を機械的に検出できる。

> **P5-06**: Module Boundaries セクションの共有型定義テーブルを必ず埋めること。
> モジュール間で共有される型の配置先・管理方法を明示することで、型の重複定義を防ぐ。

```markdown
## Module Boundaries

### レイヤー定義

| Layer | Directory | Description |
|-------|-----------|-------------|
| handlers | src/handlers/ | HTTP ハンドラ層（最上位） |
| services | src/services/ | ビジネスロジック層（中間） |
| infra | src/infra/ | インフラ層（最下層・横断的関心事） |

### 依存方向ルール

| From (依存元) | Allowed Dependencies (許可) | Forbidden (禁止) |
|--------------|---------------------------|-----------------|
| handlers | services, infra | — |
| services | infra | handlers |
| infra | — | handlers, services |
```

記述ルール:
1. `Layer` 名はソースコード上のモジュール名（ディレクトリ名）と一致させる
2. `Directory` は `src/` からの相対パスで記述する
3. 依存方向は**上位 → 下位**のみ許可。逆方向（下位 → 上位）を `Forbidden` に明記する
4. 横断的関心事（error, config 等）は最下層に配置し、全レイヤーからの参照を許可する
5. レイヤー定義がない場合（小規模プロジェクト等）はセクション自体を省略してよい

#### Required Build Tools

Based on the Key Design Decisions from Wave 1, list all CLI tools needed to build, test, and run the project. `Min Version` は step 3.5 で検証した最新安定版を採用する。各ツールの `--version` コマンドはインストール済みバージョンの把握（Min Version との比較用）に使い、Min Version の根拠にはしない。Do NOT copy example versions from this skill file or the template — the examples below are format references only.

```markdown
## Required Build Tools

| Tool | Min Version | Purpose | Check Command | Install Command | Required |
|------|-------------|---------|---------------|-----------------|----------|
| cargo | >= 1.93 | Rust build system | cargo --version | rustup update | Yes |
| docker | >= 29.0 | Container runtime | docker --version | apt install docker.io | Yes |
```

導出ルール:
1. Key Design Decisions の技術選定 → 対応するビルドツール（Rust → cargo, Node.js → node+npm 等）
2. Container Architecture → docker / podman
3. Testing Strategy 概要 → ビルドや基本テストに必要なツール（E2E ブラウザテスト用の playwright/chromium 等は test-design.md の Required Test Tools に記載）
4. Check Command は、ツールがインストール済みなら exit 0 になる単一コマンド
5. Required 列: `Yes`（必須）または `Recommended`（推奨）のみ。E2E テストに必要なツール（Playwright, Chrome等）は設計時に Required=Yes として明記すること
6. Min Version は step 3.5 で検証した最新安定版を反映すること。AI の学習データのデフォルト値を使用しない
7. Container Architecture の Base Image タグ（例: `rust:X.YZ-slim`）は Required Build Tools の Min Version と一致させること。不一致は Wave 2 Self-Review で FAIL

#### Excluded Test Environments

特定環境でのみ実行可能なテスト（特殊ハードウェア依存等）がある場合に、除外理由と代替検証方法を明記する。

```markdown
## Excluded Test Environments

| Test Category | Excluded Tests | Reason | Alternative Verification |
|--------------|---------------|--------|------------------------|
| E2E | E2E-3 (iOS Safari 検証) | CI に iOS デバイスがない | BrowserStack で手動検証 |
```

**重要**: 設計時に明示的に除外宣言されていないテストは、すべて実装フェーズで実行必須。Docker/Chrome/サーバー起動/DB 等の不足は除外理由にならない（design.md/test-design.md の Required Tools で対応すべき）。除外テストがない場合はテーブルを空にする（セクション自体は残す）。

### 6. Self-Review via Subagent (before approval)

After Wave 2 is complete, review in **2 steps** before requesting formal approval.

#### Step A: fix (automated mechanical corrections)

Auto-fix placeholders, formatting, and typos. Do not add or change content:

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
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

#### Step B: check (content validation)

After fix is complete, detect content problems. Do not modify the file:

```
Agent({
  subagent_type: "general-purpose",
  model: "opus",
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
    8. FRONTMATTER (spec-dependency-graph.md SD2): Valid YAML frontmatter with spec_id, phase: design, version, depends_on (file: requirements.md, refs: [REQ-...]) must exist at the top of the file
    9. IDENTIFIERS (spec-dependency-graph.md SD1): Components and Interfaces use '### DES-N: Name' headings, Data Models use '### MOD-N: Name', API sections use '### API-N: Name'. depends_on.refs must point to REQ-N (or REQ-N.M) that exist in requirements.md
    10. EVIDENCE CITATIONS (evidence-coverage.md EC1): Read task_type from .spec-workflow/specs/{spec-name}/request-spec.md frontmatter.
        - If task_type is absent, 'legacy', or request-spec.md does not exist → SKIP checks 10-11 (EC5) and note 'evidence checks skipped (legacy)' in the report.
        - Otherwise, for every EV-{category}-{NNN} citation in this document (HTML comment, inline paren form, or frontmatter depends_on.refs):
            a. .spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md must exist.
            b. The referenced file's frontmatter spec_name: must equal this spec-name.
            c. The {category} must be listed in .claude-plugin/rules/task-types.md TT3 (or the project's user-config/task-types.yml TT4).
          Any failure = FAIL with rule_id EC1.
    11. INLINE CODE BUDGET (evidence-coverage.md EC3): Count fenced code block lines (between opening and closing fences, exclusive). Fail if any of:
            - A single fenced block exceeds 20 lines.
            - Cumulative fenced-block lines within a single H2 or H3 section exceed 40 lines.
            - Total fenced-block lines in the document exceed 200 lines.
          For each violation FAIL with rule_id EC3; fix_hint: 'Move the long excerpt to a new EV-{category}-{NNN}.md (pick the best-matching category from task-types.md TT3) and leave a brief summary + citation'. Markdown tables, block-quoted prose, ASCII architecture diagrams, and Mermaid diagrams are NOT counted.
    12. PER-COMPONENT EVIDENCE (evidence-coverage.md EC2, per DES/MOD): Each '### DES-N:' and '### MOD-N:' section must either (a) cite at least one EV-... inside that section, or (b) carry an HTML comment '<!-- no-evidence: {reason} -->' inside the section that explains why no existing-code anchor applies (reason must be non-empty). Missing both = FAIL rule_id EC2_perDES.
    13. CODE REUSE ANALYSIS EVIDENCE (evidence-coverage.md EC2): The 'Code Reuse Analysis' section must be driven by EV citations. Every concrete reused path, module, or utility mentioned in this section must be backed by an EV-... citation on the same line or in the adjacent bullet. Missing any = FAIL rule_id EC2_codeReuse; fix_hint: 'Back each reused path with an EV citation (typically EV-entry-points-* or EV-domain-models-*). If you still need to list the path without an existing EV, create one via targeted re-investigation.'

    Reporting: for EC1/EC2/EC3 issues, include fields rule_id, location, message, fix_hint.
    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 7. Approval Workflow

Formal approval — verbal approval is not accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only (do not include content). Save the returned `approvalId`.

2. **Automatic polling with auto-transition**: Start approval polling (Bash script with 60-minute timeout):
   ```
   /check-approval <approvalId> next:/spec-test-design
   ```
   The polling script will automatically check approval status and handle the result:
   - **approved**: Cleanup is performed automatically, and check-approval automatically invokes `/spec-test-design`
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval
   - **timeout**: Reported to user, can re-run to resume

3. **Handle needs-revision** (if polling ends with needs-revision):
   - Read the review comments, update the document, re-run the subagent review
   - Submit a NEW approval request and run `/check-approval <newApprovalId> next:/spec-test-design`

## Rules

- Feature names use kebab-case
- One spec at a time
- **Do not start Wave 2 before Wave 1 is complete** — user confirmation is required
- **Verbal confirmation is allowed for Wave 1** — formal approval tool not required
- **Formal approval is required after Wave 2** — verbal approval is not accepted
- Approval requests: filePath only, never content
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before moving to tasks
