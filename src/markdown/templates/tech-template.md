# Technology Stack

> This document captures **technology-level instance information** for this project.
> General engineering policies (error handling, type safety, security, API validation, testing, build caches) are
> authoritative in `.claude-plugin/rules/`. Do not duplicate them here. Record only what **this** project chose.
> Placeholder format: `{{FIELD_NAME}}` marks required values; `[example: ...]` shows illustrative samples only.

## Project Type

{{PROJECT_TYPE}} — e.g., web application, CLI tool, desktop app, mobile app, library, API service, embedded system.

## Core Technologies

### Primary Language(s)

| Language | Runtime / Compiler | Language Toolchain |
|----------|--------------------|--------------------|
| {{language_version}} | {{runtime_or_compiler}} | {{package_manager_build_tool}} |

### Key Dependencies / Libraries

| Library / Framework | Version | Purpose |
|---------------------|---------|---------|
| {{name}} | {{semver_or_tag}} | {{why_used}} |
| {{name}} | {{semver_or_tag}} | {{why_used}} |

### Application Architecture

{{ARCHITECTURE_SUMMARY}} — one paragraph. If the project follows
`.claude-plugin/rules/project-architecture.md` verbatim, state `Follows project-architecture.md ({{rust|dotnet}} profile)`
and describe only deviations below.

| Deviation | Reason |
|-----------|--------|
| {{deviation}} | {{why}} |

Status: {{Follows project-architecture.md | deviations listed above}}

### Data Storage

| Concern | Technology |
|---------|------------|
| Primary Storage | {{e.g., PostgreSQL 15, SQLite, S3}} |
| Caching | {{e.g., Redis, Valkey, in-memory}} |
| Data Formats | {{e.g., JSON, Protocol Buffers, XML}} |

### External Integrations

| System | Protocol | Authentication |
|--------|----------|----------------|
| {{system_name}} | {{e.g., HTTP/REST, gRPC, WebSocket}} | {{e.g., OAuth2, API key, mTLS}} |

## External Dependencies (Approved)

Third-party dependencies that have been reviewed and approved for use in this project. New dependencies must be added
here **before** being introduced into the codebase.

| Name | Version | Purpose | License | Approved On | Approved By |
|------|---------|---------|---------|-------------|-------------|
| {{name}} | {{semver}} | {{why_used}} | {{spdx_id}} | {{YYYY-MM-DD}} | {{approver}} |

## Development Environment

### Build & Development Tools

| Concern | Tool |
|---------|------|
| Build System | {{e.g., cargo, dotnet, npm scripts}} |
| Package Management | {{e.g., cargo, NuGet, npm, pnpm}} |
| Development Workflow | {{e.g., hot reload, watch mode, REPL}} |

### Code Quality Tools

| Concern | Tool |
|---------|------|
| Static Analysis | {{e.g., clippy, Roslyn analyzers, ESLint}} |
| Formatting | {{e.g., rustfmt, dotnet format, Prettier}} |
| Testing Framework | {{e.g., cargo test, xUnit, Jest}} |
| Documentation Generation | {{e.g., rustdoc, DocFX, TypeDoc}} |

### Version Control & Collaboration

| Concern | Value |
|---------|-------|
| VCS | {{e.g., Git}} |
| Branching Strategy | {{e.g., GitHub Flow, Git Flow, trunk-based}} |
| Code Review | {{e.g., required approvals, CODEOWNERS scope}} |

## Deployment & Distribution

| Concern | Value |
|---------|-------|
| Target Platform(s) | {{e.g., Linux x86_64, Windows, Kubernetes}} |
| Distribution Method | {{e.g., container image, npm package, installer}} |
| Installation Requirements | {{e.g., .NET 8 runtime, glibc 2.28+}} |
| Update Mechanism | {{e.g., package manager pull, auto-update service}} |

## Technical Requirements & Constraints

### Performance

| Metric | Target |
|--------|--------|
| {{e.g., p95 request latency}} | {{e.g., < 200 ms}} |
| {{e.g., startup time}} | {{e.g., < 2 s}} |

### Compatibility

| Concern | Constraint |
|---------|------------|
| Platform Support | {{e.g., Linux, macOS, Windows; x86_64 + arm64}} |
| Dependency Versions | {{e.g., PostgreSQL >= 14, Node.js >= 20}} |
| Standards Compliance | {{e.g., OpenAPI 3.1, OAuth 2.1}} |

### Security

| Concern | Value |
|---------|-------|
| Authentication | {{e.g., OIDC, API key}} |
| Encryption | {{e.g., TLS 1.3, AES-256 at rest}} |
| Compliance Standards | {{e.g., GDPR, SOC 2, N/A}} |

Detailed security policies live in `.claude-plugin/rules/security.md`. Record only project-specific additions above.

### Scalability & Reliability

| Concern | Value |
|---------|-------|
| Expected Load | {{e.g., 1k req/s peak, 50 GB/day}} |
| Availability Target | {{e.g., 99.9% monthly}} |
| Growth Projection | {{e.g., 2x traffic in 12 months}} |

## Architecture Decision Records

Summary of significant architectural decisions. Full records live in `.claude/_docs/adr/` (managed by the `/adr` skill).
Add a new ADR with `/adr <title>`.

If this project has no ADRs yet, record `Status: N/A — no ADRs yet`. Once ADRs exist, replace the status line with
the summary table below and keep it in sync with `.claude/_docs/adr/INDEX.md`.

Status: {{N/A — no ADRs yet | see summary table below}}

| ADR | Title | Status | Date | Supersedes |
|-----|-------|--------|------|------------|
| [ADR-NNNN](.claude/_docs/adr/NNNN-{{slug}}.md) | {{title}} | {{Proposed\|Accepted\|Deprecated\|Superseded}} | {{YYYY-MM-DD}} | {{—\|ADR-NNNN}} |

> Status values: Proposed, Accepted, Deprecated, Superseded.

## Technical Decisions

Entry point into decision records for this project.

- **Formal decisions** → Architecture Decision Records above (canonical source: `.claude/_docs/adr/INDEX.md`).
- **Lightweight chronological changelog** → `.spec-workflow/steering/logs/tech-decisions.md` (one-line "what changed on
  YYYY-MM-DD, link to ADR-NNNN if formalized").

## Known Limitations

High-level summary of current technical debt and limitations. Detailed entries are managed under
`.claude/_docs/tech-debt/INDEX.md` (P5-02). Create individual debt entries with `/tech-debt add`.

| Area | Impact | Tech-Debt Entry |
|------|--------|-----------------|
| {{area}} | {{user_or_dev_impact}} | {{TD-NNNN or link}} |

## See Also

General engineering policies enforced project-wide (authoritative location: `.claude-plugin/rules/`):

- `rules/design-principles.md` — architectural taste invariants (D1–D6)
- `rules/project-architecture.md` — baseline architecture per language profile
- `rules/security.md` / `rules/type-safety.md` / `rules/api-validation.md` — horizontal policies
- `rules/error-message-guidelines.md` — error formatting
- `rules/regression-test-policy.md` / `rules/flaky-test-management.md` — testing discipline
- `rules/doc-freshness.md` / `rules/doc-crossref.md` — documentation discipline
