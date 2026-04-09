---
paths:
  - "**/*.cs"
  - "**/Migrations/**"
globs:
  - "**/*.csproj"
---

# Entity Framework Core Best Practices (.NET 10)

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
// Models/User.cs — エンティティ定義
public class User
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public required string Email { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    // ナビゲーションプロパティ
    public ICollection<Order> Orders { get; set; } = [];
}

// DTOs/UserDto.cs — API レスポンス用
public record UserDto(int Id, string Name, string Email, DateTime CreatedAt);

// DTOs/CreateUserRequest.cs — API リクエスト用
public record CreateUserRequest(string Name, string Email);
```

```csharp
// Data/Configurations/UserConfiguration.cs — Fluent API 設定
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

        // リレーションシップ設定
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
        // 同一アセンブリ内の IEntityTypeConfiguration をすべて自動適用
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

```csharp
// Program.cs — サービス登録
var builder = WebApplication.CreateBuilder(args);

// PostgreSQL の場合
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// SQL Server の場合
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
// 読み取り専用クエリ — AsNoTracking でパフォーマンス向上
var users = await context.Users
    .AsNoTracking()
    .Where(u => u.Name.Contains(searchTerm))
    .OrderByDescending(u => u.CreatedAt)
    .Select(u => new UserDto(u.Id, u.Name, u.Email, u.CreatedAt))
    .Skip(offset)
    .Take(limit)
    .ToListAsync();

// 一意のレコードを取得 — SingleOrDefaultAsync を使用
var user = await context.Users
    .AsNoTracking()
    .SingleOrDefaultAsync(u => u.Email == email);

// 複数の Include がある場合 — AsSplitQuery でカーテシアン爆発を回避
var usersWithOrders = await context.Users
    .AsNoTracking()
    .Include(u => u.Orders)
        .ThenInclude(o => o.OrderItems)
    .AsSplitQuery()
    .Where(u => u.CreatedAt >= startDate)
    .ToListAsync();

// NG: ToListAsync() してからフィルタリング（全件取得してしまう）
// var allUsers = await context.Users.ToListAsync();
// var filtered = allUsers.Where(u => u.Name.Contains(searchTerm));

// OK: フィルタ→プロジェクション→マテリアライズの順
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
// 高スループットシナリオ — DbContext インスタンスプーリング
builder.Services.AddDbContextPool<AppDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection")),
    poolSize: 128);

// 接続文字列でコネクションプールサイズを指定
// "Host=localhost;Database=mydb;Username=user;Password=pass;Max Pool Size=100;Min Pool Size=10"
```

> **Note:** `AddDbContextPool` requires a parameterless `DbContext` constructor or one that only takes `DbContextOptions`. Avoid injecting additional services into pooled contexts.

## Transactions

- `SaveChangesAsync()` is an implicit transaction — all changes in a single `SaveChanges` call are atomic
- Use explicit `BeginTransactionAsync()` only when spanning multiple `SaveChangesAsync()` calls
- Use `CreateExecutionStrategy()` to wrap transactions for retry-safe execution with connection resiliency

```csharp
// 暗黙的トランザクション — 単一の SaveChangesAsync で十分な場合
context.Users.Add(new User { Name = "Alice", Email = "alice@example.com" });
context.Users.Add(new User { Name = "Bob", Email = "bob@example.com" });
await context.SaveChangesAsync(); // 両方のInsertが単一トランザクションで実行

// 明示的トランザクション — 複数の SaveChangesAsync にまたがる場合
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

// リトライ安全なトランザクション — 接続回復性を考慮
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
# マイグレーション作成
dotnet ef migrations add CreateUsersTable

# データベースに適用
dotnet ef database update

# 生成される SQL を確認（本番適用前に必ずレビュー）
dotnet ef migrations script

# 冪等スクリプト生成（CI/CD パイプライン向け）
dotnet ef migrations script --idempotent -o migrate.sql

# 特定のマイグレーション範囲の SQL を生成
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
// N+1 回避 — Include / ThenInclude で関連データを一括取得
var users = await context.Users
    .Include(u => u.Orders)
        .ThenInclude(o => o.OrderItems)
    .ToListAsync();

// コンパイル済みクエリ — ホットパス向けのパフォーマンス最適化
private static readonly Func<AppDbContext, string, Task<User?>> GetUserByEmailAsync =
    EF.CompileAsyncQuery(
        (AppDbContext context, string email) =>
            context.Users.SingleOrDefault(u => u.Email == email));

// 使用方法
var user = await GetUserByEmailAsync(context, "alice@example.com");

// 一括更新 — ExecuteUpdateAsync（変更トラッキングをバイパス）
await context.Users
    .Where(u => u.CreatedAt < cutoffDate)
    .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsArchived, true));

// 一括削除 — ExecuteDeleteAsync（変更トラッキングをバイパス）
await context.Users
    .Where(u => u.IsDeleted && u.DeletedAt < retentionDate)
    .ExecuteDeleteAsync();

// 開発環境のみ — 機密データロギング有効化
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
// Testcontainers で実際のデータベースを使用した統合テスト
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
// トランザクションロールバックパターン — テスト分離用
public class TransactionalTestBase : IAsyncLifetime
{
    protected AppDbContext Context { get; private set; } = null!;
    private IDbContextTransaction _transaction = null!;

    public async Task InitializeAsync()
    {
        // 共有テストデータベースの DbContext を取得（テストフィクスチャ経由）
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
