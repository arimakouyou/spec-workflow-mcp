---
name: context7
description: |
  Guideline for using the Context7 MCP to fetch **up-to-date documentation** for libraries, frameworks, and external tools before implementation, before configuration, and when handling errors. Do not rely on stale memory-based knowledge or old Stack Overflow answers; consult the official docs via Context7 MCP before writing or fixing code. Use it when calling library APIs, writing config files (tsconfig, vite, eslint, etc.), resolving library/tool-induced errors, and verifying CLI options. Triggers on: 'context7', 'fetch latest docs', 'library documentation', 'check API usage', '最新ドキュメント取得', 'ライブラリのドキュメント参照'.
allowed-tools: [Read, Edit, Write, Bash, Grep]
---

# Context7 MCP Usage Skill

## In Scope

- New implementation that calls library / framework APIs
- Writing config files (`tsconfig.json`, `vite.config.ts`, `eslint.config.mjs`, `pyproject.toml`, etc.)
- Verifying arguments and configuration for CLI tools (webpack, rollup, esbuild, etc.)
- Resolving library-induced errors (including version differences)

## Out of Scope

- Internal project code design and refactoring (outside Context7's responsibility)
- Non-public internal tools / APIs (Context7 has no docs for them)

## Key Points

### 1. When Using Libraries

Before writing code that calls a library's API, fetch the latest documentation and code samples for that library via the Context7 MCP. Don't write based on stale usage patterns from memory; follow the current usage that Context7 returns.

```text
(Bad)
When calling React's useState, write it the way you remember from memory.

(Good)
Search "react hooks useState" via Context7 MCP → confirm the latest usage → implement.
```

### 2. External Tool Configuration and Syntax

When writing config files or specifying CLI options, confirm the correct option and format via Context7 MCP first. Don't write based on guesswork.

### 3. When Handling Errors

When a library-/tool-induced error occurs, look up the remedy via Context7 MCP and apply a fix grounded in the official documentation. Avoid fixes based on old Stack Overflow answers or memory-derived guesses.

## Common Pitfalls

1. **Starting because "I already know it"**: The library version may have changed and the API along with it. Always check Context7
2. **Skipping Context7 after an error**: Context7 is the fastest and most accurate first thing to try
3. **Old patterns in config files**: Migration-bearing changes such as eslint flat config, vite v5, and new tsconfig options should be verified against the latest via Context7

## Project-Specific Conventions

- In projects where Context7 MCP is registered in the plugin's `.claude-plugin/.mcp.json`, prefer this skill
- If Context7 does not have docs for the library in question, fetch from the official docs site via WebFetch

## Related Rules / Skills

- Related Skill: `spec-design` (consult Context7 when selecting libraries during the design phase)
- Technology-specific Skills like `axum` / `diesel` / `leptos`: explicitly suggest Context7 search queries for that technology

## References

- Context7: <https://context7.com/>
- Model Context Protocol: <https://modelcontextprotocol.io/>
