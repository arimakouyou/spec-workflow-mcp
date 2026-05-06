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

### Steering Documents Check (Recommended)

Check whether the following steering docs exist. If they do not, recommend that the user run `/steering-doc` (do not block):

| File | Purpose | Required Level |
|------|---------|----------------|
| `.spec-workflow/steering/structure.md` | Architecture overview (module composition, request flow) | Strongly recommended |
| `.spec-workflow/steering/tech.md` | Tech stack, environment variables, build tools | Recommended |
| `.spec-workflow/steering/product.md` | Product direction, user stories | Optional |

> **P1-01 response**: When the architecture overview (`structure.md`) exists, agents can grasp the codebase as a whole. If not yet created, generate it with `/steering-doc`.

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
6. **Phase Deliverables** (made mandatory by K-4) — For each Phase, declare in one place: **what to build** + **which Test Layer verifies it** + **smokeable deliverable**. Wave 1 finalizes Phase boundaries and the verification strategy. Each Phase lists the three items: Deliverable / Test Layers / Smokeable

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

After writing Key Design Decisions, verify that every library and framework version listed is the latest stable release. Versions based on AI training data may be outdated.

#### 3.5.1 Extract Version Information

Collect every technology + version pair from the Key Design Decisions section (e.g., "Leptos 0.7", "Diesel 2.2", "Axum 0.8").

#### 3.5.2 Confirm Latest Stable Versions

For each collected library, confirm the latest stable version using the following priority order:

1. **WebSearch** (recommended):
   - Search: "{library name} latest stable release"
   - Search: "{library name} crates.io" (Rust) / "{package name} npm" (Node.js)

2. **context7 MCP** (supplementary):
   - Identify the library via resolve-library-id
   - Confirm the latest version or changelog via query-docs

3. **Registry CLI fallback** (when web tools are unavailable, crates.io / npm packages only):
   ```bash
   # Node.js
   npm view {package_name} version
   # Rust (verify exact crate name match)
   cargo search {crate_name} --limit 1 | grep "^{crate_name} ="
   ```
   For tools outside crates.io / npm (docker, chromium, etc.), confirm via WebSearch on the official release page.

#### 3.5.3 Version Update

Summarize verification results in a table and update Key Design Decisions:

| Library | Design Version | Latest Stable | Action |
|---------|---------------|---------------|--------|
| {name} | {old} | {new} | Updated / Kept (reason) |

- Update the Key Design Decisions versions to the latest stable releases
- **Exception**: If a steering document (e.g., tech.md) pins a specific version for compatibility, keep it and note the reason
- **Major version change**: If the design version and latest version differ in major version, report this to the user during Architecture Confirmation (step 4)

### 3.6 Generate ADRs from Key Design Decisions

Auto-generate an ADR (Architecture Decision Record) from each decision in the Key Design Decisions section.

1. Check whether the `.claude/_docs/adr/` directory exists. Create it if not
2. For each Key Design Decisions item:
   - Extract the technology, pattern, or approach that was "chosen over alternatives" as an ADR candidate
   - Check INDEX.md to ensure no duplication with existing ADRs
3. For each candidate, create an ADR file following the `/adr` skill procedure:
   - `status: Accepted` (the design approval process also serves as decision approval)
   - **Context**: Context of the corresponding Key Design Decision in design.md
   - **Decision**: The chosen technology / pattern
   - **Alternatives Considered**: Alternatives considered and reasons for rejection (copy from Key Design Decisions if present)
   - **Consequences**: Impact on the design
4. Update INDEX.md

**ADR generation criteria** — Create an ADR only for decisions that match the following:
- Choice of framework, language, or database (e.g., Axum, PostgreSQL, Leptos)
- Choice of architecture pattern (e.g., layered architecture, event-driven)
- Decisions involving significant trade-offs (e.g., performance vs maintainability)

**Decisions not requiring an ADR** — Do not create ADRs for:
- Library version selection (versions are managed in Key Design Decisions)
- Choices with no alternative under industry standards


### 4. Architecture Confirmation (Present to User)

