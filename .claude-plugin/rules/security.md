---
always_apply: true
---

# Security Coding Standards

Security standards to apply during code reviews and implementation. Based on OWASP Top 10, including authentication and authorization.

## A1: Injection

- SQL: Build queries through an ORM query builder (e.g., Diesel, Entity Framework Core). Do not embed external input into raw SQL via string concatenation
  - **Rust**: Diesel query builder ensures parameterization at compile time
  - **C#/.NET**: EF Core LINQ queries are parameterized. Use `FromSqlInterpolated` (not `FromSqlRaw` with string concatenation) for raw SQL
- Command injection: Do not pass user input directly to `Command::new()` / `Process.Start()`. Pass arguments individually
- Path traversal: When including user input in file paths, validate against directory traversal (`../`)

## A2: Broken Authentication

- Apply authentication middleware to endpoints that require authentication
  - **Rust**: `route_layer` / tower middleware
  - **C#/.NET**: `app.UseAuthentication()` + `app.UseAuthorization()` middleware pipeline, `[Authorize]` attribute
- Do not store passwords in plain text. Use hash functions such as bcrypt / argon2
- Generate session tokens / JWT using cryptographically secure random values
- Set token expiration and reject expired tokens

## A3: Broken Access Control

- Implement owner checks for resource access (users may only view/update their own data)
- IDOR (Insecure Direct Object Reference): Do not grant access based solely on the ID in path parameters. Validate the association with the authenticated user
- When role-based authorization is needed, centralize it in middleware or guard functions
  - **C#/.NET**: Use policy-based authorization (`builder.Services.AddAuthorizationBuilder().AddPolicy(...)`) with `[Authorize(Policy = "...")]`
- Verify that admin-only endpoints are inaccessible to regular users

## A4: Sensitive Data Exposure

- Do not include password hashes, internal IDs, stack traces, or DB error details in responses
- Explicitly define response types using DTOs; do not return Model objects directly
- Do not output sensitive information (passwords, tokens, personal data) to logs
- In production, use generic error messages that do not allow clients to infer internal implementation details

## A5: Input Validation

- Validate all input from request bodies, path parameters, and query parameters
- Set upper limits on string length (to prevent DoS)
- Return 400 Bad Request for type conversion errors (e.g., string → number)
- Use dedicated libraries for format validation of email addresses, URLs, dates, etc.

## A6: Security Headers and CORS

- Configure allowed origins explicitly for CORS
  - **Rust**: `CorsLayer::permissive()` is for development only
  - **C#/.NET**: `builder.Services.AddCors(options => options.AddPolicy(...))` — avoid `AllowAnyOrigin()` in production
- Validate Content-Type and reject requests with unexpected formats

## A7: Mass Assignment

- When converting DTO → Model, ensure that fields the client should not be able to update (`id`, `created_at`, `role`, etc.) are not modified
  - **Rust**: When using `AsChangeset`, explicitly specify the fields to be updated
  - **C#/.NET**: Use separate request DTOs (not entity classes) for model binding. Map only intended fields

## A8: Rate Limiting

- Design rate limiting for public endpoints (login, registration, password reset)
- Consider lockout after repeated failures as a brute-force protection measure

## A9: Dependency Vulnerabilities

- **Vulnerability scanning**:
  - **Rust**: Run `cargo audit` to check against the RustSec Advisory Database
  - **C#/.NET**: Run `dotnet list package --vulnerable --include-transitive` to check NuGet dependencies
  - Both are integrated as **blocking** quality checks — see `.claude-plugin/rules/quality-checks.md`
- **Unused dependency detection**:
  - **Rust**: `cargo +nightly udeps` for unused dependencies in `Cargo.toml`
  - **C#/.NET**: `Snitch` for redundant direct references, `Meziantou.Analyzer` for unused usings
  - Fewer dependencies reduce the attack surface
- When vulnerabilities are reported:
  1. Check if a patched version exists and update the manifest
  2. If no patch exists, evaluate the severity and whether the vulnerable code path is reachable
  3. Document accepted risks in comments if a vulnerable dependency cannot be removed
- Review lockfile/manifest changes during code review to catch unexpected dependency additions

## A10: Logging and Monitoring

- Log authentication failures, authorization failures, and validation errors
- Include sufficient context in logs (request ID, user ID)
- However, mask sensitive information (see A4)
