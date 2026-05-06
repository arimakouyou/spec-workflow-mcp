# Type Safety Guidelines

Defines type checking settings and type-safe coding patterns for the project.

## Rust Type Safety

While Rust provides strong type safety at the compiler level, the following patterns further enhance safety.

### TS-R1: Newtype Pattern

Use newtypes for domain-specific values to prevent type confusion:

```rust
// NG: Using raw types directly
fn get_user(id: i64) -> User { ... }
fn get_order(id: i64) -> Order { ... }
// get_user(order_id) is compilable — dangerous

// OK: Distinguished by newtypes
struct UserId(i64);
struct OrderId(i64);
fn get_user(id: UserId) -> User { ... }
fn get_order(id: OrderId) -> Order { ... }
// get_user(order_id) causes a compile error
```

Applies to: Domain values such as IDs, amounts, email addresses, etc.

### TS-R2: Safe Numeric Casting

Casting with `as` carries risks of precision loss or overflow:

```rust
// NG: Implicit truncation
let x: i64 = 300;
let y: i8 = x as i8; // 44 — silent overflow

// OK: Explicit conversion
let y: i8 = x.try_into().map_err(|_| AppError::Overflow)?;
```

`as` is only permitted when safety is guaranteed, such as `usize` ↔ pointer conversions.

### TS-R3: Exhaustive Pattern Matching

`match` must always cover all patterns, and the `_ =>` wildcard should be avoided:

```rust
// NG: Does not trigger compile error when a new variant is added
match status {
    Status::Active => { ... },
    _ => { ... },  // New variants implicitly fall into here
}

// OK: Explicitly list all variants
match status {
    Status::Active => { ... },
    Status::Inactive => { ... },
    Status::Suspended => { ... },
}
```

Exception: `#[non_exhaustive]` enums from external crates require `_ =>`.

### TS-R4: Safe Handling of Option/Result

```rust
// NG: Risk of panic
let value = map.get("key").unwrap();

// OK: Error handling
let value = map.get("key").ok_or(AppError::NotFound("key"))?;

// OK: Default value
let value = map.get("key").unwrap_or(&default);
```

`unwrap()` is permitted only in test code. In production code, use the `?` operator, `unwrap_or`, or `unwrap_or_else`.

### TS-R5: Type-Level State Management via PhantomData

Express state transitions through types to prevent invalid state transitions at compile time:

```rust
struct Draft;
struct Published;

struct Article<State> {
    title: String,
    body: String,
    _state: std::marker::PhantomData<State>,
}

impl Article<Draft> {
    fn publish(self) -> Article<Published> { ... }
}
// Article<Published> does not have publish() — prevents double publication
```

## C# Type Safety

C# provides strong type safety through the .NET type system and Nullable Reference Types (NRT). The following patterns further enhance safety.

### TS-C1: Nullable Reference Types (NRT)

Enable NRT project-wide to verify null safety at the compiler level:

```xml
<!-- Directory.Build.props -->
<PropertyGroup>
  <Nullable>enable</Nullable>
</PropertyGroup>
```

```csharp
// NG: Using null-forgiving operator in production code
var user = repository.FindById(id)!;

// OK: Explicit null check
var user = await repository.FindByIdAsync(id)
    ?? throw new NotFoundException($"User {id} not found");

// OK: Explicitly using nullable types
public async Task<User?> FindByIdAsync(UserId id);
```

The `!` null-forgiving operator is permitted only in test code. In production code, use `??`, `?.`, and `??=`.

### TS-C2: Strong Typing (readonly record struct)

Use `readonly record struct` for domain-specific values to prevent type confusion:

```csharp
// NG: Using raw types directly
public User GetUser(int id) { ... }
public Order GetOrder(int id) { ... }
// GetUser(orderId) is compilable — dangerous

// OK: Distinguished by readonly record struct
public readonly record struct UserId(int Value);
public readonly record struct OrderId(int Value);
public User GetUser(UserId id) { ... }
public Order GetOrder(OrderId id) { ... }
// GetUser(orderId) causes a compile error
```

Applies to: Domain values such as IDs, amounts, email addresses, etc.

### TS-C3: Exhaustive Pattern Matching (switch expression)

Switch expressions must cover all patterns, and the `_` wildcard should be avoided:

