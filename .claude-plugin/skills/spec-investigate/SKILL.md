---
name: spec-investigate
description: "Phase 0.5 of the v2 spec workflow: collect evidence (EV-{category}-NNN files) that requirements and design cite, instead of guessing about existing code or library behaviour. Categories come from the request-spec task_type. Triggers on: 'collect evidence', 'investigate before requirements', '事前調査', or automatically after request-spec approval."
---

# Investigation (Phase 0.5)

Evidence is frozen once collected: not approved, never rewritten. A later spec phase that needs more evidence adds a new EV file.

## 1. Plan

Read `task_type` from `request-spec.md` frontmatter. The required categories are in `${CLAUDE_PLUGIN_ROOT}/rules/doc-format.md` §4.1.

| Category | What to establish |
|---|---|
| code | The current structure, entry points and conventions the change touches |
| contract | Current public behaviour: API shapes, error mapping, persisted formats |
| tests | Existing test harnesses and fixtures, and how tests are run |
| regressions | The reproduction and root cause of the bug (bugfix) |
| lib | The runtime behaviour of each external library the design will rely on (greenfield and new dependencies), taken from its documentation or vendored source |

## 2. Collect

For each category, launch one read-only Explore agent. Launch them one per message, serially. Ask each agent for:

- one topic per finding
- the sources as `path:Lx-Ly@<commit>` (code) or URL (lib)
- the decisive lines verbatim
- what they establish

## 3. Write

Launch `spec-workflow-mcp:spec-author` with `DOC: evidence` and the findings. It writes:

- `.spec-workflow/specs/<spec>/evidence/EV-<category>-<NNN>.md`, one topic each, following `templates/docs/evidence.md`
- `evidence/manifest.md`, following `templates/docs/manifest.md`, with `status: ready`

## 4. Next

There is no approval gate. Continue directly with `/spec-requirements <spec>`.
