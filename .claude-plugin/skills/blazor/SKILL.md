---
name: blazor
description: |
  Best practices for Blazor Web App / Blazor WebAssembly (.NET 10). Covers render mode selection (`InteractiveServer` / `InteractiveWebAssembly` / `InteractiveAuto`), data flow via code-behind (`.razor.cs` + partial class) with `[Parameter]` / `[CascadingParameter]` / `EventCallback<T>`, two-way binding with `@bind`, `<EditForm>` + `DataAnnotationsValidator` / `FluentValidation`, the `@page` directive and `NavigationManager`, Trim/AOT verification via `dotnet publish -c Release -p:PublishTrimmed=true`, bUnit component tests + xUnit tests with logic extraction, and list rendering optimization with `<Virtualize>` and `@key`. Reference when implementing Blazor components, managing state, configuring EditForm validation, setting up AOT publish, or writing bUnit tests. Complements the `aspnet-core` Skill. Triggers on: 'Blazor component', 'render mode', 'EditForm validation', 'bUnit test', 'PublishTrimmed', 'Blazorコンポーネント', 'レンダーモード', 'EditFormバリデーション', 'bUnitテスト'.
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Blazor Best Practices

When using Blazor Web App or Blazor WebAssembly, this Skill complements the `aspnet-core` Skill.

## Scope

- Creating and modifying Blazor components (`.razor` + `.razor.cs`)
- Render mode selection (`InteractiveServer` / `InteractiveWebAssembly` / `InteractiveAuto`)
- Data flow design with `[Parameter]` / `[CascadingParameter]` / `EventCallback<T>`
- `<EditForm>` + validation (`DataAnnotationsValidator` / `FluentValidation`)
- List rendering optimization with `<Virtualize>` / `@key`
- Trim/AOT build verification (`dotnet publish -c Release -p:PublishTrimmed=true`)
- Component tests with bUnit, xUnit tests via logic extraction
- Routing design (`@page` + `NavigationManager`)

## Out of Scope

- ASP.NET Core Minimal APIs themselves -> `aspnet-core` Skill
- Entity Framework Core -> `entity-framework-core` Skill
- Project configuration (.csproj) -> `csproj` Skill
- C# code style -> `csharp-style` Rule

## Project Structure (Blazor Web App)

```
src/
├── Components/
│   ├── Layout/
│   │   ├── MainLayout.razor
│   │   └── NavMenu.razor
│   ├── Pages/
│   │   ├── Home.razor
│   │   └── Counter.razor
│   └── _Imports.razor
├── Models/
├── Services/
├── Data/                    # EF Core (server-side)
├── Program.cs
├── App.razor
└── wwwroot/
```

## Render Modes

- `InteractiveServer` — SignalR-based server-side rendering
- `InteractiveWebAssembly` — in-browser WASM
- `InteractiveAuto` — server first, then switches to WASM
- Specify per-component with `@rendermode`, or globally in `App.razor`

## Component Patterns

- One component per file; file name = component name
- Code-behind pattern: `MyComponent.razor` + `MyComponent.razor.cs`
- Use `[Parameter]` for props, `[CascadingParameter]` for context
- Use `EventCallback<T>` for child-to-parent communication

```csharp
// MyComponent.razor.cs (code-behind)
public partial class MyComponent : ComponentBase
{
    [Parameter]
    public string Title { get; set; } = string.Empty;

    [Parameter]
    public EventCallback<string> OnTitleChanged { get; set; }

    [CascadingParameter]
    public ThemeInfo? Theme { get; set; }
}
```

## State Management

- Two-way binding with `@bind`
- DI-like state propagation via cascading values
- For complex state, use a state container (registered as a Scoped service)
- Do not store state in static fields

## Server Functions (equivalent to Leptos `#[server]`)

- Use standard ASP.NET Core API endpoints
- From Blazor WASM, call them via an `HttpClient` injected through DI
- Blazor Server: inject and use services directly

## Forms and Validation

- `<EditForm>` with `Model` binding
- `DataAnnotationsValidator` for validation
- `FluentValidation` for complex rules
- Display errors with `<ValidationSummary>` and `<ValidationMessage>`

```razor
<EditForm Model="@user" OnValidSubmit="@HandleSubmit">
    <DataAnnotationsValidator />
    <ValidationSummary />

    <InputText @bind-Value="user.Name" />
    <ValidationMessage For="@(() => user.Name)" />

    <button type="submit">Submit</button>
</EditForm>
```

## Routing

- Define routes with the `@page "/path"` directive
- Route parameters: `@page "/user/{Id:int}"`
- Use `NavigationManager` for programmatic navigation
- Use `<NavLink>` for active link styling

## WASM Build Verification (equivalent to `cargo leptos build`)

```bash
dotnet publish -c Release -p:PublishTrimmed=true
```

- `-p:PublishTrimmed=true` is **mandatory** — without it, trimming compatibility issues are not detected
- Even if `<PublishTrimmed>true</PublishTrimmed>` is set in the .csproj, specify it explicitly so CI and local behavior match

Additional optimization settings (in .csproj):

```xml
<PropertyGroup>
    <PublishTrimmed>true</PublishTrimmed>
    <RunAOTCompilation>true</RunAOTCompilation>
</PropertyGroup>
```

- Check Trim/AOT warnings (IL2xxx, IL3xxx) — they indicate reflection-dependent code that may break at runtime
- After tests pass in the GREEN phase, always run `dotnet publish -c Release -p:PublishTrimmed=true` to verify the WASM compilation

## Testing

- **Logic tests**: Extract logic into the code-behind `.razor.cs` file and test with xUnit
- **Component tests**: Test rendering and interactions with bUnit
- Do not test raw HTML output — test component behavior and state
- Test signal/state changes, event handler callbacks, and validation logic

### bUnit Test Example

```csharp
[Fact]
public void Counter_IncrementButton_UpdatesCount()
{
    using var ctx = new TestContext();
    var cut = ctx.RenderComponent<Counter>();

    cut.Find("button").Click();

    cut.Find("p").MarkupMatches("<p>Current count: 1</p>");
}
```

### Unit Test Targets

| Frontend concern | Test approach |
|---|---|
| Component state transitions | Extract logic to code-behind, assert with xUnit |
| Validation logic | Extract validation function, test directly |
| Service logic | Unit-test DI services, mock dependencies |
| EventCallback handlers | Fire events with bUnit, assert state changes |

### Out of Unit Test Scope (delegate to E2E)

- HTML output of Razor templates
- Dynamic application of CSS classes
- Routing transitions
- SignalR connection behavior

## Performance

- Use `@key` to optimize list rendering
- Lazy-load assemblies with `<BlazorWebAssemblyLazyLoad>`
- Virtualize long lists with `<Virtualize>`
- Minimize unnecessary component re-renders with `ShouldRender()`

```razor
<Virtualize Items="@items" Context="item">
    <ItemRow Item="@item" />
</Virtualize>
```

## Related Rules / Skills

- Universal constraints: `csharp-style`, `design-principles`, `security` (A1-A10), `type-safety` (TS-C1-C5)
- Related Skills: `aspnet-core` (Blazor Server-side DI / middleware), `csproj` (PublishTrimmed configuration), `entity-framework-core` (server-side DB access), `dotnet-build-cache`, `setup-ci`, `tdd-skills-dotnet`
