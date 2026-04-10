---
name: integration-test-dotnet
description: >
  .NET integration test design and implementation skill.
  Uses ASP.NET Core WebApplicationFactory, Entity Framework Core, Testcontainers for .NET, and WireMock.NET.
  Covers test design policy, 5-category test coverage (happy path, error, boundary, edge, external dependency),
  and parallel test execution with xUnit collection fixtures.
  Use when designing or implementing integration tests for .NET 10 Web API or Blazor projects.
argument-hint: "<domain>[,<domain>...] [--dry-run] [--base-branch <branch>]"
user-invokable: true
---

# integration-test-dotnet

A skill that uses Agent Teams to create integration tests under `tests/<ProjectName>.IntegrationTests/` in parallel.
Workers (alpha/bravo) implement the tests, and Pentagon reviews them at the quality gate.

Tech stack: ASP.NET Core (.NET 10) + Entity Framework Core + Testcontainers for .NET + StackExchange.Redis + WireMock.NET

## Execution Environment Rules

| Rule | Description |
|--------|------|
| **No self-created branches/worktrees** | Do not directly run `git checkout -b` / `git worktree add` |
| **When `--base-branch` is not specified** | Work in the current directory on the current branch |
| **When `--base-branch` is specified** | Create a worktree via the `create-git-worktree` skill |

## Design Policy

| Dependency Type | Policy |
|----------|------|
| **DB (PostgreSQL/SQL Server)** | Testcontainers for .NET — real database container (no EF Core InMemory provider) |
| **External HTTP APIs** | WireMock.NET — HTTP-level stubbing with request matching and response templating |
| **Cache (Redis)** | Testcontainers for .NET — real Redis container |
| **Internal services** | Interface-based DI override via `WebApplicationFactory.WithWebHostBuilder` |

## WebApplicationFactory Setup

The central test fixture creates a real PostgreSQL container via Testcontainers and replaces
the application's `DbContext` registration. All tests share the container but each test
gets an isolated transaction or a freshly-seeded database state.

```csharp
public class IntegrationTestFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    private readonly RedisContainer _redis = new RedisBuilder()
        .WithImage("redis:7-alpine")
        .Build();

    public WebApplicationFactory<Program> Factory { get; private set; } = default!;

    public async Task InitializeAsync()
    {
        await Task.WhenAll(_postgres.StartAsync(), _redis.StartAsync());

        Factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.ConfigureServices(services =>
                {
                    // Replace DbContext with test database
                    services.RemoveAll<DbContextOptions<AppDbContext>>();
                    services.AddDbContext<AppDbContext>(options =>
                        options.UseNpgsql(_postgres.GetConnectionString()));

                    // Replace Redis connection
                    services.RemoveAll<IConnectionMultiplexer>();
                    services.AddSingleton<IConnectionMultiplexer>(
                        ConnectionMultiplexer.Connect(_redis.GetConnectionString()));
                });
            });

        // Run EF Core migrations
        using var scope = Factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        await _postgres.DisposeAsync();
        await _redis.DisposeAsync();
    }
}
```

## 5-Category Test Coverage

All integration test cases are organized into 5 categories:

| Category | Description | Examples |
|----------|-------------|----------|
| **Happy Path** | Correct inputs producing expected results | User creation succeeds, list retrieval returns data |
| **Error Path** | Invalid inputs or error conditions | Validation errors, authentication failures, 404 |
| **Boundary** | Boundary condition behavior | Empty collections, max-length strings, pagination edges |
| **Edge Cases** | Special or unusual situations | Duplicate data, concurrent updates, special characters |
| **External Dependencies** | External system failures | WireMock.NET timeout simulation, service unavailable |

## Test Structure