```csharp
// NG: Does not trigger compiler warning when a new variant is added
var message = status switch
{
    Status.Active => "Active",
    _ => "Unknown",  // New variants implicitly fall into here
};

// OK: Explicitly list all variants
var message = status switch
{
    Status.Active => "Active",
    Status.Inactive => "Inactive",
    Status.Suspended => "Suspended",
};
// Triggers compiler warning CS8509 when a new variant is added
```

Use in conjunction with `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` to turn coverage gaps into build errors.

### TS-C4: Result Pattern

Use the Result pattern instead of exceptions for expected errors:

```csharp
// NG: Using exceptions for business errors
public User CreateUser(CreateUserRequest req)
{
    if (string.IsNullOrEmpty(req.Name))
        throw new ValidationException("Name is required");
    // ...
}

// OK: Expressed via OneOf / custom Result
public OneOf<User, ValidationError> CreateUser(CreateUserRequest req)
{
    if (string.IsNullOrEmpty(req.Name))
        return new ValidationError("Name is required");
    // ...
    return user;
}
```

Exceptions should only be used for truly exceptional situations (e.g., network failure, DB connection loss).

### TS-C5: Immutability Defaults

Aim for immutability by default, and allow mutability only when necessary:

```csharp
// OK: Using record for immutable data types
public record UserResponse(string Name, string Email, DateTime CreatedAt);

// OK: Using init-only properties
public class AppConfig
{
    public required string DatabaseUrl { get; init; }
    public required int Port { get; init; }
}

// OK: Using readonly collections
public IReadOnlyList<User> GetUsers() => users.AsReadOnly();
```

Utilize `record`, `init`, `required`, `IReadOnlyList<T>`, and `IReadOnlyDictionary<K,V>`.

## TypeScript Type Safety (Future Support)

The following settings are mandatory for TypeScript projects:

### TS-T1: tsconfig.json Strict Mode

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "exactOptionalPropertyTypes": true
  }
}
```

### TS-T2: Ban 'any'

The use of `any` is prohibited in principle. If unavoidable, use `unknown` + type guards:

```typescript
// NG
function parse(data: any): User { ... }

// OK
function parse(data: unknown): User {
  if (!isUser(data)) throw new ValidationError();
  return data;
}
```

## Integration with review-worker

The `review-worker` verifies the following in Category B (Design and Structure):

### Rust
- TS-R1: Are newtypes used for domain values?
- TS-R2: Is there a legitimate reason for `as` casting?
- TS-R3: Does `match` avoid the `_ =>` wildcard?
- TS-R4: Is `unwrap()` avoided in production code?

### C#
- TS-C1: Is NRT enabled and is the `!` null-forgiving operator avoided in production code?
- TS-C2: Are readonly record structs used for domain values?
- TS-C3: Is the switch expression exhaustive (avoiding the `_` wildcard)?
- TS-C4: Is the Result pattern used for business errors?
- TS-C5: Are immutability defaults (record, init, IReadOnlyList) used?

## Enforcement Levels

| Rule | Current Enforcement Level | Target |
|------|---------------------------|------|
| TS-R1 (Newtype) | L1 Documentation | L2 AI Review |
| TS-R2 (Safe Casting) | L3 CI (`clippy::cast_possible_truncation`) | L3 Maintain |
| TS-R3 (Exhaustive match) | L5 Compiler (`#[deny(unreachable_patterns)]`) | L5 Maintain |
| TS-R4 (Ban unwrap) | L3 CI (`clippy::unwrap_used` / `clippy::expect_used` / `clippy::panic`; exclude tests via `clippy.toml`) | L3 Maintain |
| TS-R5 (PhantomData) | L1 Documentation | L2 AI Review |
| TS-C1 (Enable NRT) | L5 Compiler (`<Nullable>enable</Nullable>`) | L5 Maintain |
| TS-C2 (Strong Typing) | L1 Documentation | L2 AI Review |
| TS-C3 (Exhaustive switch) | L3 CI (CS8509 + TreatWarningsAsErrors) | L3 Maintain |
| TS-C4 (Result Pattern) | L1 Documentation | L2 AI Review |
| TS-C5 (Immutability) | L1 Documentation | L2 AI Review |
```