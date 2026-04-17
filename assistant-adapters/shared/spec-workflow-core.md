# Spec Workflow Core

Use this workflow when guiding spec-driven development with Spec Workflow MCP.

## Core Principles

- Execute phases in order: `spec-request-spec` -> `spec-requirements` -> `spec-design` -> `spec-test-design` -> `spec-tasks` -> `spec-implement`
- Work on one spec at a time
- Use kebab-case for spec names
- Never skip approval checkpoints
- Never accept verbal approval; approval must come from the dashboard or the VS Code extension
- Do not move to the next phase until approval cleanup succeeds

## Files

- Specs live in `.spec-workflow/specs/{spec-name}/`
- Steering docs live in `.spec-workflow/steering/`
- Templates load from `.spec-workflow/user-templates/` first, then `.spec-workflow/templates/`

## Approval Flow

1. Create or update the phase document.
2. Call the `approvals` MCP tool with `action: "request"` and `filePath` only.
3. Poll the approval until it reaches a terminal state.
4. If approved, call `approvals` with `action: "delete"` before proceeding.
5. If revision or rejection is returned, update the document, request a new approval, and poll again.

## Phase Capability Names

- `spec-request-spec`
- `spec-requirements`
- `spec-design`
- `spec-test-design`
- `spec-tasks`
- `spec-implement`
- `check-approval`

Expose these names through whatever your client supports: slash commands, saved prompts, reusable instructions, command palettes, or agent templates.