```csharp
[Collection("Integration")]
public class UserEndpointTests(IntegrationTestFixture fixture)
    : IClassFixture<IntegrationTestFixture>
{
    private readonly HttpClient _client = fixture.Factory.CreateClient();

    [Fact]
    public async Task CreateUser_ReturnsCreated_WhenValidRequest()
    {
        // Given
        var request = new { Name = "Alice", Email = "alice@example.com" };

        // When
        var response = await _client.PostAsJsonAsync("/api/users", request);

        // Then
        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var user = await response.Content.ReadFromJsonAsync<UserResponse>();
        user!.Name.Should().Be("Alice");
    }

    [Fact]
    public async Task CreateUser_ReturnsBadRequest_WhenNameMissing()
    {
        // Given
        var request = new { Email = "alice@example.com" };

        // When
        var response = await _client.PostAsJsonAsync("/api/users", request);

        // Then
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }
}
```

## DB Verification Pattern

After POST/PUT/DELETE, verify DB state directly via DbContext to confirm side effects:

```csharp
[Fact]
public async Task CreateUser_PersistsToDatabase()
{
    // Given
    var request = new { Name = "Alice", Email = "alice@example.com" };

    // When
    await _client.PostAsJsonAsync("/api/users", request);

    // Then — verify DB state directly
    using var scope = fixture.Factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var user = await db.Users.FirstOrDefaultAsync(u => u.Email == "alice@example.com");
    user.Should().NotBeNull();
    user!.Name.Should().Be("Alice");
}

[Fact]
public async Task DeleteUser_RemovesFromDatabase()
{
    // Given — seed a user
    int userId;
    using (var seedScope = fixture.Factory.Services.CreateScope())
    {
        var seedDb = seedScope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = new User { Name = "Alice", Email = "alice@example.com" };
        seedDb.Users.Add(user);
        await seedDb.SaveChangesAsync();
        userId = user.Id;
    }

    // When
    var response = await _client.DeleteAsync($"/api/users/{userId}");

    // Then — verify with a fresh DbContext to avoid EF Core change tracker cache
    response.StatusCode.Should().Be(HttpStatusCode.NoContent);
    using var verifyScope = fixture.Factory.Services.CreateScope();
    var verifyDb = verifyScope.ServiceProvider.GetRequiredService<AppDbContext>();
    var deleted = await verifyDb.Users.FindAsync(userId);
    deleted.Should().BeNull();
}
```

## WireMock.NET Pattern

Use WireMock.NET to stub external HTTP API dependencies at the HTTP level:

```csharp
public class ExternalApiTests : IClassFixture<IntegrationTestFixture>, IAsyncLifetime
{
    private readonly IntegrationTestFixture _fixture;
    private WireMockServer _wireMock = default!;
    private HttpClient _client = default!;

    public ExternalApiTests(IntegrationTestFixture fixture) => _fixture = fixture;

    public Task InitializeAsync()
    {
        _wireMock = WireMockServer.Start();

        // Override the external API base URL in the test host
        _client = _fixture.Factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.Configure<ExternalApiOptions>(opts =>
                    opts.BaseUrl = _wireMock.Url!);
            });
        }).CreateClient();

        return Task.CompletedTask;
    }

    public Task DisposeAsync()
    {
        _wireMock.Dispose();
        return Task.CompletedTask;
    }

    [Fact]
    public async Task CreateOrder_CallsPaymentGateway_AndReturnsCreated()
    {
        // Given — stub the payment gateway
        _wireMock.Given(
            Request.Create().WithPath("/api/charge").UsingPost()
        ).RespondWith(
            Response.Create()
                .WithStatusCode(200)
                .WithBodyAsJson(new { transactionId = "txn_123", status = "succeeded" })
        );

        var request = new { ProductId = 1, Amount = 100 };

        // When
        var response = await _client.PostAsJsonAsync("/api/orders", request);

        // Then
        response.StatusCode.Should().Be(HttpStatusCode.Created);
    }

    [Fact]
    public async Task CreateOrder_ReturnsServiceUnavailable_WhenPaymentGatewayTimesOut()
    {
        // Given — simulate timeout
        _wireMock.Given(
            Request.Create().WithPath("/api/charge").UsingPost()
        ).RespondWith(
            Response.Create().WithDelay(TimeSpan.FromSeconds(30))
        );

        var request = new { ProductId = 1, Amount = 100 };

        // When
        var response = await _client.PostAsJsonAsync("/api/orders", request);

        // Then
        response.StatusCode.Should().BeOneOf(
            HttpStatusCode.GatewayTimeout,
            HttpStatusCode.ServiceUnavailable);
    }
}
```

