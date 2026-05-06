---
name: entity-framework-core
description: |
  Entity Framework Core (.NET 10) best practices. Covers entity configuration via `IEntityTypeConfiguration<T>` (Fluent API), the `required` keyword, `DbContext.OnModelCreating` + `ApplyConfigurationsFromAssembly`, registration with `AddDbContext` / `AddDbContextPool`, read-query optimization with `AsNoTracking` / `AsSplitQuery` / `SingleOrDefaultAsync` / projection (`Select`), transactions with `BeginTransactionAsync` and `CreateExecutionStrategy`, `dotnet ef migrations` + idempotent scripts, bulk operations via `ExecuteUpdateAsync` / `ExecuteDeleteAsync`, and integration testing with Testcontainers (PostgreSql) — do not use the InMemory provider for integration tests. Reference when defining EF Core entities, optimizing queries, creating migrations, designing a DbContext, or writing integration tests. Triggers on: 'Entity Framework Core', 'EF Core', 'DbContext', 'IEntityTypeConfiguration', 'AsNoTracking', 'dotnet ef migrations', 'Testcontainers', 'EF Core エンティティ定義', 'クエリ最適化', 'マイグレーション作成', 'DbContext 設計', '統合テスト'.
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Entity Framework Core Best Practices (.NET 10)

## In Scope

- Entity definitions (Fluent API, `IEntityTypeConfiguration<T>`)
- DbContext setup and registration (`AddDbContext` / `AddDbContextPool`)
- Read-query optimization (`AsNoTracking` / `AsSplitQuery` / projection)
- Transaction boundary design (implicit / explicit / `CreateExecutionStrategy`)
- Migration creation and application (`dotnet ef migrations`)
- Bulk operations (`ExecuteUpdateAsync` / `ExecuteDeleteAsync`)
- Integration testing with Testcontainers

## Out of Scope

- ASP.NET Core DI / middleware -> `aspnet-core` Skill
- Project layout -> `csproj` Skill
- C# code style -> `csharp-style` Rule

## Project Structure

- Place `DbContext` in the `Data/` directory
- Entity models belong in `Models/`
- Use the Repository pattern with interfaces in `Repositories/`
- Fluent API configuration classes go in `Data/Configurations/`
- Migrations are auto-generated into `Data/Migrations/`

```
src/
├── Data/
│   ├── AppDbContext.cs
│   ├── Configurations/
│   │   ├── UserConfiguration.cs
│   │   └── OrderConfiguration.cs
│   └── Migrations/
│       ├── 20260401000000_InitialCreate.cs
│       └── AppDbContextModelSnapshot.cs
├── Models/
│   ├── User.cs
│   └── Order.cs
├── DTOs/
│   ├── UserDto.cs
│   └── CreateUserRequest.cs
├── Repositories/
│   ├── IUserRepository.cs
│   └── UserRepository.cs
└── ...
```

## Entity Definitions

- Use Fluent API via `IEntityTypeConfiguration<T>` over Data Annotations for all configuration
- Separate entity classes (DB models) from DTOs (API models) — never expose entities directly in API responses
- Use the `required` keyword (C# 11+) for non-nullable reference properties
- Define navigation properties for relationships; keep foreign key properties explicit

```csharp
// Models/User.cs — entity definition
public class User
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public required string Email { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    // Navigation properties
    public ICollection<Order> Orders { get; set; } = [];
}

// DTOs/UserDto.cs — for API responses
public record UserDto(int Id, string Name, string Email, DateTime CreatedAt);

// DTOs/CreateUserRequest.cs — for API requests
public record CreateUserRequest(string Name, string Email);
```

```csharp
// Data/Configurations/UserConfiguration.cs — Fluent API configuration
public class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> builder)
    {
        builder.ToTable("users");

        builder.HasKey(u => u.Id);

        builder.Property(u => u.Name)
            .IsRequired()
            .HasMaxLength(255);

        builder.Property(u => u.Email)
            .IsRequired()
            .HasMaxLength(255);

        builder.HasIndex(u => u.Email)
            .IsUnique();

        builder.Property(u => u.CreatedAt)
            .HasDefaultValueSql("NOW()");

        builder.Property(u => u.UpdatedAt)
            .HasDefaultValueSql("NOW()");

        // Relationship configuration
        builder.HasMany(u => u.Orders)
            .WithOne(o => o.User)
            .HasForeignKey(o => o.UserId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
```

## DbContext Configuration

- Register with `AddDbContext<AppDbContext>()` (Scoped lifetime by default)
- Use `UseNpgsql()` for PostgreSQL or `UseSqlServer()` for SQL Server
- Apply all `IEntityTypeConfiguration<T>` classes via `ApplyConfigurationsFromAssembly` in `OnModelCreating`
- Keep `DbContext` lean — no business logic, only data access concerns

```csharp
// Data/AppDbContext.cs
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<Order> Orders => Set<Order>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Auto-apply all IEntityTypeConfiguration classes in the same assembly
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

```csharp
// Program.cs — service registration
var builder = WebApplication.CreateBuilder(args);

// For PostgreSQL
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// For SQL Server
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));
```

## Queries

- Use `AsNoTracking()` for read-only queries to reduce memory overhead and improve performance
- Use `AsSplitQuery()` for queries with multiple `Include()` calls to avoid cartesian explosion
- Prefer `SingleOrDefaultAsync()` over `FirstOrDefaultAsync()` when expecting a unique result — it throws if duplicates exist, catching data integrity issues early
- Never call `ToListAsync()` before filtering — always compose the full query before materializing
- Use projection with `Select()` to fetch only the columns you need, avoiding over-fetching

```csharp
// Read-only query — AsNoTracking improves performance
var users = await context.Users
    .AsNoTracking()
    .Where(u => u.Name.Contains(searchTerm))
    .OrderByDescending(u => u.CreatedAt)
    .Select(u => new UserDto(u.Id, u.Name, u.Email, u.CreatedAt))
    .Skip(offset)
    .Take(limit)
    .ToListAsync();

