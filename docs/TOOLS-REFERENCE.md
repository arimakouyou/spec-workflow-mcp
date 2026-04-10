# Tools Reference

Complete documentation for all MCP interfaces provided by Spec Workflow MCP.

## Overview

Spec Workflow MCP provides specialized interfaces for structured software development, accessible through the Model Context Protocol.

### Architecture Note

MCP defines two interface types — **Tools** and **Prompts** — plus the plugin system provides **Skills**:

| Interface | Description | Registration |
|-----------|-------------|-------------|
| **MCP Tool** | AI が直接呼び出す操作（副作用あり） | `src/tools/index.ts` — `approvals` のみ |
| **MCP Prompt** | AI にワークフロー指示を提供するテンプレート | `src/prompts/index.ts` — 7 prompts |
| **Plugin Skill** | Claude Code プラグインのスラッシュコマンド | `.claude-plugin/skills/` — 30+ skills |

**登録済み MCP Tool**: `approvals`（承認リクエスト・ステータス確認・削除を `action` パラメータで切替）

**登録済み MCP Prompts**: `create-spec`, `create-steering-doc`, `implement-task`, `spec-status`, `inject-spec-workflow-guide`, `inject-steering-guide`, `refresh-tasks`

> **Note**: このドキュメントでは概念的な操作を「ツール」として説明していますが、
> 実装上は MCP Prompt として提供されているものがあります（AI が `prompts/get` で取得し指示に従って動作）。
> プラグインとして使用する場合、対応するスキル（`/spec-requirements`, `/spec-design` 等）が
> これらの操作をより高レベルでオーケストレートします。

## Interface Categories

1. **Workflow Guides** - Documentation and guidance (MCP Prompts)
2. **Spec Management** - Create and manage specifications (MCP Prompts)
3. **Context Tools** - Retrieve project information (MCP Prompts)
4. **Steering Tools** - Project-level guidance (MCP Prompts)
5. **Approval Tools** - Document approval workflow (MCP Tool: `approvals`)

## Workflow Guide Tools

### spec-workflow-guide

**Purpose**: Provides comprehensive guidance for the spec-driven workflow process.

**Parameters**: None

**Returns**: Markdown guide explaining the complete workflow

**Usage Example**:
```
"Show me the spec workflow guide"
```

**Response Contains**:
- Workflow overview
- Step-by-step process
- Best practices
- Example prompts

### steering-guide

**Purpose**: Guide for creating project steering documents.

**Parameters**: None

**Returns**: Markdown guide for steering document creation

**Usage Example**:
```
"Show me how to create steering documents"
```

**Response Contains**:
- Steering document types
- Creation process
- Content guidelines
- Examples

## Spec Management Tools

### create-spec

**Purpose**: Creates or updates specification documents (requirements, design, test-design, tasks). MCP Prompt として登録されている。

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| specName | string | Yes | Name of the spec (kebab-case) |
| docType | string | Yes | Type: "requirements", "design", "test-design", or "tasks" |
| content | string | Yes | Markdown content of the document |
| revision | boolean | No | Whether this is a revision (default: false) |

**Usage Example**:
```typescript
{
  specName: "user-authentication",
  docType: "requirements",
  content: "# User Authentication Requirements\n\n## Overview\n...",
  revision: false
}
```

**Returns**:
```typescript
{
  success: true,
  message: "Requirements document created successfully",
  path: ".spec-workflow/specs/user-authentication/requirements.md",
  requestedApproval: true
}
```

**Notes**:
- Creates spec directory if it doesn't exist
- Automatically requests approval for new documents
- Validates markdown format
- Preserves existing documents when creating new types

### spec-list (概念的操作)

> **Architecture Note**: この操作は独立した MCP Tool/Prompt としては存在しない。
> `spec-status` prompt または `/spec-implement` スキルのコンテキスト内で同等の機能が提供される。

**Purpose**: Lists all specifications with their current status.

**Parameters**: None

**Returns**: Array of spec summaries

**Response Structure**:
```typescript
[
  {
    name: "user-authentication",
    status: "in-progress",
    progress: 45,
    documents: {
      requirements: "approved",
      design: "pending-approval",
      testDesign: "not-created",
      tasks: "not-created"
    },
    taskStats: {
      total: 15,
      completed: 7,
      inProgress: 1,
      pending: 7
    }
  }
]
```

**Usage Example**:
```
"List all my specs"
```

### spec-status

**Purpose**: Gets detailed status information for a specific spec.

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| specName | string | Yes | Name of the spec to check |

**Returns**: Detailed spec status

**Response Structure**:
```typescript
{
  exists: true,
  name: "user-authentication",
  documents: {
    requirements: {
      exists: true,
      approved: true,
      lastModified: "2024-01-15T10:30:00Z",
      size: 4523
    },
    design: {
      exists: true,
      approved: false,
      pendingApproval: true,
      lastModified: "2024-01-15T14:20:00Z",
      size: 6234
    },
    testDesign: {
      exists: false,
      approved: false,
      lastModified: null,
      size: 0
    },
    tasks: {
      exists: true,
      taskCount: 15,
      completedCount: 7,
      inProgressCount: 1,
      progress: 45
    }
  },
  overallProgress: 45,
  currentPhase: "implementation"
}
```