## Team Composition (always 3 roles)

| Role | Agent | Responsibility |
|------|------------|------|
| **Command** (Leader) | Main agent | Commander and strategy planner |
| **Workers** (alpha/bravo) | Sub-agent x 1-2 | Test implementation |
| **Pentagon** (Reviewer) | Sub-agent | Quality review and judgment |

## Arguments

`$ARGS` is specified as a comma-separated list of domain names (e.g., `users,orders`).

| Argument | Required | Description |
|------|:----:|------|
| `$ARGS` | YES | `{domain}[,{domain}...]` (comma-separated) |
| `--dry-run` | - | Print the assignment plan and exit |
| `--base-branch <branch>` | - | Branch to derive the worktree from |
| `--api <method>` | - | Only target a specific HTTP method |

### Usage Examples

```bash
# Parallel execution (2 targets)
/integration-test-dotnet users,orders

# dry-run (show plan only)
/integration-test-dotnet users,orders --dry-run

# Single target (alpha 1 + Pentagon 1)
/integration-test-dotnet sessions

# Specific method only
/integration-test-dotnet users --api GET
```

---

## Flow Overview

```
/integration-test-dotnet users,orders
    |
    +-- [P0] Parse & Analyze
    |     +-- Parse arguments (comma-separated)
    |     +-- For each target: trace controller -> service -> repository -> entity
    |     +-- Worker assignment plan
    |     +-- --dry-run: show plan only and exit
    |
    +-- [P1] Setup Team
    |     +-- Pre-check test helpers and shared fixtures
    |     +-- Create whiteboard
    |
    +-- [P2] Launch Agents
    |     +-- Launch Workers (alpha/bravo) x 1-2
    |     +-- Launch Pentagon x 1
    |     +-- Assign initial tasks
    |
    +-- [P3] Monitor & Facilitate
    |     +-- Worker completes -> Request Pentagon review
    |     +-- PASS -> Update whiteboard, assign next task
    |     +-- FAIL -> Send back to Worker (max 3 times)
    |
    +-- [P4] Final Verification
    |     +-- Run dotnet test across all test files
    |     +-- dotnet format + build warnings
    |
    +-- [P5] Cleanup & Report
          +-- Aggregate results
          +-- Clean up whiteboard
          +-- Output final report
```

---

## Executor Instructions

**You (Command) manage the team following the steps below.**

### P0: Parse & Analyze

1. Split `$ARGS` by comma to build the target list
2. **For each target**:
   - Identify controller: trace routes and action methods from `Controllers/{Domain}Controller.cs`
   - Identify service: analyze business logic from `Services/{Domain}Service.cs` or `Services/I{Domain}Service.cs`
   - Identify repository: analyze query logic from `Repositories/{Domain}Repository.cs` or via EF Core DbContext
   - Identify entity: check EF Core entity models from `Models/{Domain}.cs` or `Entities/{Domain}.cs`
   - Identify DTOs: check request/response models from `Dtos/{Domain}Dto.cs`
   - Identify external dependencies: find interface-based dependencies (e.g., external API clients via `HttpClient`)
3. **Worker assignment**: assign to Workers per test class. Before assignment, run the resource detection snippet from `resource-aware-parallelism.md` and obtain `MAX_HEAVY_AGENTS`. Limit Worker count to `min(Workers column below, MAX_HEAVY_AGENTS)`.

   | # of Targets | MAX_HEAVY_AGENTS | # of Workers | Assignment Method |
   |:------:|:------:|:---------:|---------|
   | 1 | any | 1 | All to alpha |
   | 2 | >= 2 | 2 | One each to alpha / bravo |
   | 2 | 1 | 1 | Both to alpha (sequential) |
   | 3+ | >= 2 | 2 | Round-robin |
   | 3+ | 1 | 1 | All to alpha (sequential) |

4. **On `--dry-run`**: output the following and exit

