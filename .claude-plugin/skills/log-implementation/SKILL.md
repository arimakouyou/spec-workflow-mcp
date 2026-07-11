---
name: log-implementation
description: "Append the completion sections (Summary, Statistics, Files, Artifacts, Review Process) to the per-task log after task implementation completes. Required: specName, taskId, summary, filesModified, filesCreated, statistics, artifacts (apiEndpoints / components / functions / classes / integrations). Always invoke before marking a task as [x]. Triggers on: '/log-implementation invocation', 'implementation logging', 'task completion log', '実装ログ記録', 'タスク完了ログ'."
---

# Log Implementation — Task-completion sections of the task log

After task implementation completes, this skill **appends the completion sections** (`## Summary`, `## Statistics`, `## Files Modified`, `## Files Created`, `## Artifacts`, `## Review Process`) to the per-task log. The task log itself (`## Metadata` + `## Events`) is created and maintained by `parallel-worker` and `review-worker` during the task; this skill writes the structured completion record at the end.

See `${CLAUDE_PLUGIN_ROOT}/rules/task-log-format.md` for the full format spec (TL3 = structure, TL5 = completion sections).

## Division of Responsibility with the Hook

This skill, as the "primary feature," generates a detailed completion record that includes artifacts. The `log-implementation.sh` hook auto-generates only a skeleton at Stop time as a **safety net** (summary=`(auto-logged)`, empty artifacts). Information is richer when this skill is explicitly invoked.

- **Skill (primary)**: the LLM judges semantic information and fills in artifacts — detailed completion record
- **Hook (safety net)**: auto-generates a skeleton — minimum record when the skill is forgotten

## Critical Rule

**Always run this skill before marking a task as `[x]`.** When this skill is explicitly invoked, the hook respects the existing completion sections and skips (no overwrite).

## Inputs

Collect the following information before appending the completion sections:

| Field | Required | Description |
|------|:---:|------|
| specName | Yes | Spec name (kebab-case) |
| taskId | Yes | Task ID (e.g., "1", "1.2", "3.1.4") — used verbatim in the file path, no sanitization |
| summary | Yes | Implementation summary (one line) |
| filesModified | Yes | List of modified files |
| filesCreated | Yes | List of created files |
| statistics | Yes | `linesAdded` and `linesRemoved` |
| artifacts | Yes | Structured data (see below) |
| reviewProcess | No | Review quality metrics |

### artifacts Structure

```yaml
apiEndpoints:     # API endpoints created/modified
  - method: GET/POST/PUT/DELETE
    path: /api/...
    purpose: ...            # Purpose / role of this endpoint
    location: path/to/file  # Source file where it is implemented
    requestFormat: ...      # (optional) Main request format
    responseFormat: ...     # (optional) Main response format
components:       # UI components created
  - name: ...
    type: ...               # Type of component (page, widget, etc.)
    purpose: ...            # Purpose / role of the component
    location: path/to/file  # Source file where it is implemented
    props: ...              # (optional) Major properties
    exports: [...]          # (optional) Exported names
functions:        # Utility functions created
  - name: ...
    purpose: ...            # Purpose / role of the function
    location: path/to/file  # Source file where it is implemented
    signature: ...          # (optional) Function signature
    isExported: true/false  # Whether it is part of the module's public API
classes:          # Classes created
  - name: ...
    purpose: ...            # Purpose / role of the class
    location: path/to/file  # Source file where it is implemented
    methods: [...]          # (optional) Major method names
    isExported: true/false  # Whether it is part of the module's public API
integrations:     # Frontend-backend integration patterns
  - description: ...          # Purpose / use case of the integration
    frontendComponent: ...    # Related UI component name/path
    backendEndpoint: ...      # Related API endpoint (method + path)
    dataFlow: ...             # How data flows between which APIs/components
```

### reviewProcess Structure (optional)

```yaml
reworkCount: 0      # Number of reworks (0 = passed first review)
reviewOutcome: commit  # commit | escalated
findings:           # Only when reworkCount > 0
  - attempt: 1
    categories: [...]
    summary: ...
    action: rework | commit | escalate
```

`reviewProcess` data can be derived from the task log's `review-worker:cycle-*` and `parallel-worker:rework-*` events. When you have all of them in the events, prefer deriving over re-asking the user.

## Procedure

### 1. Task Existence Check

Read `.spec-workflow/specs/{specName}/tasks.md` and verify that `{taskId}` exists.

### 2. Locate the Task Log

**Path**: `.spec-workflow/specs/{specName}/task-logs/{taskId}.log.md`

The file should already exist (created by `parallel-worker` at task start). If it does not exist (rare — e.g., manual task without running an impl-worker), create it first with the standard header per `${CLAUDE_PLUGIN_ROOT}/rules/task-log-format.md` TL3.

### 3. Append Completion Sections

Append the following sections to the end of the task log. Do NOT modify any existing `## Metadata` or `## Events` content.

````markdown

## Summary

{summary}

## Statistics

- Lines Added: +{linesAdded}
- Lines Removed: -{linesRemoved}
- Files Changed: {filesModified.length + filesCreated.length}
- Net Change: {linesAdded - linesRemoved}

## Files Modified
{Each line as `- path/to/file` for filesModified. If empty, write `_No files modified_`}

## Files Created
{Each line as `- path/to/file` for filesCreated. If empty, write `_No files created_`}

## Artifacts

{If artifacts is empty, write `_No artifacts recorded_`}

### API Endpoints
{Each endpoint in the following format. Omit the section entirely if there are none:}
#### {method} {path}
- **Purpose:** {purpose}
- **Location:** {location}
- **Request Format:** {requestFormat}  <- optional
- **Response Format:** {responseFormat}  <- optional

### Components
{Each component:}
#### {name}
- **Type:** {type}
- **Purpose:** {purpose}
- **Location:** {location}

### Functions
{Each function:}
#### {name}
- **Purpose:** {purpose}
- **Location:** {location}
- **Exported:** Yes/No

### Classes
{Each class:}
#### {name}
- **Purpose:** {purpose}
- **Location:** {location}
- **Exported:** Yes/No

### Integrations
{Each integration:}
#### Integration
- **Description:** {description}
- **Frontend Component:** {frontendComponent}
- **Backend Endpoint:** {backendEndpoint}
- **Data Flow:** {dataFlow}

## Review Process

```json
{"reworkCount": N, "reviewOutcome": "commit", "findings": [...]}
```
````

> **Note**: the `## Review Process` section must contain **only** the JSON block (no explanatory text — the parser uses JSON.parse).

### 4. Confirm Completion

Confirm the sections were appended successfully and report to the user.

## Idempotency

If the task log already contains a `## Summary` section (i.e., this skill ran before), do not append a second set of completion sections. Instead, report that the task log already has completion sections and exit without re-writing. The hook honors this check by skipping when `## Summary` is present.