**Usage Example**:
```
"Show me the status of user-authentication spec"
```

### manage-tasks (概念的操作)

> **Architecture Note**: この操作は独立した MCP Tool としては存在しない。
> タスク管理は `refresh-tasks` prompt と `/spec-implement` スキルで処理される。

**Purpose**: Comprehensive task management including updates, status changes, and progress tracking.

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| specName | string | Yes | Name of the spec |
| action | string | Yes | Action: "update", "complete", "list", "progress" |
| taskId | string | Sometimes | Task ID (required for update/complete) |
| status | string | No | New status: "pending", "in-progress", "completed" |
| notes | string | No | Additional notes for the task |

**Actions**:

1. **Update Task Status**:
```typescript
{
  specName: "user-auth",
  action: "update",
  taskId: "1.2.1",
  status: "in-progress",
  notes: "Started implementation"
}
```

2. **Complete Task**:
```typescript
{
  specName: "user-auth",
  action: "complete",
  taskId: "1.2.1"
}
```

3. **List Tasks**:
```typescript
{
  specName: "user-auth",
  action: "list"
}
```

4. **Get Progress**:
```typescript
{
  specName: "user-auth",
  action: "progress"
}
```

**Returns**: Task information or update confirmation

## Context Tools

### get-template-context (概念的操作)

> **Architecture Note**: この操作は独立した MCP Tool としては存在しない。
> テンプレートは `create-spec` prompt が内部的にロードする。

**Purpose**: Retrieves markdown templates for all document types.

**Parameters**: None

**Returns**: Object containing all templates

**Response Structure**:
```typescript
{
  requirements: "# Requirements Template\n\n## Overview\n...",
  design: "# Design Template\n\n## Architecture\n...",
  tasks: "# Tasks Template\n\n## Implementation Tasks\n...",
  product: "# Product Steering Template\n...",
  tech: "# Technical Steering Template\n...",
  structure: "# Structure Steering Template\n..."
}
```

**Usage Example**:
```
"Get all document templates"
```

### get-steering-context (概念的操作)

> **Architecture Note**: この操作は独立した MCP Tool としては存在しない。
> ステアリングコンテキストは `inject-steering-guide` prompt で提供される。

**Purpose**: Retrieves project steering documents and guidance.

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| docType | string | No | Specific doc: "product", "tech", "structure", or "all" |

**Returns**: Steering document content

**Usage Example**:
```typescript
{
  docType: "tech"  // Returns only technical steering
}
```

**Response Structure**:
```typescript
{
  product: "# Product Steering\n\n## Vision\n...",
  tech: "# Technical Steering\n\n## Architecture\n...",
  structure: "# Structure Steering\n\n## Organization\n..."
}
```

### get-spec-context (概念的操作)

> **Architecture Note**: この操作は独立した MCP Tool としては存在しない。
> スペックコンテキストは `spec-status` prompt で取得できる。

**Purpose**: Retrieves complete context for a specific spec.

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| specName | string | Yes | Name of the spec |
| includeContent | boolean | No | Include document content (default: true) |

**Returns**: Complete spec context

**Response Structure**:
```typescript
{
  name: "user-authentication",
  exists: true,
  documents: {
    requirements: {
      exists: true,
      content: "# Requirements\n\n...",
      approved: true
    },
    design: {
      exists: true,
      content: "# Design\n\n...",
      approved: false
    },
    testDesign: {
      exists: false,
      content: null,
      approved: false
    },
    tasks: {
      exists: true,
      content: "# Tasks\n\n...",
      stats: {
        total: 15,
        completed: 7,
        progress: 45
      }
    }
  },
  relatedSpecs: ["user-profile", "session-management"],
  dependencies: ["database-setup", "auth-library"]
}
```

**Usage Example**:
```
"Get full context for user-authentication spec"
```

## Steering Document Tools

### create-steering-doc

**Purpose**: Creates project steering documents (product, tech, structure).

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| docType | string | Yes | Type: "product", "tech", or "structure" |
| content | string | Yes | Markdown content of the document |

**Usage Example**:
```typescript
{
  docType: "product",
  content: "# Product Steering\n\n## Vision\nBuild the best..."
}
```

**Returns**:
```typescript
{
  success: true,
  message: "Product steering document created",
  path: ".spec-workflow/steering/product.md"
}
```

**Notes**:
- Creates steering directory if needed
- Overwrites existing steering documents
- No approval required for steering docs
- Should be created before specs

## Approval System Tools

### approvals

