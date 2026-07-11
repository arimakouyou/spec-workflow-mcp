---
name: spec-test-design
description: "Phase 3 of spec-driven development: create a test design document that defines UT/IT/E2E test specifications. Use this skill after design is approved, when the user wants to define test strategy, test specifications, or plan testing before task breakdown. Triggers on: 'create test design', 'test specification', 'define test plan for X', 'test-design for X', or any request to create a test-design.md document."
---

# Spec Test Design (Phase 3)

Create a test design document that defines **how to test** the feature. This phase follows approved design and precedes task breakdown. The document defines concrete test cases at UT/IT/E2E levels, which subsequent phases reference for test implementation and verification.

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify all prerequisite files exist:

1. Check `.spec-workflow/specs/{spec-name}/request-spec.md` exists
2. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists
3. Check `.spec-workflow/specs/{spec-name}/design.md` exists

**Legacy workflow exception**: If `request-spec.md` does not exist but `requirements.md` already exists, this is a legacy spec created before Phase 0. Skip the `request-spec.md` check and proceed normally.

If `requirements.md` or `design.md` is missing — **STOP immediately.** Inform the user: "{filename} does not exist; cannot begin test design. Please run {skill-name} first." Then exit this skill.

| Missing File | Required Skill | Skip if legacy? |
|-------------|---------------|-----------------|
| request-spec.md | `/spec-request-spec` | Yes (if requirements.md exists) |
| requirements.md | `/spec-requirements` | No |
| design.md | `/spec-design` | No |

---

Design must be approved and cleaned up (Phases 1-2 complete). If not, use `/spec-design` first.

## Inputs

The same **spec name** used in previous phases (kebab-case, e.g., `user-authentication`).

## Process

### 1. Load Resources

**Template** — prefer custom, fall back to default; if neither exists, use the structure defined in this skill:
1. `.spec-workflow/user-templates/test-design-template.md` (custom)
2. `.spec-workflow/templates/test-design-template.md` (default; may not exist in all environments)
3. If both files are missing, do **not** fail; instead, construct `test-design.md` directly following the sections and guidance described below.

**Steering documents** — load if they exist:
```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

### 2. Read Approved Documents

- `.spec-workflow/specs/{spec-name}/request-spec.md`
- `.spec-workflow/specs/{spec-name}/requirements.md`
- `.spec-workflow/specs/{spec-name}/design.md`

### 3. Analyze (Main Agent)

The main agent investigates and decides the following. This becomes context handed to subagents.

#### 3.1 Container / Test Infrastructure Technology Selection

Detect the project type and container configuration, and select test technologies:

1. **Confirm container configuration**:
   - Read the Container Architecture section of design.md
   - Confirm whether docker-compose.yml / Dockerfile exist

2. **Decide DB test strategy**:
   - DB dependency present → testcontainers (default)
   - docker-compose.test.yml already exists → leverage it
   - No DB → not needed

3. **Decide E2E test runner**:
   - Frontend present (HTML templates, JSX/TSX, Leptos view! macro) → Playwright
   - API only → reqwest (Rust) / supertest (Node.js)

#### 3.2 Existing Test Pattern Survey

Explore the codebase and survey existing test frameworks, patterns, and helpers:

```bash
# Check test file structure
find . -name "*test*" -o -name "*spec*" | head -20

# Check test framework
grep -r "mockall\|rstest\|jest\|pytest\|vitest" Cargo.toml package.json 2>/dev/null

