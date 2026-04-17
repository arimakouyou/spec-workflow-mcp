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
3. **Frontmatter `depends_on.refs`** (per `spec-dependency-graph.md` SD2) for document-level dependencies — ただし後述の precedence note の通り、現時点では `/spec-verify` が `EV-*` を refs として認識しない。後方互換のため Step B の EC1 整合性チェックは `refs` 内の `EV-*` を citation として拾うが、**新規の citation は HTML コメントまたは括弧内引用を使うこと** を推奨する:
   ```yaml
   # 非推奨（未サポート運用）
   depends_on:
     refs: [REQ-1.1]  # EV-* は refs に入れず、本文で <!-- EV-callers-003 --> の形で引用する
   ```

Rules:

- The canonical form of an EV-ID in any of these contexts is the exact string `EV-{category}-{NNN}`. Matching is case-sensitive; `{NNN}` is exactly 3 digits with zero-padding.
- The evidence file's frontmatter `ev_id:` and its filename stem **must match exactly** (per `spec-dependency-graph.md` SD1). A mismatch is a FAIL under EC1.
- A citation that points to a file that does not exist under `.spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md` is a FAIL.
- A citation that names a `{category}` that is neither listed in `task-types.md` TT3 nor in the project's `user-config/task-types.yml` (TT4) is a FAIL.
- A citation that points to an EV whose `spec_name:` frontmatter disagrees with the current spec is a FAIL. Cross-spec citations are not supported in Step 2; they may be introduced in a later step.

> **Precedence note (EC1 ↔ SD3/SD5)**: `/spec-verify` は現時点では `depends_on.refs` の要素として `REQ-N` / `REQ-N.M` / `DES-N` / `MOD-N` / `API-N` / `UT-N.M` / `IT-N` / `E2E-N` のみを認識し、`EV-*` エントリは未サポート（未知の ref として扱われる可能性がある）。したがって本 PR の時点では、EV の引用は HTML コメント（`<!-- EV-{category}-{NNN} -->`）または括弧内引用（`(EV-{category}-{NNN})`）を正式な方法とし、`depends_on.refs` への EV-ID 直接記載は未サポート運用とする。将来 `/spec-verify` に EV-* 対応が入る際は、SD3 と EC1 を同時に更新する。

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

- **Per-artifact waiver**: `<!-- no-evidence: {reason} -->` comment adjacent to a specific item (per `### REQ-N:` AC, per `### DES-N:` / `### MOD-N:` section, per `#### UT-N.M:` / `### IT-N:` / `### E2E-N:` section) documents why no EV applies to that item. The Step B check accepts this as non-blocking only when `{reason}` is non-empty.
- **Doc-level category waiver** (requirements.md only): `<!-- no-evidence: {category} — {reason} -->` comment placed at the top of `requirements.md` waives the doc-level EC2 category coverage requirement for that single `{category}`. Both `{category}` (must match one of the categories listed in `task-types.md` TT3 / TT4) and `{reason}` must be non-empty; the Step B check records it as WARN rather than FAIL. One comment per waived category.
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

Step B sub-agents must evaluate evidence coverage for legacy / unclassified specs in this exact order:

1. If `request-spec.md` is missing → SKIP all EC checks and return PASS for the evidence portion.
2. If `request-spec.md` exists but `task_type` is absent → SKIP all EC checks and return PASS for the evidence portion.
3. If `task_type: legacy` **and** the spec contains no `EV-{category}-{NNN}` citations (HTML comment, inline paren form, `_Evidence` task metadata, or `depends_on.refs` EV entry) → SKIP all EC checks and return PASS for the evidence portion. This preserves the legacy workflow exception documented in `spec-workflow-enforcement.md`.
4. If `task_type: legacy` **and** the spec contains one or more `EV-*` citations → treat the spec as **opt-in for citation integrity only**:
   - Run EC1 and require every cited EV identifier to resolve correctly (file existence, `spec_name:` match, category validity).
   - Do **not** enforce EC2 (neither doc-level category coverage nor per-artifact requirements). Missing evidence on REQ/DES/MOD/testcase/task in a legacy spec is never a FAIL.
   - Treat EC3 as **advisory only**: report oversized inline code excerpts as informational notes, but do not FAIL Step B on that basis.
5. Only specs whose `request-spec.md` declares a non-legacy `task_type` are fully subject to EC1 / EC2 / EC3.

## EC6: Retrofitting Existing Specs

When a previously-created non-legacy spec adds EV citations for the first time:

- The skill run that introduces citations should add them using supported body citation forms from `EC1`（HTML コメントアンカー `<!-- EV-{category}-{NNN} -->`、括弧内引用 `(EV-{category}-{NNN})`、または tasks.md の `_Evidence:` メタデータ）。新規の citation は frontmatter `depends_on.refs` には **追加しない**（EC1 precedence note の通り、現時点で `EV-*` は `/spec-verify` が refs として未サポートのため、`/spec-verify` から unknown ref として reject される可能性がある）。
- `EC3` line-count violations uncovered by retrofitting are reported but do not block approval on the first retrofit pass; they become blocking after the second run. This avoids a wall of errors on legacy documents while still encouraging cleanup.
