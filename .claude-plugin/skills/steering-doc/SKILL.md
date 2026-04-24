---
name: steering-doc
description: "Create project-level steering documents (product.md, tech.md, structure.md) that define vision, technology stack, and codebase conventions. Use this skill when the user wants to set up steering docs, define project direction, or establish project-level guidance before starting specs. Triggers on: 'create steering document', 'steering doc', 'ステアリングドキュメント', 'setup project guidance', 'define project vision', 'define tech stack', 'project structure doc', 'product vision', or any request to create steering/*.md documents."
---

# Steering Document Creation

Create project-level guidance documents that inform all future spec-driven development. Steering documents are created in sequence: **product.md → tech.md → structure.md**.

## When to Use

- Starting a new project and establishing direction
- Documenting an existing project's vision, tech stack, and structure
- Before beginning the first spec (steering docs feed into Phase 0: Request Spec)

## Document Types

| Document | Purpose | Output Path |
|----------|---------|-------------|
| **product.md** | Vision, goals, target users, success metrics | `.spec-workflow/steering/product.md` |
| **tech.md** | Project-level technology stack and architecture | `.spec-workflow/steering/tech.md` |
| **structure.md** | Codebase organization, naming conventions, patterns | `.spec-workflow/steering/structure.md` |

## Inputs

Ask the user which steering document(s) they want to create. If they say "all" or "steering documents", create all three in sequence.

If a specific `docType` is provided (product, tech, or structure), create only that one.

## Process

### 1. Check Existing State

Check which steering documents already exist:
```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

If a document already exists, inform the user and ask whether to overwrite or skip.

### 2. Create Each Document in Sequence

For each document to create, follow this process:

#### Step A: Load the Template

Check for a custom template first. If none exists, fall back to the default:

1. `.spec-workflow/user-templates/{docType}-template.md` (custom)
2. `.spec-workflow/templates/{docType}-template.md` (default)

Follow the template structure exactly for consistency.

#### Step B: Research and Write

**For product.md:**
- Discuss with the user to understand the product vision and goals
- Define target users, key features, and success metrics
- Establish product principles that guide decisions
- If web search is available, research market context

**For tech.md:**
- Analyze the existing codebase to detect technology stack (package.json, Cargo.toml, etc.)
- Document programming languages, frameworks, and key libraries
- Record architectural patterns and decisions
- Technology selection rationale and decision history go to `.spec-workflow/steering/logs/tech-decisions.md`, not in tech.md itself

**For structure.md:**
- Analyze the actual directory structure and file organization
- Document naming conventions, import patterns, and code structure
- Define module boundaries and code organization principles
- Include dashboard/monitoring structure if applicable

#### Step C: Create the Document

Write the file to:
```
.spec-workflow/steering/{docType}.md
```

#### Step D: Self-Review via Subagent (before approval)

Validate the document in **2 stages** before requesting approval.

**fix (automated mechanical corrections):**

Auto-fix placeholders, formatting, and typos. Do not add or change content:

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Fix steering doc (auto-fix)",
  prompt: "You are a spec document reviewer. Auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/steering/{docType}.md

    Document type: steering ({docType})

    Auto-fix targets (you may directly modify the file):
    - Remove placeholder text ([describe...], [e.g., ...], TODO, TBD)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Fix obvious typos

    Not auto-fix targets (report as issues only):
    - Adding or removing sections
    - Adding or changing content

    Mode: fix — Return a structured report (auto-fixed items + remaining issues)."
})
```

**check (content validation):**

After fix is complete, detect content issues. Do not modify the file:

```
Agent({
  subagent_type: "general-purpose",
  model: "opus",
  description: "Review steering doc (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/steering/{docType}.md

    Document type: steering ({docType})
    Template: {project-path}/.spec-workflow/templates/{docType}-template.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no placeholders)
    2. SPECIFICITY: Content must be specific to this project, not generic boilerplate
    3. COMPLETENESS: All tables must have concrete entries, not placeholder rows
    4. ACTIONABILITY: Guidance must be clear enough to inform future spec development

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

#### Step E: Approval Workflow

This is a strict, automated process. Verbal approval from the user is never accepted — only dashboard or VS Code extension approval counts.

1. **Request approval**: Use the `approvals` MCP tool with `action: 'request'`. Pass `filePath` only — never include content in the request. Save the returned `approvalId`.

2. **Automatic polling**: Start approval polling (Bash script with 60-minute timeout):
   ```
   /check-approval <approvalId>
   ```
   The polling script will automatically check approval status and handle the result:
   - **approved**: Cleanup is performed automatically
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval
   - **timeout**: Reported to user, can re-run to resume

3. **Handle needs-revision** (if polling ends with needs-revision):
   - Read the reviewer's comments, update the document accordingly
   - Re-run the review subagent (fix + check)
   - Submit a NEW approval request and run `/check-approval <newApprovalId>`

4. **Next document**: After approval and cleanup succeed, proceed to the next document in sequence (product → tech → structure). If this was the last document, inform the user that steering docs are complete.

### 3. Completion

After all requested steering documents are approved:
- Inform the user: "Steering documents are complete. These will be referenced automatically during spec creation phases."
- If the user wants to start spec development, suggest: "Ready to create a spec? Use `/spec-request-spec` to begin Phase 0."

### 4. CLAUDE.md 整備ガイダンス（P1-02 対応）

> **P1-02**: harness-maturity-check チェックリスト P1（コンテキストエンジニアリング）の項目 P1-02
> 「エージェント向けの指示ファイルが整備されている」に対応するステップ。

steering doc 作成完了後、プロジェクトルートの `CLAUDE.md`（または `.cursorrules`, `.github/copilot-instructions.md` 等のエージェント向け指示ファイル）の状態を確認する。

**チェック項目:**

1. **存在確認**: プロジェクトルートにエージェント向け指示ファイルが存在するか
2. **簡潔さ**: 100行以下を目安とし、詳細は別ファイルへのポインタにする
3. **ポインタ設計**: 具体的なルールやパターンは `.claude-plugin/rules/` や steering doc への参照で構成する

**推奨構成例:**

```markdown
# CLAUDE.md

## プロジェクト概要
{1-2行の概要。詳細は .spec-workflow/steering/product.md を参照}

## アーキテクチャ
{1-2行の構成概要。詳細は .spec-workflow/steering/structure.md を参照}

## 技術スタック
{主要技術の列挙。詳細は .spec-workflow/steering/tech.md を参照}

## コーディングルール
- ルール一覧: `.claude-plugin/rules/` ディレクトリ直下
- スタイル: `.claude-plugin/rules/rust-style.md`
- セキュリティ: `.claude-plugin/rules/security.md`

## ワークフロー
- spec-workflow によるスペック駆動開発を採用
- 実装前に必ず設計承認を取得すること
```

CLAUDE.md が未作成の場合は上記の構成をユーザーに提案する。既存の場合は簡潔さとポインタ設計を確認し、改善を提案する。

## Rules

- Create documents in sequence: product.md → tech.md → structure.md
- Check for custom templates in `.spec-workflow/user-templates/` first
- Follow exact template structures
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before next document
- tech.md: selection rationale goes to `.spec-workflow/steering/logs/tech-decisions.md`
- When the user requests the full steering-doc set, complete documents in the specified sequence (no skipping); users may still request or update individual documents directly.