# Existing test helpers
find . -path "*/test*/*helper*" -o -path "*/test*/*fixture*" -o -path "*/test*/*util*" | head -10
```

Summarize the findings as input to subagents in the following form:
```
Test technology summary:
- Test framework: [vitest / jest / rstest / pytest, etc.]
- DB test strategy: [testcontainers / docker-compose.test.yml / not needed]
- E2E test runner: [Playwright / reqwest / supertest, etc.]
- Existing test helpers: [list of file paths]
- Existing test patterns: [summary of patterns]
```

#### 3.3 Enumerate Required Test Tools

Based on the results of sections 3.1 and 3.2, list the tools required for test execution in Required Test Tools table form:

1. **Test framework** (cargo test, vitest, jest, etc.) → record with Check Command and Required=Yes
2. **Container runtime** (when using testcontainers) → docker (Required=Yes)
3. **E2E test runner** (Playwright, Cypress, etc.) → Required=Yes, recorded with Install Command
4. **Browser engine** (for Browser E2E) → chromium (Required=Yes) — **Environment-dependent skipping not allowed**
5. **DB tools** (diesel_cli, prisma, etc.) → Required=Yes
6. **Optimization tools such as build cache** → Recommended

Summarize results in the following form, to be inserted into test-design.md in Step 5:
```
Required test tools:
| Tool | Min Version | Purpose | Check Command | Install Command | Required |
|------|-------------|---------|---------------|-----------------|----------|
| ... | ... | ... | ... | ... | ... |
```

**Important**: Tools required for E2E tests (Playwright, Chrome, etc.) must always be Required=Yes. Except for tests explicitly excluded under "Excluded Test Environments" in design.md, every test is mandatory to run.

#### 3.3.1 Test Tool Version Verification

For each tool in the Required Test Tools table, treat **"detecting the installed version"** and **"researching the latest stable version"** separately. The `Min Version` is taken from the **latest stable confirmed in the latter**, not from the former.

1. Confirm the **latest stable version** via WebSearch or registry CLI
   - You may use registry CLI only for crates.io / npm packages
     - `npm view {pkg} version`
     - Rust: `cargo search {crate} --limit 1 | grep "^{crate} ="` (verify exact match)
   - For other tools (docker, chromium, etc.), confirm via WebSearch on the official release page
   - Playwright: confirm the latest stable via `npm view playwright version`
   - Chromium: use the bundled version corresponding to the Playwright version (`npx playwright install chromium`). Record Min Version as `(bundled with playwright)`
2. If needed, separately detect the **currently installed version** as a local environment / project dependency
   - Playwright: `npx playwright --version` is treated as installed-version detection, not as latest-stable research
3. Update `Min Version` with the latest stable verified in step 1. Step 2 results are only diff-check reference info, not the basis for `Min Version`

As in Phase 2 step 3.5, do not use defaults from AI training data.

---

### 4. Generate Test Specifications via Subagents

Launch subagents **one at a time** to derive UT/IT/ST/E2E specs independently (CT is added after H-2). Per `${CLAUDE_PLUGIN_ROOT}/rules/serial-execution-policy.md`, concurrent subagent launches are prohibited across the plugin.

**Important**: Make Agent calls **one per message**. Wait for each subagent (A through E) to complete and return its output before launching the next. Do NOT batch multiple Agent calls into a single message.

#### Declaration-based derivation (K-7; see `dapper-hardening-orchestrator.md`)

Each Subagent reads, as the **highest-priority input** for derivation, **the `Test Layers:` field declaration in design.md DES-N** (made mandatory by K-2) and **the `Test Layers:` field declaration in requirements.md REQ-N.M** (made mandatory by K-1), and derives **only specs corresponding to the declared layers**. Heuristic derivation of non-declared layers is forbidden.

- If DES-11 declares `Test Layers: UT, CT, ST-1` → Subagent A derives UT-11.x, Subagent D (after H-2) derives CT-11, Subagent E derives ST-1
- If DES-3 declares `Test Layers: UT, IT-19` → Subagent A derives UT-3.x, Subagent B derives IT-19. Subagents C/D/E do not generate specs for it

**Fallback**: Only when design.md / requirements.md lack Test Layers declarations (legacy), each Subagent falls back to the conventional heuristic derivation. New specs require declaration-based derivation (K-2 / K-1 / K-6 / K-7 are linked).

Each Subagent's prompt must read the `Test Layers:` field from design.md / requirements.md and only process components / requirements corresponding to its responsibility layer.

#### Subagent A: Derive UT Specs

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Derive UT specs",
  prompt: "You are a test specification engineer. Generate Unit Test specifications.

    Read the following files:
    - {project-path}/.spec-workflow/specs/{spec-name}/design.md
    - {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Task:
    From the **Components and Interfaces** section of design.md, derive unit test specs for each component.

    Derivation rules:
    1. Enumerate each component's public interfaces (methods / functions)
    2. For each interface, design test cases across 4 categories (Happy Path / Boundary Values / Error Handling / Edge Cases)
    3. Identify mock targets from each component's **Dependencies**
    4. From the **Error Handling** table in design.md, design error-handling tests for each error code
    5. **Leptos frontend components**: When a component is a Leptos frontend component (uses view! macro, #[component], signals; located under pages/ / components/):
       - Do NOT specify tests for HTML rendering or DOM structure
       - Instead, specify the following tests:
         a. Signal state transitions (initial state, value after update)
         b. Correctness of derived computations (closures, Memo values)
         c. Validation logic (extracted from the component)
         d. Callback / handler logic (behavior of extracted functions)
         e. Server function business logic (core computation)
       - Annotate the Verification column of the UT table with 'Test target: extracted logic function'

    Naming convention: UT-{component number}.{test case number} (e.g., UT-1.1, UT-1.2, UT-2.1)

    Quality criteria:
    - Every component in design.md must have a UT spec
    - Each UT must cover the applicable categories among the 4
    - Each test case's Input / Expected Output / Verification must be concrete (no placeholders)
    - Leptos frontend component UT specs target extractable logic (signals, validation, computation), not HTML rendering

    Test technology context:
    {Insert the test technology summary investigated by the main agent here}

    Output format:
    Output the ## Unit Test Specifications markdown section as-is.
    Each component is a subsection (###); list test cases in table form."
})
```