**Purpose**: ダッシュボードインターフェースを通じた承認リクエストの管理。

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| action | string | Yes | 操作: "request", "status", "delete" |
| title | string | Yes (request) | 承認対象の簡潔なタイトル |
| filePath | string | Yes (request) | プロジェクトルートからの相対パス（content は渡さない） |
| type | string | Yes (request) | "document" または "action" |
| category | string | Yes (request) | 承認カテゴリ: "spec" または "steering" |
| categoryName | string | Yes (request) | スペック名（例: "user-auth"）、steering の場合は "steering" |
| approvalId | string | Yes (status/delete) | 承認リクエストの ID |
| projectPath | string | No | プロジェクトルートの絶対パス |

**重要**: `filePath` のみを指定し、ドキュメント内容 (`content`) は渡さないこと（ダッシュボードがファイルを直接読み取る）。

**Usage Example**:
```typescript
{
  action: "request",
  title: "User Authentication Requirements",
  filePath: ".spec-workflow/specs/user-auth/requirements.md",
  type: "document",
  category: "spec",
  categoryName: "user-auth"
}
```

**Returns**:
```typescript
{
  success: true,
  approvalId: "...",
  message: "Approval requested. Check dashboard to review."
}
```

### get-approval-status

**Purpose**: Checks the approval status of a document.

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| specName | string | Yes | Name of the spec |
| documentId | string | Yes | Document ID to check |

**Returns**:
```typescript
{
  exists: true,
  status: "pending" | "approved" | "rejected" | "changes-requested",
  feedback: "Please add more detail about error handling",
  timestamp: "2024-01-15T10:30:00Z",
  reviewer: "user"
}
```

**Usage Example**:
```
"Check approval status for user-auth requirements"
```

### delete-approval

**Purpose**: Removes completed, rejected, or needs-revision approval requests to clean up the approval queue. Cannot delete pending approvals.

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| specName | string | Yes | Name of the spec |
| documentId | string | Yes | Document ID to remove |

**Returns**:
```typescript
{
  success: true,
  message: "Approval record deleted"
}
```

**Usage Example**:
```
"Clean up completed approvals for user-auth"
```

## Tool Integration Patterns

### Sequential Workflow

Interfaces are designed to work in sequence:

**Plugin Skills (recommended)**:
1. `/steering-doc` → Create project steering documents
2. `/spec-request-spec` → Phase 0: Define scope and tech stack
3. `/spec-requirements` → Phase 1: Create requirements
4. `/spec-design` → Phase 2: Technical design
5. `/spec-test-design` → Phase 3: Test design
6. `/spec-tasks` → Phase 4: Break down into tasks
7. `/spec-implement` → Phase 5: Implementation

**Manual MCP (without plugin)**:
1. `inject-steering-guide` prompt → Learn about steering
2. `create-steering-doc` prompt → Create steering documents
3. `inject-spec-workflow-guide` prompt → Learn workflow
4. `create-spec` prompt → Create spec documents
5. `approvals` tool (action: request) → Request review
6. `approvals` tool (action: status) → Check approval status
7. `implement-task` prompt → Get implementation guidance
8. `spec-status` prompt → Track progress

### Parallel Operations

Some tools can be used simultaneously:

- `spec-list` + `spec-status` → Get overview and details
- `get-spec-context` + `get-steering-context` → Full project context
- Multiple `create-spec-doc` → Create multiple specs

### Error Handling

All tools return consistent error structures:

```typescript
{
  success: false,
  error: "Spec not found",
  details: "No spec named 'invalid-spec' exists",
  suggestion: "Use spec-list to see available specs"
}
```

## Best Practices

### Tool Selection

1. **Information Gathering**:
   - Use `spec-list` for overview
   - Use `spec-status` for specific spec
   - Use `get-spec-context` for implementation

2. **Document Creation**:
   - Always create requirements first
   - Wait for approval before design
   - Create test design after design approval
   - Create tasks after test design approval

3. **Task Management**:
   - Update status when starting tasks
   - Mark complete immediately after finishing
   - Use notes for important context

### Performance Considerations

- **Batch Operations**: Request multiple specs in one conversation
- **Caching**: Tools cache file reads for performance
- **Selective Loading**: Use `includeContent: false` for faster status checks

### Security

- **Path Validation**: All paths are validated and sanitized
- **Project Isolation**: Tools only access project directory
- **Input Sanitization**: Markdown content is sanitized
- **No Execution**: Tools never execute code

## Extending Tools

### Custom Tool Development

To add new tools:

1. Create tool module in `src/tools/`
2. Define parameters schema
3. Implement handler function
4. Register with MCP server
5. Add to exports

Example structure:
```typescript
export const customTool = {
  name: 'custom-tool',
  description: 'Description',
  parameters: {
    // JSON Schema
  },
  handler: async (params) => {
    // Implementation
  }
};
```

## Tool Versioning

Tools maintain backward compatibility:

- Parameter additions are optional
- Response structures extend, not replace
- Deprecated features show warnings
- Migration guides provided

## Related Documentation

- [User Guide](USER-GUIDE.md) - Using tools effectively
- [Workflow Process](WORKFLOW.md) - Tool usage in workflow
- [Prompting Guide](PROMPTING-GUIDE.md) - Example tool usage
- [Development Guide](DEVELOPMENT.md) - Adding new tools