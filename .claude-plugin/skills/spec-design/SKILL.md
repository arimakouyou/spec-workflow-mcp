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

Describe each component in this format:
```markdown
### ComponentName
- **Purpose:** [Responsibility this component owns]
- **Interfaces:** [Public method / API signatures]
- **Dependencies:** [Components / external services depended on]
- **Reuses:** [Existing code to leverage (with concrete paths)]
```

#### Data Models

Describe all entities in type definition or schema format.

#### API Design (if applicable)

For each endpoint, describe:
- HTTP method, path, and description
- Request / response types (fields, types, required / optional)
- Error responses

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

#### Required Build Tools

Based on the Key Design Decisions from Wave 1, list all CLI tools needed to build, test, and run the project. Search the codebase to detect current tool versions.

```markdown
## Required Build Tools

| Tool | Min Version | Purpose | Check Command | Install Command | Required |
|------|-------------|---------|---------------|-----------------|----------|
| cargo | >= 1.82 | Rust build system | cargo --version | rustup update | Yes |
| docker | >= 24.0 | Container runtime | docker --version | apt install docker.io | Yes |
```

導出ルール:
1. Key Design Decisions の技術選定 → 対応するビルドツール（Rust → cargo, Node.js → node+npm 等）
2. Container Architecture → docker / podman
3. Testing Strategy 概要 → E2E ブラウザテストの場合 playwright/chromium（Required=Yes）
4. Check Command は、ツールがインストール済みなら exit 0 になる単一コマンド
5. Required 列: `Yes`（必須）または `Recommended`（推奨）のみ。E2E テストに必要なツール（Playwright, Chrome等）は設計時に Required=Yes として明記すること

#### Excluded Test Environments

特定環境でのみ実行可能なテスト（特殊ハードウェア依存等）がある場合に、除外理由と代替検証方法を明記する。

```markdown
## Excluded Test Environments

| Test Category | Excluded Tests | Reason | Alternative Verification |
|--------------|---------------|--------|------------------------|
| E2E | E2E-3 (iOS Safari 検証) | CI に iOS デバイスがない | BrowserStack で手動検証 |
```

**重要**: 設計時に明示的に除外宣言されていないテストは、すべて実装フェーズで実行必須。Docker/Chrome/サーバー起動/DB 等の不足は除外理由にならない（Required Build Tools で対応すべき）。除外テストがない場合はテーブルを空にする（セクション自体は残す）。

### 6. Self-Review via Subagent (before approval)

After Wave 2 is complete, review in **2 steps** before requesting formal approval.

#### Step A: fix (automated mechanical corrections)

Auto-fix placeholders, formatting, and typos. Do not add or change content:

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

#### Step B: check (content validation)

After fix is complete, detect content problems. Do not modify the file:

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

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 7. Approval Workflow

Formal approval — verbal approval is not accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only (do not include content). Save the returned `approvalId`.

2. **Automatic polling**: Start automatic status checking:
   ```
   /loop 1m /check-approval <approvalId>
   ```
   The loop will automatically check approval status every minute and handle the result:
   - **pending**: Continue polling (no action needed)
   - **approved**: Cleanup is performed automatically, loop stops
   - **needs-revision**: Loop stops, reviewer comments are displayed

3. **Handle needs-revision** (if loop stopped with revision request):
   - Read the review comments, update the document, re-run the subagent review
   - Submit a NEW approval request and start a new `/loop 1m /check-approval <newApprovalId>`

4. **Next phase**: After approval and cleanup succeed, **automatically** proceed to Phase 3 (Test Design).
   Load the `/spec-test-design` skill and begin immediately — do not wait for user input.

## Rules

- Feature names use kebab-case
- One spec at a time
- **Do not start Wave 2 before Wave 1 is complete** — user confirmation is required
- **Verbal confirmation is allowed for Wave 1** — formal approval tool not required
- **Formal approval is required after Wave 2** — verbal approval is not accepted
- Approval requests: filePath only, never content
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before moving to tasks