#### Subagent B: Derive IT Specs (**backend HTTP API only**, tightened by J-1)

> J-1 tightens scope: IT targets the **backend HTTP API only**. Integrations crossing the frontend Resource → server fn boundary are the responsibility of CT (component reactivity) or ST (single feature full-stack); they are not IT. The phrasing "via server fn" is forbidden.

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Derive IT specs",
  prompt: "You are a test specification engineer. Generate Integration Test specifications.

    Read the following files:
    - {project-path}/.spec-workflow/specs/{spec-name}/design.md
    - {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Task:
    From the **Architecture** diagram and the Dependencies sections of **Components and Interfaces** in design.md, identify component-to-component interactions for the **backend HTTP API only** and turn them into test cases.

    Scope (tightened by J-1):
    - **In scope**: HTTP API endpoint behavior on the backend server (status code / response body / DB state changes / authentication and authorization)
    - **Out of scope**: UI operations / DOM checks / the frontend Resource → server fn boundary. These belong to CT (component reactivity) or ST (single feature full-stack). The phrasing "via server fn" is forbidden in IT specs
    - See the Test Taxonomy section in quality-checks.md for details

    Derivation rules:
    1. Among the arrows (dependencies) in the Architecture diagram, design HTTP integration test scenarios for each **backend-internal** edge
    2. Design DB integration tests for components that touch the DB (real DB / TempDir / docker-compose.test.yml)
    3. For external API integrations, design integration tests using mocks / stubs (mockito / wiremock)
    4. Interactions that require UI-driven behavior verification go to **ST or CT, not IT** (Subagent E / Subagent D's responsibility)

    Naming convention: IT-{scenario number} (e.g., IT-1, IT-2)

    Quality criteria:
    - An IT spec must exist for components whose `Test Layers:` field in design.md DES-N includes `IT-N` or `IT` (consistent with K-2)
    - Each IT must record Components, Interaction, Technology, Preconditions, Steps, Expected Result, and Verification Points
    - **IT specs that include UI verification / DOM operations are not allowed** (detected by Step B Check 15)

    Test technology context:
    {Insert the test technology summary investigated by the main agent here}

    Output format:
    Output the ## Integration Test Specifications markdown section as-is.
    Each scenario is a subsection (###); record details in a table or structured list."
})
```

#### Subagent C: Derive E2E Specs (**user journey only**, tightened by J-2)

> J-2 tightens scope: E2E is **strictly for user journeys**, covering only end-to-end flows that chain multiple features. "Tests of individual features" (e.g., zoom/rotate only, search only) belong to ST (System Test) and are not E2E.

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Derive E2E specs",
  prompt: "You are a test specification engineer. Generate End-to-End Test specifications.

    Read the following files:
    - {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    - {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Task:
    From the **user stories** and **Acceptance Criteria** in requirements.md, derive **user journey** test scenarios (end-to-end flows that chain multiple features).

    Scope (tightened by J-2):
    - **In scope**: User journeys that chain multiple features (e.g., login → search → click result → view details → logout)
    - **Out of scope**: Tests of individual features in isolation (e.g., zoom feature only / info panel toggle only / localStorage persistence only). These belong to ST (System Test). Per-feature E2E names like 'e2e-zoom-rotate.spec.ts' are forbidden
    - See the Test Taxonomy section in quality-checks.md for details

    Derivation rules:
    1. From each user story, turn the happy-path user journey containing **multiple feature chains** into an E2E scenario
    2. Include important failure scenarios (auth errors, insufficient permissions, etc.) as user-journey E2E scenarios
    3. If design.md has an API Design section, explicitly state API response verification points for each step of the user journey
    4. **Single-feature test demand** goes to ST specs (Subagent E), not E2E

    Naming convention: E2E-{scenario number} (e.g., E2E-1, E2E-2)

    Quality criteria:
    - Each E2E must include **chains of multiple features** (no chain → ST candidate)
    - Each E2E must record User Story reference, Test Type, Technology, Scenario Steps, Success Criteria, and Failure Scenarios
    - **Calling individual-feature tests (no chain) E2E is forbidden** (detected by Step B Check 15)

    Test technology context:
    {Insert the test technology summary investigated by the main agent here}

    Output format:
    Output the ## E2E Test Specifications markdown section as-is.
    Each scenario is a subsection (###); record details in a table or structured list."
})
```

#### Subagent D: Derive CT Specs (newly added by H-2)

> Newly added by H-2: CT (Component Test) targets **component reactivity** (mount → signal manipulation → DOM observation). Practicality on Leptos 0.7 + wasm-bindgen-test is confirmed in POC `wasm-bindgen-test-leptos-poc.md`.

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Derive CT specs",
  prompt: "You are a test specification engineer. Generate Component Test specifications.

    Read the following files:
    - {project-path}/.spec-workflow/specs/{spec-name}/design.md
    - {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Task:
    For components whose `Test Layers:` field in design.md DES-N (made mandatory by K-2) contains `CT` or `CT-N`, derive **component reactivity** test specs.

    Scope (finalized by H-2):
    - **In scope**: Reactivity of a single component (mount → signal manipulation → DOM observation)
    - **Out of scope**: Pure logic (UT's responsibility; verify with extracted functions) / real server communication (IT or ST) / user journeys (E2E)
    - **Typical verification items**:
      1. initial render: whether the signal's initial value is reflected in the DOM (query_selector + text_content)
      2. event wiring: whether on:click / on:submit / on:input update the signal (trigger via HtmlElement::click(); observe DOM after tick().await)
      3. signal-driven DOM update: signal change → reactive re-render → DOM verification
      4. Suspense / Resource: verify pending / loaded / error states via mocks (declared in design.md K-3)
      5. Effect: verify that on signal change, the Effect runs exactly once (no repeated firing)

    Implementation:
    - Rust / Leptos: wasm-bindgen-test + cargo test --target wasm32-unknown-unknown (wasm-pack not required)
    - .NET / Blazor: bUnit (standard)
    - Details: see quality-checks.md QC14 + tdd-skills-rust/references/leptos-frontend-testing.md

    Naming convention: CT-{component number}.{test case number} (e.g., CT-11.1, CT-11.2)

    Quality criteria:
    - A CT spec must exist for components whose `Test Layers:` field in design.md DES-N includes `CT` or `CT-N` (consistent with K-2)
    - Each CT must include the 4 fields: Mount Setup / Action (signal manipulation or event trigger) / DOM Verification / Signal Verification
    - **Verifying pure logic with CT is forbidden** (route to UT; detected by Step B Check 17/18)

    Test technology context:
    {Insert the test technology summary investigated by the main agent here}

    Output format:
    Output the ## Component Test Specifications markdown section as-is.
    Each scenario is a subsection (####); record Mount Setup / Action / DOM Verification / Signal Verification in a table or structured list."
})
```

#### Subagent E: Derive ST Specs (newly added by J-6)

> Newly added by J-6: ST (System Test) targets **full-stack behavior of a single feature** (UI operation → backend response → UI reflection). It is the middle layer between E2E (user journey) and CT (component reactivity in isolation).
> Subagent D is reserved as the CT spec deriver under H-2 (enabled after H is implemented). This Subagent is E.

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Derive ST specs",
  prompt: "You are a test specification engineer. Generate System Test specifications.

    Read the following files:
    - {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    - {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Task:
    From the user stories / individual features in requirements.md, derive **single-feature full-stack** test scenarios (verify UI operation → backend response → UI reflection for one feature).

    Scope (finalized by J-6):
    - **In scope**: Full-stack behavior of a single feature (e.g., 'login feature only', 'search feature only', 'zoom feature only')
    - **Out of scope**: Chains of multiple features (E2E's responsibility) / pure logic (UT) / component reactivity in isolation (CT) / backend HTTP API only (IT)
    - See the Test Taxonomy section in quality-checks.md for details

    Derivation rules:
    1. Decompose each REQ-N / Acceptance Criterion from a 'single-feature full-stack' viewpoint, turning each independent feature unit into a test scenario
    2. Components whose `Test Layers:` field in design.md DES-N declares `ST` or `ST-N` are ST targets (consistent with K-2)
    3. Verify by starting the real server, operating the UI, and confirming that the backend response is reflected in the UI
    4. **Scenarios that chain multiple features go to E2E (Subagent C), not ST**

    Naming convention: ST-{scenario number} (e.g., ST-1: login feature, ST-2: search feature)

    Quality criteria:
    - An ST spec must exist for features whose `Test Layers:` field in design.md DES-N includes `ST-N` or `ST`
    - Each ST must record Feature Scope (target feature scope), Test Path (UI → backend → UI route), Verification Points, and Expected Outcome
    - **STs that chain multiple features are not allowed** (use E2E if a chain is needed)

    Test technology context:
    {Insert the test technology summary investigated by the main agent here}

    Output format:
    Output the ## System Test Specifications markdown section as-is.
    Each scenario is a subsection (###); record details in a table or structured list."
})
```

---

### 5. Integrate and Create Document (Main Agent)

Integrate the outputs of the three subagents into a complete `test-design.md`.

1. Add a **Test Strategy Overview** at the top:
   - Overall test policy, Test Pyramid (UT > IT > E2E), environment requirements
   - Results of the test technology selection from section 3
   - **Required Test Tools** table: list of tools enumerated in section 3.3

2. **Place subagent outputs in order**:
   - Unit Test Specifications (Subagent A's output)
   - Component Test Specifications (Subagent D's output, component reactivity — newly added by H-2)
   - Integration Test Specifications (Subagent B's output, backend HTTP API only — J-1)
   - System Test Specifications (Subagent E's output, single-feature full-stack — newly added by J-6)
   - E2E Test Specifications (Subagent C's output, user journey only — J-2)

3. Build a **Requirements-Test Traceability Matrix**:
   - Cross-reference all subagent outputs and confirm every Requirement ID is linked to UT/IT/E2E
   - If anything is missing, the main agent adds it

4. Add **Test Data Requirements**:
   - Shared fixtures, test data generation policy

5. Add **E2E Test Infrastructure**:
   - Project Type Detection, Container Test Setup, Test Runner Configuration

6. Write to file:
```
.spec-workflow/specs/{spec-name}/test-design.md
```

**Frontmatter (required for new specs, per `${CLAUDE_PLUGIN_ROOT}/rules/spec-dependency-graph.md` SD2-SD3):**

Add the following YAML frontmatter at the top of the file. `depends_on` enumerates the REQ-N from requirements.md and the DES-N from design.md that this test design targets:

```yaml
---
spec_id: {spec-name}
phase: test-design
version: 1
depends_on:
  - file: requirements.md
    refs: [REQ-1, REQ-2]
  - file: design.md
    refs: [DES-1, DES-2]
---
```

The UT-N.M / IT-N / E2E-N identifiers are still made explicit via `####` headings as before (SD1).

**Quality criteria (integration-time checks):**
- Every Requirement ID must be linked to at least one UT and a related IT or E2E
- Every component in design.md must have a UT spec
- Each test case's Input / Expected Output / Verification must be concrete (no placeholders)
- Naming and formatting must be consistent across subagents (resolve any inconsistencies)

### 6. Self-Review via Subagent (before approval)

Validate the document in **2 stages** before approval.

#### Step A: fix (mechanical auto-fixes)

Auto-fix placeholders, formatting, and typos. Do not add or change content:

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Fix test-design spec (auto-fix)",
  prompt: "You are a spec document reviewer. Auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/test-design.md

    Document type: test-design

    Items eligible for auto-fix (may directly modify the file):
    - Remove placeholder text ([describe...], TODO, TBD)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Obvious typos

    Items NOT eligible for auto-fix (report as issues only):
    - Adding, removing, or modifying test cases
    - Changing test case content (Input, Expected Output, Verification)
    - Traceability inconsistencies

    Mode: fix — Return a structured report (auto-fixed items + remaining issues)."
})
```

#### Step B: check (content validation)

After fix completes, detect content issues. Do not modify the file:

```
Agent({
  subagent_type: "general-purpose",
  model: "opus",
  description: "Review test-design spec (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/specs/{spec-name}/test-design.md

    Document type: test-design
    Template: {project-path}/.spec-workflow/templates/test-design-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    Design: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no placeholders)
    2. UT COVERAGE: Every component in design.md must have corresponding UT specifications
    3. UT CATEGORIES: Each component's UT specs must cover all applicable categories (Happy Path, Boundary Values, Error Handling, Edge Cases)
    4. IT COVERAGE: Every significant component interaction in design.md Architecture must have an IT specification
    5. E2E COVERAGE: Every user story in requirements.md must have at least one E2E specification
    6. TRACEABILITY: Requirements-Test Traceability Matrix must cover ALL Requirement IDs. Every Requirement ID must have at least one UT and one IT or E2E
    7. SPECIFICITY: Test cases must have concrete Input, Expected Output, and Verification (no placeholders or vague descriptions)
    8. NAMING: Test case IDs follow the naming convention (UT-N.M, IT-N, E2E-N)
    9. ERROR HANDLING: design.md Error Handling table entries must have corresponding error handling test cases
    10. TEST DATA: Test Data Requirements section must define shared fixtures and generation strategy
    11. E2E INFRASTRUCTURE: E2E Test Infrastructure section must define project type, container test setup, and test runner
    12. CONTAINER CONSISTENCY: IT/E2E specs Technology fields must be consistent with design.md Container Architecture and E2E Test Infrastructure section
    13. REQUIRED TEST TOOLS: Required Test Tools section must exist within Test Environment Requirements, with at least one tool entry in table format (Tool, Min Version, Purpose, Check Command, Install Command, Required columns). All E2E test tools must be Required=Yes.
    14. FRONTMATTER (spec-dependency-graph.md SD2): Valid YAML frontmatter with spec_id, phase: test-design, version, depends_on (file entries pointing to requirements.md and design.md with refs) must exist at the top of the file. Every REQ-/DES- ID in depends_on.refs must exist in the referenced upstream file (SD4)
    15. TEST_LAYER_BOUNDARY (J-4, dapper-hardening): Each test specification must respect its layer boundary as defined in quality-checks.md Test Taxonomy:
       - IT-N specs must NOT include UI operations or DOM verifications (move to ST or E2E)
       - E2E-N specs must include chains of multiple features (single-feature tests must be moved to ST)
       - ST-N specs must NOT span multiple features (move to E2E if multi-feature journey)
       - UT specs must NOT depend on external I/O (clock / RNG / env / fs / HTTP / DB) — must use Mock points declared in design.md Architecture for Testability (K-3)
    16. CT_COVERAGE (H-2, dapper-hardening): For every UI component DES-N in design.md whose Test Layers field (K-2) declares `CT` or `CT-N`, a corresponding Component Test specification must exist in test-design.md `## Component Test Specifications` section. CT specs must include Mount Setup / Action / DOM Verification / Signal Verification fields
    17. CT_INTEGRATION_VERIFY (H-2, dapper-hardening): Each CT-N spec must verify component reactivity (mount + signal + DOM observation), NOT pure logic. Pure logic verification belongs in UT. Specifically: each CT-N must specify (a) how the component is mounted (`mount_to(...)`), (b) what signal is updated or what event is triggered, (c) how DOM is observed (query_selector + text_content / inner_html / outer_html)
    18. SIGNATURE_MATCH (C-2, dapper-hardening): For every test specification (UT / CT / IT / ST / E2E) that references a function or method from design.md DES-N, the function signature (return type + argument types) must **exactly match** the corresponding interface defined in the `Interfaces:` field of design.md DES-N. Mismatch examples:
        - design.md: `pub async fn list_roots(&self) -> Result<Vec<RootEntry>, AppError>` vs test-design.md UT: assumes `Vec<RootEntry>` (Result unwrapped) → error: `signature_mismatch`
        - design.md: `pub fn count(&self) -> usize` vs test-design.md UT: assumes `i32` return → error: `signature_mismatch`
    19. E2E_SNAPSHOT_PATH (F-1, dapper-hardening): If E2E specs reference snapshot comparison (toMatchSnapshot, toMatchAriaSnapshot, etc.), the test-design.md must explicitly mention `snapshotPathTemplate` configuration in `playwright.config.ts` (e.g., `tests/e2e/screenshots/{testFilePath}/{arg}.png`). Without explicit path template, baseline screenshots end up in default location and become non-portable.
    20. E2E_DOM_COMPARISON_METHOD (F-2, dapper-hardening): For E2E specs requiring **structural regression detection** (DOM tree comparison), use `toMatchAriaSnapshot` instead of `toContain` (substring match). `toContain` permits partial matches that hide structural breaking changes; `toMatchAriaSnapshot` enforces full structural equality.
    21. E2E_COMPOSITE_STATE_SCENARIO (F-3, dapper-hardening): If E2E scenario steps require a **composite state** (e.g., "showing 2 center images with left panel open"; "logged in + filter applied + sorted"), the operations to reach that state must be **explicitly specified in test-design.md** (e.g., NAV_NEXT N times + setting change X + ...). Implicit assumption of state without explicit setup steps → error: `e2e_setup_steps_missing`.
    22. EVIDENCE CITATIONS (evidence-coverage.md EC1): Read task_type from .spec-workflow/specs/{spec-name}/request-spec.md frontmatter and detect whether this document contains any EV-{category}-{NNN} citation (HTML comment, inline paren form, or frontmatter depends_on.refs).
        - If request-spec.md does not exist, or task_type is absent → SKIP checks 22-24 (EC5) and note 'evidence checks skipped (no request-spec / unclassified)' in the report.
        - If task_type is 'legacy' AND no EV-{category}-{NNN} citation is present in this document → SKIP checks 22-24 (EC5) and note 'evidence checks skipped (legacy, no EV citations)' in the report.
        - If task_type is 'legacy' AND at least one EV-{category}-{NNN} citation is present (opt-in legacy mode, EC5):
            Run check 22 (EC1 integrity) on every citation as described below.
            SKIP checks 23-24 and note 'legacy spec: ran EC1 only due to EV citations; skipped EC2 / EC3' in the report.
        - If task_type is any other declared value, run checks 22-24 normally.
        - For every EV-{category}-{NNN} citation in this document (HTML comment, inline paren form, or frontmatter depends_on.refs) when check 22 applies:
            a. .spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md must exist.
            b. The referenced file's frontmatter spec_name: must equal this spec-name.
            c. The {category} must be listed in ${CLAUDE_PLUGIN_ROOT}/rules/task-types.md TT3 (or the project's user-config/task-types.yml TT4).
          Any failure = FAIL with rule_id EC1.
    23. INLINE CODE BUDGET (evidence-coverage.md EC3): Apply this check only when check 22 routed to full enforcement (non-legacy classified task_type). Count fenced code block lines (between opening and closing fences, exclusive). Fail if any of:
            - A single fenced block exceeds 15 lines.
            - Cumulative fenced-block lines within a single H2 or H3 section exceed 30 lines.
            - Total fenced-block lines in the document exceed 120 lines.
          For each violation FAIL with rule_id EC3; fix_hint: 'Move fixture-like or harness-like excerpts to an evidence file under evidence/test-harness/ (or a more specific category) and leave a brief summary + citation'. Markdown tables and ASCII diagrams are NOT counted.
    24. PER-TESTCASE EVIDENCE (evidence-coverage.md EC2, per UT/IT/E2E): Apply this check only when check 22 routed to full enforcement (non-legacy classified task_type). Every '#### UT-N.M:', '### IT-N:', and '### E2E-N:' section must cite at least one EV-... that anchors the behavior under test. If a case exercises a truly new behavior with no existing-code anchor, use '<!-- no-evidence: {reason} -->' (per-artifact waiver per EC2) with a non-empty reason inside the section. Missing both = FAIL rule_id EC2_perTestCase with fix_hint 'Cite the EV that captures the current or expected behavior the test guards (typically EV-contract-current-*, EV-branches-*, or EV-regressions-*).'

    Reporting: for EC1/EC2/EC3 issues, include fields rule_id, location, message, fix_hint.
    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 7. Approval Workflow

Same strict process — verbal approval is never accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only. Save the returned `approvalId`.

2. **Check approval (synchronous)**: After the user approves via the dashboard / VS Code extension, run:
   ```
   /check-approval <approvalId> next:/spec-tasks
   ```
   `check-approval` fetches status once via the `approvals` MCP tool (no polling) and branches:
   - **pending**: User has not acted yet — instruct the user to approve, then re-run `/check-approval`
   - **approved**: Cleanup is performed automatically, and `check-approval` automatically invokes `/spec-tasks`
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval

3. **Handle needs-revision** (if status was needs-revision):
   - Update test-design using reviewer comments, spawn the review subagent again
   - Submit a NEW approval request and run `/check-approval <newApprovalId> next:/spec-tasks`

## Rules

- Feature names use kebab-case
- One spec at a time
- Every design.md component must have UT specs
- Every requirement must appear in the Traceability Matrix
- Test cases must be concrete (no placeholders in Input/Expected Output/Verification)
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
