---
name: spec-investigate
description: "Phase 0.5 of spec-driven development: collect existing-code evidence before writing requirements, so specs cite file:line citations instead of guessing. Use this skill after request-spec.md is approved and before running /spec-requirements, whenever the spec declares a non-legacy task_type. Triggers on: 'investigate existing code for spec', 'collect evidence', 'scan legacy before requirements', or auto-invocation via /check-approval next:/spec-investigate."
---

# Spec Investigate (Phase 0.5)

Collect and structure **evidence** from the existing codebase so requirements, design, and test-design phases can cite specific files and line ranges instead of re-reading code from scratch. The output is a set of small topic-scoped files under `.spec-workflow/specs/{spec-name}/evidence/` plus an index `manifest.md`. This phase is **not** gated by dashboard approval — it produces supporting material, not a contract — but a self-check validates coverage before control passes to `/spec-requirements`.

This skill is opt-in: it runs only for specs whose `request-spec.md` declares a concrete `task_type` (see `.claude-plugin/rules/task-types.md`). Legacy specs bypass it entirely.

## Prerequisites Check (MANDATORY — DO NOT SKIP)

1. Verify `.spec-workflow/specs/{spec-name}/request-spec.md` exists and has an approved status in spec history. If not, stop and tell the user to run `/spec-request-spec` first.
2. Read the frontmatter of `request-spec.md` and extract `task_type`.
   - If `task_type` is missing → treat the spec as legacy. Do **not** write any evidence. Stop and tell the user: "This spec has no task_type declared, so evidence collection is skipped. Proceed with `/spec-requirements`." Exit cleanly.
   - If `task_type: legacy` → same as above, stop and forward to `/spec-requirements`.
   - Otherwise proceed.
3. Read `.claude-plugin/rules/task-types.md` (TT2, TT3) and, if it exists, `.spec-workflow/user-config/task-types.yml`. Compute the **required evidence categories** for the declared `task_type`. Unknown `task_type` → STOP and ask the user to fix `request-spec.md`.

## Inputs

- `{spec-name}` (kebab-case). Ask if not provided.
- The approved `request-spec.md` for that spec.

## Process

### 1. Load the Manifest Template

Check for a custom template first. If none exists, fall back to the default:

1. `.spec-workflow/user-templates/investigation-manifest-template.md` (custom)
2. `.spec-workflow/templates/investigation-manifest-template.md` (default)

### 2. Draft the Manifest

Write an initial `.spec-workflow/specs/{spec-name}/evidence/manifest.md` from the template. Fill:

- `spec_name`, `task_type`, `generated_at` (ISO 8601), `status: draft`
- Section 1 (scope): summarize request-spec in ≤3 lines
- Section 2 (coverage plan): one row per required category. For each, list concrete directories, globs, or known files to scan, and pick **shallow** or **deep** depth. Default:
  - `feature-add`, `feature-modify`, `refactor`, `legacy-migration` → **deep** for the change target, **shallow** for cross-cutting
  - `bugfix` → **deep** only for `root-cause-paths` and `repro`, shallow elsewhere

### 3. Spawn Read-Only Explore Agents in Parallel

For each required category in the manifest, launch one `Explore` sub-agent. **Run them in a single message with multiple Agent tool calls so they execute in parallel.** Do not exceed 4 concurrent agents — split into waves if more categories are required.

Each agent prompt MUST include:

- The spec name, `task_type`, and the category being investigated
- The category definition copied from `task-types.md` TT3
- The directories/globs to scan for that category (from the manifest)
- The `evidence-template.md` format to follow (frontmatter + sections)
- Instructions to produce **one file per topic**, not per source file, named `.spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md` with a zero-padded 3-digit sequence (001, 002, ...)
- A size guide: aim for 50–150 lines per evidence file; split larger topics
- A requirement that `sources:` in the frontmatter is a YAML list whose entries have both `path:` (real file path) and `lines:` (e.g. `L10-L45`) keys, not fabricated citations (format defined in `evidence-template.md`)
- The `Explore` thoroughness level: `medium` by default, `very thorough` for `deep` rows

Example prompt skeleton (fill in before each call):