> ⛔ **MUST: User confirmation is required** (A origin, dapper-hardening)
>
> The Wave 1 → Wave 2 transition is only allowed on user reply `continue`. **Do not skip user confirmation by inventing concepts that do not exist in this spec, such as "skipped due to Auto Mode" or "continuation mode."**
>
> Past incident (dojin-viewer): Claude invented "Auto Mode" and proceeded to Wave 2 after Wave 1 without user confirmation. The user pointed out, "I didn't issue an instruction; is this the intended behavior?" This is not part of this SKILL.md spec (hallucination).
>
> `auto-resume.sh` is for rate-limit recovery only; it is not a substitute for user intent confirmation. Before any Wave/Phase progression, **always receive an explicit user reply**.

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
- **Test Layers:** [Declare as a combination of UT / CT / IT-N / ST-N (mandatory under K-2). See quality-checks.md Test Taxonomy for details]
```

**Test Layers field (made mandatory by K-2; see `dapper-hardening-orchestrator.md`):**

For each DES-N, explicitly declare **which test layers verify the component**:

- UI component: `Test Layers: UT (extracted helpers), CT (mount + signal + DOM)`
- Backend service: `Test Layers: UT, IT-N (HTTP)`
- Library / utility: `Test Layers: UT`
- Integrated component (vertical slice of a feature): `Test Layers: UT, CT, ST-N`

Concrete IDs (e.g., `IT-19`) may be back-filled after they are finalized in test-design.md. At the spec-design stage, layer names alone are acceptable (e.g., `Test Layers: UT, IT`). The `spec-test-design` Subagent uses this declaration as the highest-priority input for derivation, eliminating heuristic-based automatic decisions (K-7).

Data Models should use `### MOD-N: ModelName` and API sections (if present) should use `### API-N: EndpointName`.

#### Data Models

Describe all entities in type definition or schema format.

> **Validation guidance**: Annotate request DTOs with `#[serde(deny_unknown_fields)]` to reject unknown fields (see `api-validation` Skill AV-R1). Define each field's required/optional status (`Option<T>`), string length limits, and allowed Enum values at design time.

#### API Design (if applicable)

For each endpoint, describe:
- HTTP method, path, and description
- Request / response types (fields, types, required / optional)
- Error responses

> **OpenAPI generation guidance**: For OpenAPI schema auto-generation (`/generate-api-docs`), describe each field of request/response types with field-level doc comments. Defining descriptions at design time keeps implementation-time doc comments consistent with the OpenAPI `description` field.
>
> Example:
> ```rust
> struct UserResponse {
>     /// Unique identifier of the user
>     id: Uuid,
>     /// Display username (2-50 characters)
>     display_name: String,
>     /// Account creation time (UTC)
>     created_at: DateTime<Utc>,
> }
> ```

#### Architecture for Testability (K-3 required)

> Source: `.claude/_docs/plans/dapper-hardening-orchestrator.md` root cause K (K-3).
> Establishes the design ↔ enforcement round-trip loop in which the direct calls to clock / RNG / env / fs / HTTP / DB prohibited by I (UT Properties Gate, QC15) are **only permitted via the Mocks declared here**.

The `## Architecture for Testability` section is mandatory and must contain the following 5 sub-sections:

```markdown
## Architecture for Testability

### Mock points
[Design map for trait boundaries / DI injection points / port-adapter structure. Example: inject `trait UserRepository` from `services/` via DI; bind `MockUserRepository` for tests]

### Clock injection
[Usage policy for `trait Clock` + `MockClock` / handling of `js-sys::Date` on WASM targets]

### RNG injection
[Usage policy for `trait Rng` + `MockRng`]

### External I/O isolation
[Isolation design via HTTP (mockito / wiremock) / fs (tempfile) / env (`dotenvy::from_path_override`), etc.]

### Test fixtures
[Layout / lifetime / cleanup policy for shared fixtures. When to use docker-compose.test.yml vs testcontainers, etc.]
```

If all 5 sub-sections are not present, spec-design Step B (Check) flags an error (K-6).

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

Define the project's layer structure and dependency direction rules. Used by `/generate-arch-tests` to auto-generate architecture invariant tests.

> **Architecture test linkage**: Writing this section enables you to run `/generate-arch-tests` after the implementation phase to mechanically detect inter-layer dependency direction violations.

> **P5-06**: Always fill in the shared-type definitions table in the Module Boundaries section.
> Explicitly stating where shared types live and how they are managed prevents duplicate type definitions across modules.

