---
name: generate-api-docs
description: >
  Auto-generate OpenAPI 3.1 documentation from source code. Parses API route definitions,
  collects handler signatures, type definitions, and doc comments, generates OpenAPI YAML,
  and offers doc comment improvement suggestions.
  Triggers on: 'generate API docs', 'OpenAPI generation', 'API documentation generation', '/generate-api-docs', 'OpenAPI生成', 'APIドキュメント生成'.
argument-hint: "[--output <path>] [--framework <axum|actix-web|express|fastify|auto>]"
user-invokable: true
---

# OpenAPI Documentation Auto-Generation

Parse the API route definitions, handlers, and type definitions in source code, and generate OpenAPI 3.1 YAML.

## Argument Parsing

| Argument | Default | Description |
|----------|---------|-------------|
| `--output <path>` | `docs/openapi.yaml` | Output path |
| `--framework <name>` | `auto` | Framework selection (`axum` / `actix-web` / `express` / `fastify` / `auto`) |

## Step 1: Framework Detection

For `--framework auto` (the default), detect in this priority order:

| Priority | Detection condition | Framework |
|----------|---------------------|-----------|
| 1 | `axum` dependency in `Cargo.toml` | Axum |
| 2 | `actix-web` dependency in `Cargo.toml` | Actix-web |
| 3 | `express` dependency in `package.json` | Express |
| 4 | `fastify` dependency in `package.json` | Fastify |

If none match, report an error and exit. Skip this step when `--framework` is specified explicitly.

## Step 2: API Route Parsing

Search source code with framework-specific patterns and collect route definitions.

### Axum

```bash
# Search Router definitions
grep -rn 'Router::new\(\)\|\.route(\|\.nest(' --include='*.rs' src/
```

Items to extract:
- `.route("/path", get(handler))` -> method: GET, path: `/path`, handler: `handler`
- `.nest("/prefix", router)` -> prefix of nested router
- `.with_state(...)` -> shared state type

### Actix-web

```bash
grep -rn '\.route(\|\.resource(\|web::\(get\|post\|put\|delete\|patch\)' --include='*.rs' src/
```

### Express / Fastify

```bash
grep -rn 'app\.\(get\|post\|put\|delete\|patch\)\|router\.\(get\|post\|put\|delete\|patch\)' --include='*.ts' --include='*.js' src/
```

For each route, record:
- HTTP method
- Path
- Handler function name
- File path and line number of the handler definition

## Step 3: Handler Analysis

For each handler function, collect:

### 3.1 Function Signature

Extract the handler function's argument types (request body) and return type (response).

**Rust (Axum) example:**
```rust
async fn create_user(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateUserRequest>,  // -> request type
) -> Result<Json<UserResponse>, AppError>    // -> response type
```

**TypeScript (Express) example:**
```typescript
async function createUser(
  req: Request<{}, {}, CreateUserBody>,  // -> request type
  res: Response<UserResponse>            // -> response type
): Promise<void>
```

### 3.2 Doc Comment Collection

Collect Rustdoc (`///`) or JSDoc (`/** */`) comments immediately above the handler function. These become the OpenAPI operation `description`.

### 3.3 Type Definition Analysis

Follow the request/response type definitions and collect each field's information:

- Field name
- Type (mapped to OpenAPI type/format)
- Doc comment (mapped to OpenAPI field `description`)
- `Option<T>` / `?` -> `required: false`
- Validation attributes (`#[validate]`, `@IsEmail()`, etc.) -> OpenAPI format/pattern

**Rust type mapping:**

| Rust type | OpenAPI type | OpenAPI format |
|-----------|--------------|----------------|
| `String` | string | — |
| `i32` / `i64` | integer | int32 / int64 |
| `f32` / `f64` | number | float / double |
| `bool` | boolean | — |
| `Uuid` | string | uuid |
| `DateTime<Utc>` / `NaiveDateTime` | string | date-time |
| `Vec<T>` | array (items: T) | — |
| `Option<T>` | T (required: false) | — |

## Step 4: OpenAPI 3.1 YAML Generation

Compose OpenAPI 3.1-compliant YAML from the collected information:

```yaml
openapi: "3.1.0"
info:
  title: "{Project name (Cargo.toml package.name or package.json name)}"
  version: "{version}"
  description: "{Cargo.toml description or package.json description}"
paths:
  /path:
    get:
      summary: "{First line of handler doc comment}"
      description: "{Full handler doc comment}"
      parameters: [...]
      responses:
        "200":
          description: "Success"
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ResponseType"
        "400": ...
        "404": ...
components:
  schemas:
    RequestType:
      type: object
      required: [field1, field2]
      properties:
        field1:
          type: string
          description: "{Field doc comment}"
```

### Error Response Mapping

If design.md has an Error Handling section, take error codes and HTTP statuses from that table and reflect them in each endpoint's responses. If absent, generate generic error responses (400, 404, 500).

### Output

Write the generated YAML to the `--output` path (default: `docs/openapi.yaml`). Create the `docs/` directory if it does not exist.

If the file already exists, show the diff and confirm with the user before overwriting.

## Step 5: Doc Comment Gap Analysis

Scan each field of the type definitions and report fields lacking doc comments:

```
## Doc Comment Improvement Suggestions

| File | Line | Type | Field | Suggestion |
|------|------|------|-------|------------|
| src/models/user.rs | 15 | UserResponse | display_name | /// Display-purpose user name |
| src/models/user.rs | 16 | UserResponse | created_at | /// Account creation timestamp (UTC) |
```

If no gaps exist, report "Doc comments are present on all fields".

## Step 6: Design.md Cross-Reference (Optional)

If `.spec-workflow/specs/*/design.md` exists, compare the design's API Design section against the generated OpenAPI:

### Diff Detection

| Diff type | Description | Action |
|-----------|-------------|--------|
| In design but not in code | Endpoint defined in design.md but not implemented | Report as warning |
| In code but not in design | Implemented but not defined in design.md | Report as warning (possible design drift) |
| Type mismatch | Request/response fields differ | Report the diff in detail |

Skip this step when design.md does not exist.

## Completion Report

```
## /generate-api-docs Completion Report

- Framework: {detected framework}
- Output: {output path}
- Endpoint count: {N}
- Schema count: {M}
- Doc comment coverage: {X}/{Y} fields ({Z}%)
- Improvement suggestions: {K} items
- Design.md diff: {present / none / skipped}
```
