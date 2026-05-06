---
name: log-implementation
description: "Record a structured Markdown implementation log after task implementation completes. Required: specName, taskId, summary, filesModified, filesCreated, statistics, artifacts (apiEndpoints / components / functions / classes / integrations). Always invoke before marking a task as [x]. Triggers on: '/log-implementation invocation', 'implementation logging', 'task completion log', '実装ログ記録', 'タスク完了ログ'."
---

# Log Implementation — Structured Implementation Logging

After task implementation completes, **record the implementation as a structured Markdown file**. This Skill is responsible for the detailed log including semantic information about artifacts (API endpoints / components / functions / classes / integration patterns).

## Division of Responsibility with the Hook

This skill, as the "primary feature," generates a detailed log that includes artifacts. The `log-implementation.sh` hook auto-generates only a skeleton at Stop time as a **safety net** (summary=`(auto-logged)`, empty artifacts). Information is richer when this skill is explicitly invoked.

- **Skill (primary)**: the LLM judges semantic information and fills in artifacts — detailed implementation log
- **Hook (safety net)**: auto-generates a skeleton — minimum record when the skill is forgotten

## Critical Rule

**Always run this skill before marking a task as `[x]`.** When this skill is explicitly invoked, the hook respects the existing log and skips (no overwrite).

## Inputs

Collect the following information before creating the log:

| Field | Required | Description |
|------|:---:|------|
| specName | Yes | Spec name (kebab-case) |
| taskId | Yes | Task ID (e.g., "1", "1.2", "3.1.4") |
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

## Procedure

### 1. Task Existence Check

Read `.spec-workflow/specs/{specName}/tasks.md` and verify that `{taskId}` exists.

### 2. Create Log File

**Path**: `.spec-workflow/specs/{specName}/Implementation Logs/task-{sanitizedTaskId}_{timestamp}_{idPrefix}.md`
- `sanitizedTaskId`: replace `.` and `/` in `taskId` with `-` (e.g., `3.1.4` -> `3-1-4`)
- `timestamp`: ISO format with separators stripped (e.g., `20260326T133000`). In Bash: `date -u +%Y%m%dT%H%M%S`
- `idPrefix`: first 8 characters of the Log ID (UUID)

**Create the directory if it does not exist.**

**File format** (compatible with the dashboard's `ImplementationLogManager` parser):

````markdown
# Implementation Log: Task {taskId}

**Summary:** {summary}

**Timestamp:** {ISO 8601 format, e.g., 2026-03-26T13:30:00.000Z}
**Log ID:** {Unique ID in UUID format. Generate in Bash with `uuidgen` or `cat /proc/sys/kernel/random/uuid`}

---

## Statistics

- **Lines Added:** +{linesAdded}
- **Lines Removed:** -{linesRemoved}
- **Files Changed:** {filesModified.length + filesCreated.length}
- **Net Change:** {linesAdded - linesRemoved}

## Files Modified
{Each line as `- path/to/file` for filesModified. If empty, write `_No files modified_`}

## Files Created
{Each line as `- path/to/file` for filesCreated. If empty, write `_No files created_`}

---

## Artifacts

{If artifacts is empty, write `_No artifacts recorded_`}

### API Endpoints
{Each endpoint in the following format:}
#### {method} {path}
- **Purpose:** {purpose}
- **Location:** {location}
- **Request Format:** {requestFormat}  <- optional
- **Response Format:** {responseFormat}  <- optional

### Components
{Each component in the following format:}
#### {name}
- **Type:** {type}
- **Purpose:** {purpose}
- **Location:** {location}

### Functions
{Each function in the following format:}
#### {name}
- **Purpose:** {purpose}
- **Location:** {location}
- **Exported:** Yes/No

### Classes
{Each class in the following format:}
#### {name}
- **Purpose:** {purpose}
- **Location:** {location}
- **Exported:** Yes/No

### Integrations
{Each integration in the following format:}
#### Integration
- **Description:** {description}
- **Frontend Component:** {frontendComponent}
- **Backend Endpoint:** {backendEndpoint}
- **Data Flow:** {dataFlow}

---

## Review Process

When reworkCount=0:
```json
{"reworkCount": 0, "reviewOutcome": "commit", "findings": []}
```

When reworkCount>0:
```json
{"reworkCount": 2, "reviewOutcome": "commit", "findings": [{"attempt": 1, "categories": ["naming"], "summary": "Variable name is unclear", "action": "rework"}, {"attempt": 2, "categories": [], "summary": "Fix verified", "action": "commit"}]}
```

````

> **Note**: the `## Review Process` section must contain **only** the JSON block (no explanatory text — the parser uses JSON.parse).

### 3. Confirm Creation

Confirm the file was created successfully and report to the user.
