---
always_apply: true
---

# Security Coding Standards

Security standards to apply during code reviews and implementation. Based on OWASP Top 10, including authentication and authorization.

## A1: Injection

- SQL: Build queries through an ORM query builder (e.g., Diesel). Do not embed external input into raw SQL via string concatenation
- Command injection: Do not pass user input directly to `Command::new()` or `exec`-style calls. Pass arguments individually using `.arg()`
- Path traversal: When including user input in file paths, validate against directory traversal (`../`)

## A2: Broken Authentication

- Apply authentication middleware to endpoints that require authentication (e.g., `route_layer`)
- Do not store passwords in plain text. Use hash functions such as bcrypt / argon2
- Generate session tokens / JWT using cryptographically secure random values
- Set token expiration and reject expired tokens

## A3: Broken Access Control

- Implement owner checks for resource access (users may only view/update their own data)
- IDOR (Insecure Direct Object Reference): Do not grant access based solely on the ID in path parameters. Validate the association with the authenticated user
- When role-based authorization is needed, centralize it in middleware or guard functions
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

- Configure allowed origins explicitly for CORS (`CorsLayer::permissive()` is for development only)
- Validate Content-Type and reject requests with unexpected formats

## A7: Mass Assignment

- When converting DTO → Model, ensure that fields the client should not be able to update (`id`, `created_at`, `role`, etc.) are not modified
- When using `AsChangeset`, explicitly specify the fields to be updated

## A8: Rate Limiting

- Design rate limiting for public endpoints (login, registration, password reset)
- Consider lockout after repeated failures as a brute-force protection measure

## A9: Dependency Vulnerabilities

- Regularly check for known vulnerabilities using `cargo audit`
- Remove unused dependencies

## A10: Logging and Monitoring

- Log authentication failures, authorization failures, and validation errors
- Include sufficient context in logs (request ID, user ID)
- However, mask sensitive information (see A4)
