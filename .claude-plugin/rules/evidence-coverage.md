---
always_apply: true
---

# Evidence Coverage

Rules that govern how spec documents cite evidence files and how large code quotations may become inside the spec body. Consumed by the Step B check sub-agents of `/spec-requirements`, `/spec-design`, `/spec-test-design`, and `/spec-tasks`. Orthogonal to `task-types.md` (TT defines which categories must exist; EC defines how they are cited and how much code may live inline).

Scope: applies only to specs whose `request-spec.md` declares a non-legacy `task_type` (see `task-types.md` TT5). Legacy/unclassified specs are exempt.

## EC1: EV-ID Citation Format

Evidence files created by `/spec-investigate` are named `EV-{category}-{NNN}` where `{NNN}` is a 3-digit zero-padded sequence per category (e.g. `EV-callers-001`). Spec documents cite them in one of three forms:

1. **HTML comment anchor** (preferred for fine-grained linking inside Markdown lists):
   ```markdown
   - User login must validate MFA before issuing a session <!-- EV-branches-002 -->
   ```
2. **Inline reference** (preferred at the end of a sentence or bullet):
   ```markdown
   Existing handler enforces a 30-second timeout. (EV-contract-current-001)
   ```
3. **Frontmatter `depends_on.refs`** (per `spec-dependency-graph.md` SD2) for document-level dependencies:
   ```yaml
   depends_on:
     refs: [REQ-1.1, EV-callers-003]
   ```

Rules:

- The canonical form of an EV-ID in any of these contexts is the exact string `EV-{category}-{NNN}`. Matching is case-sensitive.
- A citation that points to a file that does not exist under `.spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md` is a FAIL.
- A citation that names a `{category}` that is neither listed in `task-types.md` TT3 nor in the project's `user-config/task-types.yml` (TT4) is a FAIL.
- A citation that points to an EV whose `spec_name:` frontmatter disagrees with the current spec is a FAIL. Cross-spec citations are not supported in Step 2; they may be introduced in a later step.

## EC2: Required Citation Sites (blocking for classified task types)

Every non-legacy spec must demonstrate that each required evidence category (declared by `task_type` in `task-types.md` TT2 / TT4) is actually used — a category that is collected but never cited is a signal the investigation was ceremonial. Additionally, specific artifacts in each phase must anchor to an EV citation so implementation can follow the evidence back to source code.

Enforcement matrix (FAIL on violation unless noted):

| Phase / artifact | Required citation |
|------------------|-------------------|
| `requirements.md` (doc-level) | Every required category for this spec's `task_type` must be cited **at least once** somewhere in the document or its frontmatter `depends_on.refs`. Missing a category = FAIL. |
| `requirements.md` (per REQ) | Each `### REQ-N:` heading SHOULD carry an `<!-- EV-... -->` citation on one of its Acceptance Criteria. This is a WARN, not a FAIL — some REQs are pure policy with no existing-code anchor. |
| `design.md` (per DES-N / MOD-N) | Each `### DES-N:` and `### MOD-N:` section must cite at least one EV if the component/model touches or replaces existing code. Pure-new abstractions (no relevant existing-code neighborhood) may cite `EV-test-harness-*` or be marked with `<!-- no-evidence: reason -->`. Unjustified missing citation = FAIL. |
| `design.md` (Code Reuse Analysis) | The Code Reuse Analysis section must be driven by EV citations (no free-form code path lists). Missing citations here = FAIL. |
| `test-design.md` (per UT / IT / E2E) | Each test case must cite at least one EV whose `sources:` frontmatter anchors the behavior being tested. Missing citation = FAIL. |
| `tasks.md` (per task) | Each implementation task (excluding Phase 0 setup and PhaseReview tasks) must carry an `_Evidence: EV-...` line listing at least one EV that scoped the task. Missing `_Evidence` = FAIL. |

Escape hatches:

- `<!-- no-evidence: {reason} -->` comment adjacent to an item documents why no EV applies. The Step B check accepts this as non-blocking only when `{reason}` is non-empty.
- `task_type: legacy` specs skip EC2 entirely (see EC5).
- Retrofit allowance: EC6 still applies — a first-pass retrofit run converts EC2 FAILs into WARNs; they become blocking from the second run onward.

Interaction with `_Evidence` in tasks.md:

- The `_Evidence:` line lists EV-IDs space- or comma-separated after the colon: `_Evidence: EV-callers-001 EV-branches-002`.
- These IDs join the normal EC1 integrity check (citations must resolve).
- Task implementation skills (`/spec-impl-code`, `/spec-impl-test-write`) read `_Evidence` and load only those EV files. Not a Step-B rule, but relevant context.

## EC3: Inline Code Quotation Budget

Spec body files (`request-spec.md`, `requirements.md`, `design.md`, `test-design.md`, `tasks.md`) must keep inline code excerpts short. Long excerpts belong in evidence files, not in the spec body.

Limits:

| File | Per-fenced-block ceiling | Per-section cumulative ceiling | Document ceiling |
|------|--------------------------|--------------------------------|------------------|
| `requirements.md` | 10 lines | 20 lines inside any `##`/`###` section | 80 lines total |
| `design.md` | 20 lines | 40 lines per `##`/`###` section | 200 lines total |
| `test-design.md` | 15 lines | 30 lines per `##`/`###` section | 120 lines total |
| `tasks.md` | 10 lines | 20 lines per `##`/`###` section | 60 lines total |

Definitions:

- A "fenced block" is any ``` block, regardless of language.
- Lines are counted between the opening and closing fences, exclusive of the fences themselves.
- A "section" is the content from one heading (H2 or H3) to the next heading of the same or higher level.
- Schema-ish fragments (YAML frontmatter, JSON samples, OpenAPI stubs) count toward the budget the same as code.

Enforcement:

- Exceeding the per-block or per-section ceiling is a FAIL with the fix suggestion: "Move the long excerpt to an evidence file (category best matching the content) and leave a short summary + `EV-*` citation in its place."
- Exceeding the document ceiling is a FAIL even if individual blocks are small; refactor via evidence.
- The budget does not apply to block-quoted prose, ASCII diagrams, or Markdown tables — only fenced code blocks.

## EC4: Step-B Reporting

Step B sub-agents of the four spec skills must report issues with the following fields when they fire on an evidence rule:

- `rule_id`: one of `EC1`, `EC2`, `EC3`
- `location`: file path + line number or section heading
- `message`: concrete problem
- `fix_hint`: one-sentence instruction (e.g., "Create EV-callers-004 under .spec-workflow/specs/{name}/evidence/callers/ and replace the 37-line excerpt with the citation")

FAILs from `EC1` / `EC3` are blocking per `enforcement-levels.md` L4. `EC2` WARNs are non-blocking in Step 2.

## EC5: Interaction with Legacy Specs

- If `request-spec.md` is missing, or its `task_type` is absent, or `task_type: legacy`, the Step B sub-agent must SKIP all EC checks and return PASS for the evidence portion. This preserves the legacy workflow exception documented in `spec-workflow-enforcement.md`.
- A `task_type: legacy` spec that nonetheless contains EV-* citations is treated as opt-in: EC1 still applies (citations must resolve), but EC3 remains advisory.

## EC6: Retrofitting Existing Specs

When a previously-created non-legacy spec adds EV citations for the first time:

- The skill run that introduces citations must also add/update the frontmatter `depends_on.refs` to include any EV referenced at the document level.
- `EC3` line-count violations uncovered by retrofitting are reported but do not block approval on the first retrofit pass; they become blocking after the second run. This avoids a wall of errors on legacy documents while still encouraging cleanup.
