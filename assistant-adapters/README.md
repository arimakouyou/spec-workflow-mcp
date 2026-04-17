# Assistant Adapters

This package ships a tool-neutral workflow core plus thin adapters for instruction-driven assistants.

## Layout

- `shared/spec-workflow-core.md` - canonical workflow instructions that are safe to reuse across tools
- `codex/AGENTS.md` - ready-to-copy Codex adapter
- `generic/SYSTEM.md` - generic instruction bundle for tools that support a persistent system prompt, rules file, or workspace instructions

## Recommended Usage

1. Configure the MCP server in your client.
2. Start the shared dashboard with `spec-workflow-mcp --dashboard`.
3. Import the adapter that matches your client.
4. Reuse the phase capability names consistently:
   - `spec-request-spec`
   - `spec-requirements`
   - `spec-design`
   - `spec-test-design`
   - `spec-tasks`
   - `spec-implement`
   - `check-approval`

Claude Code users should continue using the `.claude-plugin/` distribution. Other tools can use the adapters in this directory without depending on Claude-specific plugin packaging.