// Fetch a unique record — use SingleOrDefaultAsync
var user = await context.Users
    .AsNoTracking()
    .SingleOrDefaultAsync(u => u.Email == email);

// With multiple Includes — use AsSplitQuery to avoid cartesian explosion
var usersWithOrders = await context.Users
    .AsNoTracking()
    .Include(u => u.Orders)
        .ThenInclude(o => o.OrderItems)
    .AsSplitQuery()
    .Where(u => u.CreatedAt >= startDate)
    .ToListAsync();

// BAD: filtering after ToListAsync() (loads everything into memory)
// var allUsers = await context.Users.ToListAsync();
// var filtered = allUsers.Where(u => u.Name.Contains(searchTerm));

// GOOD: filter -> project -> materialize, in that order
var result = await context.Users
    .Where(u => u.Name.Contains(searchTerm))
    .Select(u => new { u.Id, u.Name })
    .ToListAsync();
```

## Connection Pooling

- `AddDbContext<T>()` uses pooled connections by default via the ADO.NET provider
- Use `AddDbContextPool<T>()` for high-throughput scenarios to reuse `DbContext` instances themselves (reduces allocation overhead)
- Configure max pool size via connection string (e.g., `Max Pool Size=128`)
- Default pool size for `AddDbContextPool` is 1024; tune based on load

```csharp
// High-throughput scenario — pool DbContext instances themselves
builder.Services.AddDbContextPool<AppDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection")),
    poolSize: 128);

// Configure connection pool size in the connection string
// "Host=localhost;Database=mydb;Username=user;Password=pass;Max Pool Size=100;Min Pool Size=10"
```

> **Note:** `AddDbContextPool` requires a parameterless `DbContext` constructor or one that only takes `DbContextOptions`. Avoid injecting additional services into pooled contexts.

## Transactions

- `SaveChangesAsync()` is an implicit transaction — all changes in a single `SaveChanges` call are atomic
- Use explicit `BeginTransactionAsync()` only when spanning multiple `SaveChangesAsync()` calls
- Use `CreateExecutionStrategy()` to wrap transactions for retry-safe execution with connection resiliency

```csharp
// Implicit transaction — sufficient for a single SaveChangesAsync
context.Users.Add(new User { Name = "Alice", Email = "alice@example.com" });
context.Users.Add(new User { Name = "Bob", Email = "bob@example.com" });
await context.SaveChangesAsync(); // Both inserts run in a single transaction

// Explicit transaction — spans multiple SaveChangesAsync calls
await using var transaction = await context.Database.BeginTransactionAsync();
try
{
    var user = new User { Name = "Charlie", Email = "charlie@example.com" };
    context.Users.Add(user);
    await context.SaveChangesAsync();

    var order = new Order { UserId = user.Id, Total = 100.00m };
    context.Orders.Add(order);
    await context.SaveChangesAsync();

    await transaction.CommitAsync();
}
catch
{
    await transaction.RollbackAsync();
    throw;
}

// Retry-safe transaction — accounts for connection resiliency
var strategy = context.Database.CreateExecutionStrategy();
await strategy.ExecuteAsync(async () =>
{
    await using var transaction = await context.Database.BeginTransactionAsync();

    context.Users.Add(new User { Name = "Dave", Email = "dave@example.com" });
    await context.SaveChangesAsync();

    context.Orders.Add(new Order { UserId = 1, Total = 50.00m });
    await context.SaveChangesAsync();

    await transaction.CommitAsync();
});
```

## Migrations

- Create migrations: `dotnet ef migrations add <Name>`
- Apply migrations: `dotnet ef database update`
- Never modify existing migrations after they have been applied to any environment
- Review generated SQL before applying: `dotnet ef migrations script`
- Use `dotnet ef migrations script --idempotent` for production deployment scripts
- Make schema changes non-destructively (add column -> migrate data -> drop old column)

```bash
# Create a migration
dotnet ef migrations add CreateUsersTable