```
[dry-run] Assignment plan:
  alpha: {domain_a} -> {Domain}EndpointTests.cs
    - {method} {path}
  bravo: {domain_b} -> {Domain}EndpointTests.cs
    - {method} {path}
  pentagon: quality review
```

### P1: Setup Team

1. Check and update shared test fixtures (`Fixtures/` directory in the test project)
2. Create whiteboard: Write following [whiteboard-template.md](references/whiteboard-template.md)
   - **Always set Key Questions** (1-3 items)

### P2: Launch Agents

Launch Workers and Pentagon as sub-agents. Specify the agent definition under `.claude-plugin/agents/` via `subagent_type`.

**Resource-adaptive parallel control**: Limit Worker count based on `MAX_HEAVY_AGENTS` obtained in P0. Log the resource detection result:
```
[resource-check] CPU: {CPU_CORES} cores, Free memory: {FREE_MEM_MB}MB, MAX_HEAVY_AGENTS: {MAX_HEAVY_AGENTS}
[worker-limit] Requested {N} workers, launching {M} (limited by MAX_HEAVY_AGENTS)
```

**Launch Pentagon** (launch first to put it in a review-request waiting state):
```
Agent(
  subagent_type: "spec-workflow-mcp:integ-test-dotnet-auditor",
  prompt: "Whiteboard: {whiteboard_path}\nPlease wait for a review request from Command."
)
```

**Launch Workers** (fill in variables from [worker-prompt.md](references/worker-prompt.md)):
```
Agent(
  subagent_type: "spec-workflow-mcp:integ-test-dotnet-worker",
  prompt: "Worker name: {worker_name}\nDomain: {domain}\nTest class: {Domain}EndpointTests.cs\nTarget endpoints:\n{endpoint_list}\nWhiteboard: {whiteboard_path}"
)
```

If there are 2 or more targets and `MAX_HEAVY_AGENTS >= 2`, launch alpha/bravo in parallel. Otherwise, launch alpha only and assign all targets sequentially.

### P3: Monitor & Facilitate

Main loop: monitor until all tasks are complete.

**When a Worker completes**:
1. Copy Worker Findings to the whiteboard
2. Request a review from Pentagon

**When Pentagon returns PASS**:
1. Update the Quality Gate Results on the whiteboard
2. Assign the next unassigned task to a Worker if one exists

**When Pentagon returns FAIL**:
1. Count the number of reviews (per test class)
2. Under 3 times: re-run the Worker with a prompt including the review comments
3. 3rd time: mark as complete with remaining issues noted on the whiteboard

### P4: Final Verification

```bash
# Run all integration tests
dotnet test tests/<ProjectName>.IntegrationTests/ --no-build --verbosity normal

# Code quality
dotnet format tests/<ProjectName>.IntegrationTests/ --verify-no-changes --no-restore
dotnet build tests/<ProjectName>.IntegrationTests/ --no-restore -warnaserror
```

If verification fails, Command fixes it directly.

### P5: Cleanup & Report

1. Move the whiteboard to `.claude/_docs/deleted/`
2. Output the final report:

```
integration-test-dotnet parallel implementation complete

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Targets: {targets}

Generated files:
  {file_list}

Test results:
  {test_summary}

Quality gate:
  {quality_gate_results}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## References

| Document | Purpose |
|------------|------|
| [quality-gate.md](references/quality-gate.md) | Pentagon's judgment criteria |
| [test-case-design.md](references/test-case-design.md) | 5 test case classifications |
| [test-patterns.md](references/test-patterns.md) | Test implementation patterns |
| [fixture-catalog.md](references/fixture-catalog.md) | Shared helpers and fixture catalog |
| [external-api-mock.md](references/external-api-mock.md) | WireMock.NET external API mock patterns |
| [worker-prompt.md](references/worker-prompt.md) | Worker prompt template |
| [auditor-prompt.md](references/auditor-prompt.md) | Pentagon prompt template |
| [whiteboard-template.md](references/whiteboard-template.md) | Whiteboard template |
| [parallel-execution.md](references/parallel-execution.md) | Parallel execution flow details |
