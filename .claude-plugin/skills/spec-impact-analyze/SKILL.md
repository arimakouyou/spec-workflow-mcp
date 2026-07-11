---
name: spec-impact-analyze
description: "Impact analysis for upstream spec changes. Use this skill when the user wants to understand the downstream effect of changes made to requirements.md or design.md, asks 'what breaks if I change REQ-N', or wants to preview which design / test-design / tasks files need revisiting. Triggers on: 'impact analysis', 'what does this change affect', 'spec impact', 'downstream impact', '/spec-impact-analyze'. Reads frontmatter depends_on (per spec-dependency-graph.md SD7) and classifies each downstream file as green / amber / gray."
---

# Spec Impact Analysis

Analyze how a change in one spec file (typically `requirements.md` or `design.md`) propagates to downstream spec files via the `depends_on` frontmatter declared in `${CLAUDE_PLUGIN_ROOT}/rules/spec-dependency-graph.md` SD2. Classify each downstream file into **green / amber / gray** bands per SD7 so the user can decide which files need revisiting.

This skill is **advisory** — it does not modify any file or gate any workflow. It surfaces impact so the human can decide.

## When to Use

- A user just modified `requirements.md` (or `design.md`) and wants to know what else needs updating
- Before opening a PR that changes upstream specs, to preview downstream effects
- During a Phase Reset decision, to understand the blast radius of reverting a design choice

## Prerequisites

1. At least one spec exists under `.spec-workflow/specs/{spec-name}/`
2. The target spec file (requirements.md or design.md) has changes to analyze
3. Downstream files (design.md / test-design.md / tasks.md) ideally have the `depends_on` frontmatter (per `spec-dependency-graph.md` SD2). Files without frontmatter are reported as `not_available` — the skill does not fail on legacy specs (SD3)

## Inputs

- **spec name** (kebab-case, required)
- **target file** (optional; default: `requirements.md`). Must be one of `requirements.md`, `design.md`, or `test-design.md` — i.e., an upstream file whose downstream graph is meaningful
- **change source** (optional; one of):
  - `git-diff` — compare HEAD vs working tree (default)
  - `ref:<git-ref>` — compare working tree vs a specific git ref (e.g., `ref:main`)
  - `manual:<IDs>` — user provides the list of changed IDs directly (e.g., `manual:REQ-1.1,REQ-2.3`)

## Process

### 1. Validate Inputs

- Confirm `.spec-workflow/specs/{spec-name}/` exists
- Confirm `{target file}` exists
- If target file has **no frontmatter**, report: `Target file {target} has no frontmatter (legacy spec). Impact analysis cannot identify dependencies — please add frontmatter per spec-dependency-graph.md SD2 or run /spec-verify first to migrate.` and exit with status `not_available`

### 2. Detect Changed IDs

Determine which IDs (REQ-N.M / DES-N / MOD-N / API-N / UT-N.M / IT-N / E2E-N) were changed in the target file.

#### git-diff / ref:<git-ref>

Run the appropriate git command from the project root:

```bash
# For git-diff (working tree vs HEAD)
git diff -- .spec-workflow/specs/{spec-name}/{target-file}

# For ref:<git-ref>
git diff {git-ref} -- .spec-workflow/specs/{spec-name}/{target-file}
```

Extract from the diff:
- Added / removed / modified lines
- For each hunk, identify the enclosing **heading context** (`### REQ-N:`, `### DES-N:`, `#### UT-N.M:`, etc.) using the most recent heading line above the hunk
- Collect the set of IDs touched

#### manual:<IDs>

Parse the comma-separated ID list from the input.

### 3. Build the Reverse Dependency Graph

For each file under `.spec-workflow/specs/{spec-name}/` with a frontmatter containing `depends_on`:

1. Read the frontmatter
2. For each entry in `depends_on` where `file` matches the target file, collect `refs`
3. Invert: for each changed ID, which downstream files reference it?

If a downstream file has **no frontmatter**, record it as `not_available` rather than skipping silently (so the user knows coverage is incomplete).

### 4. Classify Each Downstream File

Apply `${CLAUDE_PLUGIN_ROOT}/rules/spec-dependency-graph.md` SD7 semantics. For each (downstream file, change) pair, choose one band:

| Band | Criterion | Recommended Action |
|------|-----------|--------------------|
| **green** | Downstream does not reference any changed ID, OR the change is purely textual (typo, wording) without altering semantics of a referenced ID | No action — informational only |
| **amber** | Downstream references a changed ID AND the change alters semantics (Acceptance Criteria rewritten, API contract changed, component purpose shifted). Also amber: an ID referenced by downstream was **deleted** or **renamed** | Revisit the downstream file and confirm/update content |
| **gray** | Downstream does not reference any changed ID AND is potentially affected only through indirect reasoning (rare). Informational only |
| **not_available** | Downstream file lacks frontmatter — dependency cannot be determined statically | Recommend adding frontmatter (SD3 opt-in) or manual review |

**Distinguishing amber vs green for referenced IDs**: read both the before and after state of the changed ID. Ask:

- Did the `WHEN ... SHALL` clause change its trigger or response? → **amber**
- Was an Acceptance Criterion added or removed? → **amber**
- Was a component's `Purpose` / `Interfaces` rewritten? → **amber**
- Was only the description text cleaned up without changing the contract? → **green**

If you cannot determine the distinction from static inspection alone (e.g., the prose is ambiguous), default to **amber** — err on the side of caution.

### 5. Report

Output a markdown report. Do **not** write to any file unless the user explicitly asks (e.g., "save this to a file").

```markdown
# Impact Analysis: {spec-name} — {target-file}

**Change source**: {git-diff | ref:<git-ref> | manual}
**Changed IDs**: {REQ-1.1, REQ-2.3}

## Downstream Classification

| Downstream File | Band | Referenced Changed IDs | Recommended Action |
|-----------------|------|------------------------|--------------------|
| design.md | amber | REQ-1.1 | Revisit DES-3 and DES-5 (both satisfy REQ-1.1) |
| test-design.md | amber | REQ-1.1 | Revisit UT-3.1, IT-2 (cover REQ-1.1) |
| tasks.md | gray | (no direct reference via frontmatter) | Possibly affected via design.md change — review after design.md is updated |

## Summary

- green: 0 files
- amber: 2 files
- gray: 1 file
- not_available: 0 files

## Notes

- This is an **advisory report**. No gates are triggered. The user decides which downstream files to revisit.
- Legacy spec files (no frontmatter) would appear as `not_available`. Run /spec-verify to migrate them.
- For amber classifications, re-running /spec-impact-analyze after each downstream update helps confirm the fix did not introduce new amber items.
```

### 6. (Optional) Save to File

If the user requests, save the report to `.spec-workflow/specs/{spec-name}/reviews/impact-{YYYY-MM-DD-HHMM}.md` so it can be referenced in PR descriptions.

## Rules

- **No writes to spec files** — this skill only reads `.spec-workflow/specs/{spec-name}/*.md`
- **No workflow gating** — green/amber/gray classifications are advisory, not blocking
- **Legacy tolerance** — files without frontmatter are reported as `not_available`, not error
- **Heuristic defaults** — when classification is ambiguous, default to **amber** (user confirmation)
- **Do not re-order heuristics** — the SD7 table in `spec-dependency-graph.md` is the source of truth. If the user disagrees with a classification, they should propose a change to SD7 rather than to this skill