# Apply to the database
dotnet ef database update

# Inspect generated SQL (always review before applying to production)
dotnet ef migrations script

# Generate an idempotent script (for CI/CD pipelines)
dotnet ef migrations script --idempotent -o migrate.sql

# Generate SQL for a specific migration range
dotnet ef migrations script AddOrdersTable AddPaymentsTable
```

> **Warning:** Never edit a migration file that has already been applied to a database. Instead, create a new migration to make corrections.

## Performance

- Avoid N+1 queries — use `Include()` and `ThenInclude()` to eagerly load related data
- Use compiled queries for hot paths via `EF.CompileAsyncQuery` to eliminate query compilation overhead
- Batch bulk operations with `ExecuteUpdateAsync()` / `ExecuteDeleteAsync()` (.NET 7+) to bypass change tracking
- Enable `EnableSensitiveDataLogging()` in development only — never in production
- Use global query filters (`HasQueryFilter`) for soft-delete and multi-tenant patterns

```csharp
// Avoid N+1 — eager-load related data with Include / ThenInclude
var users = await context.Users
    .Include(u => u.Orders)
        .ThenInclude(o => o.OrderItems)
    .ToListAsync();

// Compiled query — performance optimization for hot paths
private static readonly Func<AppDbContext, string, Task<User?>> GetUserByEmailAsync =
    EF.CompileAsyncQuery(
        (AppDbContext context, string email) =>
            context.Users.SingleOrDefault(u => u.Email == email));

// Usage
var user = await GetUserByEmailAsync(context, "alice@example.com");

// Bulk update — ExecuteUpdateAsync (bypasses change tracking)
await context.Users
    .Where(u => u.CreatedAt < cutoffDate)
    .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsArchived, true));

// Bulk delete — ExecuteDeleteAsync (bypasses change tracking)
await context.Users
    .Where(u => u.IsDeleted && u.DeletedAt < retentionDate)
    .ExecuteDeleteAsync();

// Development only — enable sensitive data logging
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseNpgsql(connectionString)
            .EnableSensitiveDataLogging()
            .EnableDetailedErrors());
}
```

## Testing

- Use **Testcontainers for .NET** with real PostgreSQL/SQL Server for integration tests
- Never use the EF Core InMemory provider for integration tests — its behavior differs significantly from real databases (no constraints, no transactions, no SQL)
- Use transaction rollback pattern for test isolation: begin a transaction before each test and roll back after

```csharp
// Integration test against a real database via Testcontainers
public class UserRepositoryTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:17-alpine")
        .Build();

    private AppDbContext _context = null!;

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_postgres.GetConnectionString())
            .Options;

        _context = new AppDbContext(options);
        await _context.Database.EnsureCreatedAsync();
    }

    public async Task DisposeAsync()
    {
        await _context.DisposeAsync();
        await _postgres.DisposeAsync();
    }

    [Fact]
    public async Task CreateUser_ShouldPersistToDatabase()
    {
        // Arrange
        var user = new User { Name = "Test User", Email = "test@example.com" };

        // Act
        _context.Users.Add(user);
        await _context.SaveChangesAsync();

        // Assert
        var saved = await _context.Users
            .SingleOrDefaultAsync(u => u.Email == "test@example.com");
        Assert.NotNull(saved);
        Assert.Equal("Test User", saved.Name);
    }
}
```

```csharp
// Transaction-rollback pattern — for test isolation
public class TransactionalTestBase : IAsyncLifetime
{
    protected AppDbContext Context { get; private set; } = null!;
    private IDbContextTransaction _transaction = null!;

    public async Task InitializeAsync()
    {
        // Obtain a DbContext from the shared test database (via test fixture)
        Context = CreateTestContext();
        _transaction = await Context.Database.BeginTransactionAsync();
    }

    public async Task DisposeAsync()
    {
        await _transaction.RollbackAsync();
        await _transaction.DisposeAsync();
        await Context.DisposeAsync();
    }
}
```

> **Warning:** `UseInMemoryDatabase` is acceptable for unit-testing simple business logic that wraps `DbContext`, but never rely on it for integration tests. Constraints (unique indexes, foreign keys, check constraints) and SQL-specific behaviors are not enforced by the InMemory provider.

## Related Rules / Skills

- Universal constraints: `csharp-style`, `design-principles` (D1-D7), `security` (A1-A10: SQL injection, etc.), `type-safety` (TS-C1-C5)
- Related Skills: `csproj`, `aspnet-core` (AppState / DI setup), `dotnet-build-cache`, `tdd-skills-dotnet`, `integration-test-dotnet` (Testcontainers PostgreSql)
