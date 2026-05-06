---
name: spec-archive
description: "Move a completed spec from `.spec-workflow/specs/{name}/` to `.spec-workflow/archive/specs/{name}/` after implementation is finished (Final E2E Gate PASS + PR created). The spec remains visible in the dashboard's Archived tab and can be restored via unarchive. Triggers on: '/spec-archive', 'archive spec', 'spec implementation complete and archive', or automatic invocation at the end of /spec-implement."
---

# Spec Archive — Archive a Completed Spec

Move a spec whose implementation is complete from the active directory to the archive directory. The archive path matches the MCP-side `SpecArchiveService`, so **the spec stays visible in the dashboard's Archived tab and can be returned to active via the unarchive button**.

## When to Use

- Right after the Final E2E Gate of `/spec-implement` passes and the PR has been created (auto-invoked by the Orchestrator)
- When you want to manually clean an already-completed spec out of the active list

## When NOT to Use

- Specs whose implementation is in progress, FAILED, or under user escalation (keep them in active)
- Specs already archived from the dashboard (rejected by the duplicate check)

## Inputs

- **spec name** (kebab-case, required)

## Process

### 1. Resolve Paths

```bash
PROJECT_DIR="$(pwd)"
ACTIVE_PATH="${PROJECT_DIR}/.spec-workflow/specs/{spec-name}"
ARCHIVE_ROOT="${PROJECT_DIR}/.spec-workflow/archive/specs"
ARCHIVE_PATH="${ARCHIVE_ROOT}/{spec-name}"
```

> Same path convention as `PathUtils.getArchiveSpecPath` in archive-service.ts (`src/core/archive-service.ts`).
> It also matches the dashboard API's archive endpoint, so the Active / Archived tabs stay consistent.

### 2. Preconditions

Verify the following before running. If any check is false, abort and report to the user:

| Check | Condition | Failure Message |
|---------|-----|------------------|
| active exists | `ACTIVE_PATH` exists as a directory | `Spec '{spec-name}' not found in active specs` |
| archive target free | `ARCHIVE_PATH` does not exist | `Spec '{spec-name}' already exists in archive — unarchive it first or rename the active spec` |

### 3. Run Archive

```bash
mkdir -p "$ARCHIVE_ROOT"
mv "$ACTIVE_PATH" "$ARCHIVE_PATH"
```

If `mv` fails, report to the user (permissions, cross-filesystem move, disk full, etc.).

### 4. Move Session File (optional)

If a `.implement-session.json` produced during the implementation session remains, move it to the archive as well:

```bash
if [ -f "${PROJECT_DIR}/.implement-session.json" ]; then
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-manage.sh" archive
fi
```

Destination: `.spec-workflow/archive/sessions/implement-session-{timestamp}.json`.

### 5. Completion Report

Tell the user:

```text
Spec '{spec-name}' archived successfully.
  From: .spec-workflow/specs/{spec-name}/
  To:   .spec-workflow/archive/specs/{spec-name}/

You can still view it in the dashboard's "Archived" tab.
To return it to active, use the unarchive button in the dashboard.
```

## Rules

- The destination path is fixed at `.spec-workflow/archive/specs/{spec-name}/` (same as archive-service.ts)
- Not idempotent for already-archived specs — report the duplicate to the user and abort
- Use `mv` rather than copy + delete (for atomicity and to preserve permissions)
- On failure, leave the active side untouched (do not create a partial state)
- This skill itself does not call the dashboard API — filesystem operations only (works even if the dashboard is not running)
- Unarchive is delegated to the MCP server's `SpecArchiveService.unarchiveSpec` or the
  dashboard's unarchive button (this skill handles archive direction only)
