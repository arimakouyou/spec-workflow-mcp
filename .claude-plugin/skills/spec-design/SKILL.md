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
6. **Phase Deliverables**（K-4 で必須化） — 各 Phase で「**何を作るか** + **どの Test Layer で検証するか** + **smokeable な成果物**」を一元宣言。Wave 1 で Phase の境界と検証戦略を確定する。Phase ごとに「Deliverable / Test Layers / Smokeable」の 3 項目を記載

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

> ⛔ **MUST: ユーザー確認は必須**（A 起点、dapper-hardening）
>
> Wave 1 → Wave 2 の遷移は、user reply `continue` でのみ許可される。**「Auto Mode のため省略」「継続モード」など、本仕様に存在しない概念を発明してユーザー確認をスキップしてはならない**。
>
> 過去事例（dojin-viewer）: Claude が「Auto Mode」を発明して Wave 1 完了後にユーザー確認なしで Wave 2 へ進み、ユーザーから「指示を出したつもりはないが、これは想定した動作か？」と指摘された。これは本 SKILL.md の仕様ではない（hallucination）。
>
> `auto-resume.sh` はレートリミット復旧専用であり、ユーザー意思確認の代替ではない。Wave/Phase 進行の前は **明示的な user reply を必ず受信する**。

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
- **Test Layers:** [UT / CT / IT-N / ST-N の組合せで宣言（K-2 必須）。詳細は quality-checks.md Test Taxonomy 参照]
```

**Test Layers field（K-2 で必須化、`dapper-hardening-orchestrator.md` 参照）:**

各 DES-N に対して、その component が **どの test 層で検証されるか** を明示宣言する:

- UI component: `Test Layers: UT (extracted helpers), CT (mount + signal + DOM)`
- Backend service: `Test Layers: UT, IT-N (HTTP)`
- Library / utility: `Test Layers: UT`
- 統合 component (機能の縦切り): `Test Layers: UT, CT, ST-N`

具体 ID（`IT-19` 等）は test-design.md で確定後に back-fill 可。spec-design 段階では layer 名のみでも可（例: `Test Layers: UT, IT`）。`spec-test-design` の Subagent はこの宣言を最優先で derivation の入力とし、heuristic に基づく自動判定を排除する（K-7）。

Data Models should use `### MOD-N: ModelName` and API sections (if present) should use `### API-N: EndpointName`.

#### Data Models

Describe all entities in type definition or schema format.

> **バリデーションガイダンス**: リクエスト DTO は `#[serde(deny_unknown_fields)]` を付与し、未知フィールドを拒否すること（`api-validation` Skill AV-R1 参照）。各フィールドの必須/任意（`Option<T>`）、文字列長制限、Enum 許容値を設計段階で定義しておくこと。

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

#### Architecture for Testability（K-3 必須）

> 出典: `.claude/_docs/plans/dapper-hardening-orchestrator.md` 根本原因 K（K-3）。
> I (UT Properties Gate, QC15) で禁止される clock / RNG / env / fs / HTTP / DB の直接呼出について、**ここで宣言された Mock 経由のみ許可** されるという design ↔ enforcement の往復ループを成立させる。

`## Architecture for Testability` セクションを必須記載とし、以下 5 サブセクションを揃える:

```markdown
## Architecture for Testability

### Mock points
[trait 境界 / DI 注入点 / port-adapter 構造の設計図。例: `trait UserRepository` を `services/` から DI 注入、テスト時は `MockUserRepository` を bind]

### Clock injection
[`trait Clock` + `MockClock` の使用方針 / WASM target での `js-sys::Date` 取扱い]

### RNG injection
[`trait Rng` + `MockRng` の使用方針]

### External I/O isolation
[HTTP (mockito / wiremock) / fs (tempfile) / env (`dotenvy::from_path_override`) などで隔離する設計]

### Test fixtures
[共通 fixture の配置 / lifetime / clean-up 方針。docker-compose.test.yml と testcontainers の使い分けなど]
```

5 サブセクションがすべて揃っていない場合は spec-design Step B (Check) で error 判定（K-6）。

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
    3. Must include: Overview, Architecture diagram, Component details (Purpose/Interfaces/Dependencies/Reuses/Test Layers),
       Data Models, Error Handling table, Requirements Traceability Matrix, Code Reuse Analysis with concrete paths,
       Required Build Tools table, Excluded Test Environments section, Phase Deliverables section, Architecture for Testability section
    4. Data models must cover all entities referenced in requirements
    5. Error Handling must have a complete table (not just scenario descriptions)
    6. Required Build Tools section must exist with at least one tool entry in table format (Tool, Min Version, Purpose, Check Command, Install Command, Required columns)
    7. Excluded Test Environments section must exist (table may be empty if no exclusions, but section must be present)
    8. FRONTMATTER (spec-dependency-graph.md SD2): Valid YAML frontmatter with spec_id, phase: design, version, depends_on (file: requirements.md, refs: [REQ-...]) must exist at the top of the file
    9. IDENTIFIERS (spec-dependency-graph.md SD1): Components and Interfaces use '### DES-N: Name' headings, Data Models use '### MOD-N: Name', API sections use '### API-N: Name'. depends_on.refs must point to REQ-N (or REQ-N.M) that exist in requirements.md
    10. TEST LAYERS PER DES (K-2, dapper-hardening): Every '### DES-N:' must declare a 'Test Layers:' field with values from quality-checks.md Test Taxonomy (UT/CT/IT/IT-N/ST/ST-N/E2E/E2E-N の組合せ)
    11. ARCHITECTURE FOR TESTABILITY (K-3): A '## Architecture for Testability' section must exist and contain all 5 sub-sections: Mock points, Clock injection, RNG injection, External I/O isolation, Test fixtures
    12. PHASE DELIVERABLES (K-4): A '## Phase Deliverables' section must exist with at least one '### Phase N:' heading, each declaring Deliverable / Test Layers / Smokeable
    13. TYPE_REFERENCE_RESOLUTION (C-1, dapper-hardening): Every custom type referenced in DES-N の `Interfaces:` field signatures (e.g., `Result<X, E>`, `Vec<T>`, `Signal<T>`, `Callback<T>` の inner types) must be defined in either:
        (a) `### MOD-N:` heading in the same design.md, or
        (b) Standard library types (std::*, core::*, alloc::*) or known framework types (Leptos / Axum / .NET CLR / Node.js built-ins)
        Undefined custom types → error: `undefined_type_reference`. Examples of failures: design.md interface uses `RelativePath` but no `### MOD-N: RelativePath` heading exists.

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 7. Approval Workflow

Formal approval — verbal approval is not accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only (do not include content). Save the returned `approvalId`.

2. **Check approval (synchronous)**: After the user approves via the dashboard / VS Code extension, run:
   ```
   /check-approval <approvalId> next:/spec-test-design
   ```
   `check-approval` fetches status once via the `approvals` MCP tool (no polling) and branches:
   - **pending**: User has not acted yet — instruct the user to approve, then re-run `/check-approval`
   - **approved**: Cleanup is performed automatically, and `check-approval` automatically invokes `/spec-test-design`
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval

3. **Handle needs-revision** (if status was needs-revision):
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