```markdown
## Module Boundaries

### Layer Definitions

| Layer | Directory | Description |
|-------|-----------|-------------|
| handlers | src/handlers/ | HTTP handler layer (topmost) |
| services | src/services/ | Business logic layer (middle) |
| infra | src/infra/ | Infrastructure layer (lowest, cross-cutting concerns) |

### Dependency Direction Rules

| From (dependent) | Allowed Dependencies | Forbidden |
|------------------|---------------------|-----------|
| handlers | services, infra | — |
| services | infra | handlers |
| infra | — | handlers, services |
```

Authoring rules:
1. `Layer` names must match the module name (directory name) in source code
2. `Directory` is written as a relative path from `src/`
3. Only **higher → lower** dependency direction is allowed. Explicitly mark the reverse (lower → higher) as `Forbidden`
4. Place cross-cutting concerns (error, config, etc.) in the lowest layer and allow references from all layers
5. If there are no layer definitions (small projects, etc.), the section itself may be omitted

#### Required Build Tools

Based on the Key Design Decisions from Wave 1, list all CLI tools needed to build, test, and run the project. Use the latest stable version verified in step 3.5 as the `Min Version`. Each tool's `--version` command is used to detect the installed version (for comparison with Min Version) — it is not the basis for Min Version. Do NOT copy example versions from this skill file or the template — the examples below are format references only.

```markdown
## Required Build Tools

| Tool | Min Version | Purpose | Check Command | Install Command | Required |
|------|-------------|---------|---------------|-----------------|----------|
| cargo | >= 1.93 | Rust build system | cargo --version | rustup update | Yes |
| docker | >= 29.0 | Container runtime | docker --version | apt install docker.io | Yes |
```

Derivation rules:
1. Key Design Decisions tech choices → corresponding build tools (Rust → cargo, Node.js → node+npm, etc.)
2. Container Architecture → docker / podman
3. Testing Strategy overview → tools needed for build and basic tests (E2E browser test tools such as playwright/chromium go in test-design.md's Required Test Tools)
4. Check Command is a single command that exits 0 if the tool is installed
5. Required column: only `Yes` (required) or `Recommended` (recommended). Tools required for E2E tests (Playwright, Chrome, etc.) must be listed as Required=Yes at design time
6. Min Version must reflect the latest stable verified in step 3.5. Do not use default values from AI training data
7. Container Architecture Base Image tags (e.g., `rust:X.YZ-slim`) must match the Required Build Tools Min Version. Mismatches FAIL Wave 2 Self-Review

#### Excluded Test Environments

When tests can only run in a specific environment (e.g., depending on specialized hardware), document the exclusion reason and an alternative verification method.

```markdown
## Excluded Test Environments

| Test Category | Excluded Tests | Reason | Alternative Verification |
|--------------|---------------|--------|------------------------|
| E2E | E2E-3 (iOS Safari verification) | No iOS device in CI | Manual verification on BrowserStack |
```

**Important**: Any test not explicitly excluded at design time is required to run in the implementation phase. Missing Docker / Chrome / server / DB, etc., is not a valid exclusion reason (handle these in Required Tools of design.md / test-design.md). When there are no excluded tests, leave the table empty (but keep the section).

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
    10. TEST LAYERS PER DES (K-2, dapper-hardening): Every '### DES-N:' must declare a 'Test Layers:' field with values from quality-checks.md Test Taxonomy (combinations of UT/CT/IT/IT-N/ST/ST-N/E2E/E2E-N)
    11. ARCHITECTURE FOR TESTABILITY (K-3): A '## Architecture for Testability' section must exist and contain all 5 sub-sections: Mock points, Clock injection, RNG injection, External I/O isolation, Test fixtures
    12. PHASE DELIVERABLES (K-4): A '## Phase Deliverables' section must exist with at least one '### Phase N:' heading, each declaring Deliverable / Test Layers / Smokeable
    13. TYPE_REFERENCE_RESOLUTION (C-1, dapper-hardening): Every custom type referenced in the `Interfaces:` field signatures of DES-N (e.g., the inner types of `Result<X, E>`, `Vec<T>`, `Signal<T>`, `Callback<T>`) must be defined in either:
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