```
You are producing evidence for a spec workflow phase.

Spec: {spec-name}
task_type: {task_type}
Category: {category}   (definition: {copy from TT3})
Depth: {shallow|deep}
Scan targets: {globs/dirs from manifest}

Write one or more evidence files under:
  .spec-workflow/specs/{spec-name}/evidence/{category}/

Each file:
- Uses the evidence template at .spec-workflow/templates/evidence-template.md
- Is 50–150 lines, scoped to a single topic
- Fills `sources:` as a YAML list of entries, each with `path:` (real file path) and `lines:` (e.g. `L10-L45`); see evidence-template.md
- Names: EV-{category}-001.md, EV-{category}-002.md, ...
- **The file name stem and the frontmatter `ev_id:` MUST match exactly** — both carry the same `EV-{category}-{NNN}` string (per `.claude-plugin/rules/spec-dependency-graph.md` SD1). A mismatch will FAIL the EC1 integrity check.
- Quotes only what is needed to establish the fact (avoid full-file dumps)

Return a short summary listing each file created with its topic and the list of sources (path:Lstart-Lend).
```

Wait for all agents to complete.

### 4. Update the Manifest

Merge the sub-agent reports into section 3 of `manifest.md` (one row per EV produced). Fill section 5 (gaps) with topics the sub-agents flagged as incomplete.

### 5. Self-Check via Subagent (before transitioning)

Validate coverage in **2 stages**.

#### Step A: fix (mechanical)

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Fix investigation manifest and evidence files (auto-fix)",
  prompt: "You are a spec evidence reviewer. Auto-fix minor issues in the manifest and evidence files under:
    {project-path}/.spec-workflow/specs/{spec-name}/evidence/

    Document type: investigation-artifacts

    Auto-fix targets (you may directly modify files):
    - Remove placeholder text ([describe...], TODO, TBD) in manifest.md
    - Fix markdown formatting (table alignment, heading levels)
    - Normalize EV file names to EV-{category}-NNN.md (3-digit, per category)
    - Fix obvious typos in titles and section headers

    Not auto-fix targets (report as issues only):
    - Adding, splitting, or merging evidence files
    - Changing or adding source citations
    - Changing category assignments

    Mode: fix — Return a structured report (auto-fixed items + remaining issues)."
})
```

#### Step B: check (coverage validation)

```
Agent({
  subagent_type: "general-purpose",
  model: "opus",
  description: "Review investigation coverage (check)",
  prompt: "You are a spec evidence reviewer. Review artifacts under (do NOT modify files):
    {project-path}/.spec-workflow/specs/{spec-name}/evidence/

    Inputs:
    - Manifest: .spec-workflow/specs/{spec-name}/evidence/manifest.md
    - task_type from .spec-workflow/specs/{spec-name}/request-spec.md frontmatter
    - Required categories per .claude-plugin/rules/task-types.md TT2 (and TT4 overrides if .spec-workflow/user-config/task-types.yml exists)

    Checks:
    1. COVERAGE: Every required category for the declared task_type has at least one EV-*.md file under evidence/{category}/
    2. SOURCES_EXIST: For each EV file, every entry under sources: has a path that exists in the repo (use the Read tool to probe). Line ranges are plausible (start <= end, end <= file length).
    3. TOPIC_SCOPING: No EV file exceeds 200 lines. Warn if any file is under 20 lines (likely too thin).
    4. MANIFEST_CONSISTENCY: manifest.md section 3 lists every EV file that exists on disk, and vice versa. No orphans.
    5. FRONTMATTER: Each EV file has ev_id, category, task_type, spec_name, topic, and sources fields populated (no placeholder strings).

    Mode: check — DO NOT modify files. Return PASS/FAIL with a structured issue list (file path, check id, message, suggested fix)."
})
```

If Step B returns FAIL, fix the issues yourself (re-run targeted Explore agents for missing evidence, edit misnamed files, etc.) and re-run Step B up to 3 times. Once PASS, set `status: ready` in the manifest frontmatter.

### 6. Transition to Requirements

Evidence is supporting material, not a contract — **do not** call the `approvals` MCP tool. Instead, once Step B PASS:

1. Print a short summary to the user: number of EV files per category and any remaining gaps from manifest section 5.
2. Invoke `/spec-requirements` directly with the spec name.

If the user interrupts before Step B passes, leave `status: draft` in the manifest so the next invocation of this skill can resume.

## Rules

- Only `Read`, `Grep`, `Glob`, `Bash` (read-only probes) and `Agent` (Explore / general-purpose) are used for discovery. Sub-agents may write files **only** under `.spec-workflow/specs/{spec-name}/evidence/`.
- Evidence files must cite real `path:Lstart-Lend`. Fabricated citations are a FAIL in Step B.
- One EV file = one topic, 50–150 lines target, 200 lines hard ceiling.
- This skill never creates requirements.md, design.md, test-design.md, or tasks.md.
- Never accept `task_type` from conversation — only from `request-spec.md` frontmatter.
- On any blocking error (unknown `task_type`, missing template, Step B FAIL after 3 retries), stop and report the situation to the user per `CLAUDE.md` automation-limits rule. Do not silently fall through to `/spec-requirements`.
