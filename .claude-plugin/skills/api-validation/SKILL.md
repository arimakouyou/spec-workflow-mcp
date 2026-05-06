---
name: api-validation
description: |
  API request validation conventions (Rust + C#). Rust (serde): AV-R1 `deny_unknown_fields`, AV-R2 type-level validation (Axum Extractor), AV-R3 business validation (service layer), AV-R4 Enum validation (`rename_all`), AV-R5 explicit Optional. C# (ASP.NET Core): AV-C1 `[ApiController]` + Model Validation, AV-C2 Data Annotations + FluentValidation, AV-C3 `UnmappedMemberHandling.Disallow`, AV-C4 `JsonStringEnumConverter`, AV-C5 `required` + nullability. Use when implementing API endpoints, designing DTOs, deciding the responsibility split between validation layers, or running the review-worker Security category. Triggers on: 'API validation', 'request validation', 'DTO validation', 'APIバリデーション', 'リクエストバリデーション'.
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# API Validation Schema

Define API request validation strictly to ensure rejection of unknown fields and schema consistency.

## Targets

- API endpoint implementation (Axum / ASP.NET Core)
- Request DTO design
- Responsibility split between type validation and business validation
- Allowed-value design for Enum fields
- Type-level expression of required vs. optional fields
- Application of the review-worker Security category

## Out of Scope

- HTTP response design -> `axum` / `aspnet-core` Skill
- DB layer validation -> `diesel` / `entity-framework-core` Skill
- Frontend validation -> `leptos` / `blazor` Skill

## Basic Principles

1. **Reject unknown fields**: request DTOs must not accept undefined fields
2. **Layered validation**: type validation -> business validation in two stages
3. **Consistent error responses**: conform to the Error Handling table in design.md

## Rust (Serde) Validation Patterns

### AV-R1: deny_unknown_fields

Apply `#[serde(deny_unknown_fields)]` to every request DTO:

```rust
// OK: rejects unknown fields
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CreateUserRequest {
    /// User name (2-50 characters)
    name: String,
    /// Email address
    email: String,
}

// NG: no deny_unknown_fields — arbitrary fields are silently dropped
#[derive(Deserialize)]
struct CreateUserRequest {
    name: String,
    email: String,
}
```

> **Note**: Do not apply `deny_unknown_fields` to response DTOs (new fields may be added during API versioning).

### AV-R2: Type-Level Validation

Run type validation at the extractor level (Axum pattern):

```rust
// Axum: the Json extractor validates during deserialization
async fn create_user(
    Json(payload): Json<CreateUserRequest>,  // type mismatch -> automatic 400
) -> Result<Json<UserResponse>, AppError> {
    // payload is type-safe by the time we reach here
    service.create_user(payload).await
}
```

### AV-R3: Business Validation

Run business-rule validation in the service layer:

```rust
impl UserService {
    fn validate_create(&self, req: &CreateUserRequest) -> Result<(), AppError> {
        if req.name.len() < 2 || req.name.len() > 50 {
            return Err(AppError::BadRequest("name must be 2-50 chars"));
        }
        if !req.email.contains('@') {
            return Err(AppError::BadRequest("invalid email format"));
        }
        Ok(())
    }
}
```

### AV-R4: Enum Validation

Use `#[serde(rename_all = "snake_case")]` for string-to-Enum conversion and reject undefined values:

```rust
#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum UserRole {
    Admin,
    Editor,
    Viewer,
}
// "admin" -> OK, "superadmin" -> deserialization error (400)
```

### AV-R5: Explicit Optional Fields

Express required vs. optional fields explicitly in the type:

```rust
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct UpdateUserRequest {
    /// Specify only when updating
    name: Option<String>,
    /// Specify only when updating
    email: Option<String>,
}
```

Fields without `Option<T>` are required. Missing required fields in the request -> 400 error.

## C# (ASP.NET Core) Validation Patterns

### AV-C1: [ApiController] + Model Validation

Enable automatic model validation with the `[ApiController]` attribute:

```csharp
// OK: [ApiController] enables automatic ModelState validation + ProblemDetails responses
[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> CreateUser(CreateUserRequest request)
    {
        // request has already been validated against ModelState by the time we reach here
        var user = await _service.CreateUserAsync(request);
        return CreatedAtAction(nameof(GetUser), new { id = user.Id }, user);
    }
}
```

For Minimal API, use `[AsParameters]` or manual validation:

```csharp
app.MapPost("/users", async ([FromBody] CreateUserRequest request, IValidator<CreateUserRequest> validator) =>
{
    var result = validator.Validate(request);
    if (!result.IsValid)
        return Results.ValidationProblem(result.ToDictionary());
    // ...
});
```

### AV-C2: Data Annotations + FluentValidation

Separate type-level validation (Data Annotations) from business rules (FluentValidation):

```csharp
// Data Annotations: type-level constraints
public class CreateUserRequest
{
    [Required]
    [StringLength(50, MinimumLength = 2)]
    public required string Name { get; init; }

    [Required]
    [EmailAddress]
    public required string Email { get; init; }
}

// FluentValidation: business rules
public class CreateUserRequestValidator : AbstractValidator<CreateUserRequest>
{
    public CreateUserRequestValidator(IUserRepository repository)
    {
        RuleFor(x => x.Email)
            .MustAsync(async (email, ct) => !await repository.ExistsAsync(email, ct))
            .WithMessage("Email already registered");
    }
}
```

### AV-C3: Reject Unknown Fields

ASP.NET Core ignores unknown JSON properties by default. To reject them, configure `JsonSerializerOptions`:

```csharp
// Program.cs
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow;
});
```

> **Note**: Do not apply this to response DTOs. Request DTOs only.

### AV-C4: Enum Validation

Use `JsonStringEnumConverter` for JSON-string-to-Enum conversion and reject undefined values:

```csharp
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum UserRole
{
    Admin,
    Editor,
    Viewer,
}
// "Admin" -> OK, "SuperAdmin" -> deserialization error (400)
```

### AV-C5: Explicit Required / Optional

Express required vs. optional explicitly using the `required` keyword and nullability:

```csharp
public class UpdateUserRequest
{
    /// Specify only when updating
    public string? Name { get; init; }

    /// Specify only when updating
    public string? Email { get; init; }
}

public class CreateUserRequest
{
    /// Required (required + non-nullable)
    public required string Name { get; init; }

    /// Required
    public required string Email { get; init; }
}
```

`required` + non-nullable = required. `nullable (?)` = optional.

## Validation Error Response

The error response format conforms to the Error Handling section in design.md:

```json
{
  "error": {
    "code": "BadRequest",
    "message": "Validation failed: name must be 2-50 characters"
  }
}
```

| Error type | HTTP Status | Origin |
|------------|-------------|--------|
| Type mismatch (JSON parse error) | 400 | Extractor (automatic) |
| Unknown field | 400 | serde deny_unknown_fields (automatic) |
| Business rule violation | 400 | Service layer (manual) |
| Authentication failure | 401 | Authentication middleware |
| Authorization failure | 403 | Authorization middleware |

## Integration with spec-design

When defining DTOs in the design.md Data Models section, document:

- Required / optional for each field
- Length limits for string fields
- Allowed values for Enum fields
- Rust: target of `deny_unknown_fields` (request DTOs)
- C#: target of `UnmappedMemberHandling.Disallow` (request DTOs)

## Integration with review-worker

In review-worker category C (Security), verify:

### Rust

- AV-R1: request DTOs carry `deny_unknown_fields`
- AV-R3: business validation runs in the service layer
- AV-R5: required / optional fields are expressed in the type

### C#

- AV-C1: `[ApiController]` or a validator is applied
- AV-C2: type constraints and business rules are separated (Data Annotations + FluentValidation)
- AV-C3: unknown fields are rejected on request DTOs
- AV-C5: required / optional is explicit via `required` / nullable

## Enforcement Level

| Rule | Current enforcement | Target |
|------|---------------------|--------|
| AV-R1 (deny_unknown_fields) | L1 documentation | L4 structural test (verifiable via architecture tests) |
| AV-R2 (type-level validation) | L5 type system (Axum Extractor) | maintain L5 |
| AV-R3 (business validation) | L2 AI review | maintain L2 |
| AV-R4 (Enum validation) | L5 type system (serde) | maintain L5 |
| AV-R5 (explicit Optional) | L5 type system (Rust Option) | maintain L5 |
| AV-C1 (ApiController auto-validation) | L5 framework (ASP.NET Core) | maintain L5 |
| AV-C2 (FluentValidation) | L2 AI review | L3 CI (validator-registration test) |
| AV-C3 (reject unknown fields) | L1 documentation | L4 structural test |
| AV-C4 (Enum validation) | L5 type system (JsonStringEnumConverter) | maintain L5 |
| AV-C5 (Required/Optional explicit) | L5 type system (required + NRT) | maintain L5 |

## Related Rules / Skills

- Universal constraints: `security` (A1-A10), `type-safety` (TS-R1-R5, TS-C1-C5), `design-principles`, `enforcement-levels` (L1-L5)
- Related Skills: `axum` (Rust Extractor), `aspnet-core` (`[ApiController]` / Minimal API), `spec-design` (DTO schema definition)
