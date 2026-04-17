# Spec Workflow Adapter

Use `assistant-adapters/shared/spec-workflow-core.md` as the canonical workflow definition.

If your client supports reusable commands, prompts, or rules, map these capability names to your local workflow actions:

- `spec-request-spec`
- `spec-requirements`
- `spec-design`
- `spec-test-design`
- `spec-tasks`
- `spec-implement`
- `check-approval`

If your client does not support named commands, follow the phase instructions manually while still using the `approvals` MCP tool and the shared dashboard.
