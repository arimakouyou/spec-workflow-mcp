# Project Structure

> This document captures **project-specific structural instance information**.
> General coding policies (separation of concerns, dependency direction, naming, import order, code organization,
> module boundaries, documentation standards) are authoritative in `.claude-plugin/rules/`. Do not duplicate them here.
> Record only the concrete shape of **this** project.
> Placeholder format: `{{FIELD_NAME}}` marks required values; `[example: ...]` shows illustrative samples only.

## Directory Organization

Actual top-level directory layout of this project. If the layout follows `.claude-plugin/rules/project-architecture.md`
verbatim, record `Status: Follows project-architecture.md` and list only deviations. Otherwise document the full tree.

```
{{PROJECT_ROOT}}/
├── {{dir}}/                 # {{one_line_purpose}}
├── {{dir}}/                 # {{one_line_purpose}}
└── {{dir}}/                 # {{one_line_purpose}}
```

### Deviations from Standard Architecture

| Path | Standard Location (per rules/) | Reason for Deviation |
|------|--------------------------------|----------------------|
| {{path}} | {{expected_location}} | {{why}} |

Record `Status: N/A — no deviations` if the project matches the standard layout.

## File Placement Rules

Rules for placing newly added files. Define target directory and naming convention per file type so that developers and
AI agents can determine placement unambiguously.

| File Type | Target Directory | Naming Convention | Example |
|-----------|------------------|-------------------|---------|
| {{e.g., Handler / Controller}} | {{e.g., src/handlers/}} | {{e.g., snake_case.rs}} | {{e.g., user_handler.rs}} |
| {{e.g., Service / Business Logic}} | {{e.g., src/services/}} | {{e.g., snake_case.rs}} | {{e.g., auth_service.rs}} |
| {{e.g., Data Model}} | {{e.g., src/models/}} | {{e.g., snake_case.rs}} | {{e.g., user.rs}} |
| {{e.g., Unit Test}} | {{e.g., alongside source}} | {{e.g., *_test.rs / *.test.ts}} | {{e.g., user_test.rs}} |
| {{e.g., Integration Test}} | {{e.g., tests/}} | {{e.g., test_*.rs / *.test.ts}} | {{e.g., test_api.rs}} |
| {{e.g., E2E Test}} | {{e.g., e2e/ or tests/e2e/}} | {{e.g., *.spec.ts}} | {{e.g., login.spec.ts}} |
| {{e.g., CI Workflow}} | {{e.g., .github/workflows/}} | {{e.g., kebab-case.yml}} | {{e.g., ci.yml}} |
| {{e.g., Documentation}} | {{e.g., docs/}} | {{e.g., kebab-case.md}} | {{e.g., api-guide.md}} |
| {{e.g., Configuration}} | {{e.g., config/}} | {{e.g., kebab-case.toml}} | {{e.g., database.toml}} |
| {{e.g., Utility Script}} | {{e.g., scripts/}} | {{e.g., kebab-case.{sh,js}}} | {{e.g., seed-db.sh}} |

> **P4-01 Compliance**: When this table is filled in, the target directory for a new file is uniquely determined.
> Add or modify rows to match project-specific patterns.

## Project-Specific Conventions

Conventions that **extend or override** `.claude-plugin/rules/*-style.md` for this project only. If no project-specific
additions exist, keep `Status: N/A — follows .claude-plugin/rules/*-style.md`.

| Convention | Applies To | Rule |
|------------|------------|------|
| {{convention_name}} | {{scope}} | {{specific_rule}} |

Status: {{N/A — follows .claude-plugin/rules/*-style.md | custom conventions listed above}}

## See Also

General policies enforced project-wide (authoritative location: `.claude-plugin/rules/`):

- `rules/design-principles.md` — separation of concerns, dependency direction, public API minimization, DRY, naming appropriateness
- `rules/project-architecture.md` — baseline directory structure for Rust / .NET backends
- `rules/rust-style.md` / `rules/csharp-style.md` — language-specific naming, formatting, import order
- `rules/doc-crossref.md` / `rules/doc-freshness.md` — documentation standards
