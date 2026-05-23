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

A skill that uses Agent Teams to create integration tests under `tests/<ProjectName>.IntegrationTests/`.
A single Worker (alpha) implements the tests sequentially, and Pentagon reviews them at the quality gate. Concurrent Worker launches are prohibited per `rules/serial-execution-policy.md`.

> Note: The `parallel test execution with xUnit collection fixtures` mentioned in this Skill's description refers to xUnit's runtime-level test parallelism inside the .NET test runner — that is unrelated to the prohibited subagent parallelism above and remains in effect.

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
| **Command** (Leader) | Main agent | Commander, strategy planner, and shared-context holder (in-session) |
| **Worker** (alpha) | Sub-agent x 1 | Test implementation (handles all targets sequentially) |
| **Pentagon** (Reviewer) | Sub-agent (re-launched per review request) | Quality review and judgment |

**Communication model**: Workers and Pentagon communicate with Command via (i) launch-time prompt and (ii) final completion report (the agent's last response). Command holds the shared context in its own session and re-injects relevant parts into each sub-agent prompt.

## Arguments

`$ARGS` is specified as a comma-separated list of domain names (e.g., `users,orders`).

| Argument | Required | Description |
|------|:----:|------|
| `$ARGS` | YES | `{domain}[,{domain}...]` (comma-separated) |
| `--dry-run` | - | Print the assignment plan and exit |
| `--base-branch <branch>` | - | Branch to derive the worktree from |
| `--api <method>` | - | Only target a specific HTTP method |
| `--spec <name>` | - | Spec name to scope the job log under `.spec-workflow/specs/{name}/integ-test-runs/`. Omit to log at `.spec-workflow/integ-test-runs/` |

### Usage Examples

```bash
# Multiple targets (handled sequentially by alpha)
/integration-test-dotnet users,orders

# dry-run (show plan only)
/integration-test-dotnet users,orders --dry-run

# Single target
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
    |     +-- --dry-run: show plan only and exit
    |
    +-- [P1] Setup
    |     +-- Pre-check shared test fixtures (Fixtures/ directory)
    |     +-- Build shared context in Command's session
    |       (Goal, Key Questions, Shared Resources, per-domain analysis)
    |
    +-- [P2] Per-Domain Loop (Implement + Review)
    |     For each domain (one at a time):
    |     +-- Launch alpha (Worker) with full per-domain prompt
    |     +-- Worker returns Findings + self-checked tests in completion report
    |     +-- Launch Pentagon fresh with the Worker's Findings in prompt
    |     +-- PASS  -> next domain
    |     +-- FAIL (cycle < 3) -> re-launch alpha with rework instructions
    |     +-- FAIL (cycle = 3) -> record as complete-with-issues, next domain
    |
    +-- [P3] Final Verification
    |     +-- Run dotnet test across all generated test files
    |     +-- dotnet format + build -warnaserror
    |
    +-- [P4] Report
          +-- Aggregate results from Command's session state
          +-- Output final report
```

---

## Executor Instructions

**You (Command) manage the team following the steps below.** All shared state lives in your own session context.

### P0: Parse & Analyze

1. Split `$ARGS` by comma to build the target list
2. **For each target**:
   - Identify controller: trace routes and action methods from `Controllers/{Domain}Controller.cs`
   - Identify service: analyze business logic from `Services/{Domain}Service.cs` or `Services/I{Domain}Service.cs`
   - Identify repository: analyze query logic from `Repositories/{Domain}Repository.cs` or via EF Core DbContext
   - Identify entity: check EF Core entity models from `Models/{Domain}.cs` or `Entities/{Domain}.cs`
   - Identify DTOs: check request/response models from `Dtos/{Domain}Dto.cs`
   - Identify external dependencies: find interface-based dependencies (e.g., external API clients via `HttpClient`)
3. **Worker assignment**: launch only alpha (a single Worker) and have it handle all targets sequentially. Concurrent Worker launches are prohibited (`rules/serial-execution-policy.md`).

4. **On `--dry-run`**: output the following and exit

```
[dry-run] Assignment plan:
  alpha: handles all targets sequentially
    - {domain_a} -> {Domain_a}EndpointTests.cs
        - {method} {path}
    - {domain_b} -> {Domain_b}EndpointTests.cs
        - {method} {path}
  pentagon: re-launched per review request
```

### P1: Setup

1. Check and update shared test fixtures (`Fixtures/` directory in the test project)
2. Build the **shared context** in your own session memory. The shared context contains:
   - **Goal**: one-line description of what the team is producing
   - **Key Questions** (1-3 items): questions whose answers must be consistent across domains (e.g., "Is the problem+json error shape shared?")
   - **Shared Resources**: file paths for common fixtures (IntegrationTestFixture, WireMock builders, seed helpers)
   - **Per-domain Analysis Summary**: endpoint list, service/repository methods, external dependencies, derived from P0

   Keep this in session memory so that each sub-agent launch can include the relevant slice in its prompt.

3. **Create the job log** per `rules/task-log-format.md`:
   - If a spec context is available (`--spec <name>` or detected from cwd): path is `.spec-workflow/specs/{spec-name}/integ-test-runs/{timestamp}.log.md`
   - If no spec context: path is `.spec-workflow/integ-test-runs/{timestamp}.log.md`
   - `{timestamp}` is ISO 8601 UTC with separators stripped (e.g., `20260520T143200`)
   - Create the parent directory and write the header + `## Metadata` (spec, targets, args, created, log-id) + empty `## Events` section
   - Append a `job-start` event with `targets={comma-separated domains}`, `goal`, `key_questions` details

### P2: Per-Domain Loop (Implement + Review)

Process the target list one domain at a time. For each domain, Command also appends events to the job log at each transition (`rules/task-log-format.md` TL4 integration-test events). The Worker and Pentagon do not touch the log themselves — Command extracts info from their final responses and writes the entries.

#### P2.1: Launch alpha (Worker)

Before launch, append a `domain-analysis` event with `domain={domain}` and the endpoint / external_deps details. Then append a `worker-launch` event with `domain={domain}` cycle={N}.

Launch alpha with a single, self-contained prompt. Substitute the variables from your shared context. See [worker-prompt.md](references/worker-prompt.md) for the prompt template.

```
Agent(
  subagent_type: "spec-workflow-mcp:integ-test-worker",
  prompt: "Language: dotnet
Worker name: alpha
Domain: {domain}
Test class: {Domain}EndpointTests.cs
Target endpoints:
{endpoint_list}

## Shared Context (from Command)
- Goal: {goal}
- Key Questions:
{key_questions}
- Shared Resources:
{shared_resources}
- Domain Analysis:
{per_domain_analysis}

## Instructions
Implement the integration tests per the procedure in your agent definition.
Return your Findings and quality self-check results in your completion report."
)
```

#### P2.2: Worker returns

The Worker's completion report includes Findings (free text), test counts per category, and self-check results (dotnet format / dotnet build -warnaserror / dotnet test). Extract these into your session state for this domain.

Append a `worker-return` event with `domain={domain}` `cycle={N}` `result={PASS|FAIL based on self-checks}` and `test_counts`, `findings_excerpt` (one-line) details.

#### P2.3: Launch Pentagon fresh

Append a `pentagon-launch` event with `domain={domain}` `cycle={N}`.

Launch Pentagon with the Worker's Findings embedded in the prompt. Pentagon is re-launched per review request — it does NOT persist across domains. See [auditor-prompt.md](references/auditor-prompt.md) for the prompt template.

```
Agent(
  subagent_type: "spec-workflow-mcp:integ-test-auditor",
  prompt: "Language: dotnet
Test file: tests/<ProjectName>.IntegrationTests/{Domain}EndpointTests.cs

## Target API
{endpoint_list}

## Worker Findings (from alpha)
{worker_findings_block}

## Instructions
Apply the quality gate review per your agent definition and return PASS / FAIL with details in your completion report."
)
```

#### P2.4: Process Pentagon result

Append a `pentagon-return` event with `domain={domain}` `cycle={N}` `verdict={PASS|FAIL}` and `issues_excerpt` detail (one-line summary when FAIL).

| Pentagon verdict | Action |
|---|---|
| **PASS** | Append `domain-done domain={domain} status=PASS cycles={N}`, move to the next domain |
| **FAIL** (cycle < 3) | Re-launch alpha with the same prompt **plus** the Pentagon Issues block. Increment the cycle counter for this domain. |
| **FAIL** (cycle = 3) | Append `domain-done domain={domain} status=done-with-issues cycles=3`, attach Pentagon's remaining Issues to the final report, move to the next domain |

When re-launching alpha for rework, prepend the Pentagon Issues block:

```
## Pentagon Review Feedback (cycle {N})
{issues_block}

Apply the fixes per the issues above, then re-run your quality self-check and return an updated completion report.
```

### P3: Final Verification

```bash
# Run all integration tests
dotnet test tests/<ProjectName>.IntegrationTests/ --no-build --verbosity normal

# Code quality
dotnet format tests/<ProjectName>.IntegrationTests/ --verify-no-changes --no-restore
dotnet build tests/<ProjectName>.IntegrationTests/ --no-restore -warnaserror
```

If verification fails, Command fixes it directly (do not launch a new Worker for harness-level fixes).

### P4: Report

Append a `job-end` event with `targets={domains}` and `status={success|partial}` (partial = at least one `done-with-issues`).

Aggregate the per-domain state from your session and output:

```
integration-test-dotnet implementation complete

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Targets: {targets}

Generated files:
  {file_list}

Test results:
  {test_summary}

Quality gate:
  - {domain_a}: PASS / done-with-issues (cycles: {N})
  - {domain_b}: PASS / done-with-issues (cycles: {N})

Remaining issues (if any):
  {remaining_issues_block}
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
