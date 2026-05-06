---
name: csproj
description: |
  Conventions for `.csproj` / `Directory.Build.props` / `Directory.Packages.props` (.NET 10 SDK-style). Covers PropertyGroup order (TargetFramework -> OutputType -> RootNamespace), required settings (`<Nullable>enable</Nullable>` / `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` / `<ImplicitUsings>enable</ImplicitUsings>`), alphabetical PackageReference ordering, Central Package Management (`ManagePackageVersionsCentrally` + `Directory.Packages.props`), `PrivateAssets="all"` for Roslyn analyzers, and dependency hygiene via `dotnet list package --vulnerable` / snitch / `dotnet nuget why`. Reference when editing .csproj, adding or updating packages, introducing Central Package Management, configuring analyzers, or auditing NuGet vulnerabilities. Triggers on: '.csproj configuration', 'Directory.Build.props', 'Central Package Management', 'NuGet vulnerability audit', '.csproj編集', 'パッケージ追加', 'analyzer設定', 'NuGet脆弱性監査'.
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# .csproj / Directory.Build.props Style Rules

Follow SDK-style project format conventions for .NET 10 projects.

## Scope

- Creating new .csproj files; migrating legacy projects to SDK-style
- Centralizing shared settings via Directory.Build.props (`Nullable`, `TreatWarningsAsErrors`, `EnforceCodeStyleInBuild`)
- Introducing and operating Central Package Management via Directory.Packages.props
- Adding, updating, and maintaining alphabetical order of PackageReference entries
- `PrivateAssets="all"` when introducing Roslyn analyzers (Meziantou / Roslynator / StyleCop)
- NuGet vulnerability audits, unused reference detection with `snitch`, transitive dependency analysis with `dotnet nuget why`

## Out of Scope

- C# code style -> `csharp-style` Rule
- ASP.NET Core Program.cs configuration -> `aspnet-core` Skill
- NuGet cache strategy -> `dotnet-build-cache` Skill
- NuGet cache configuration in CI -> `setup-ci` Skill

## Section Order (.csproj)

- SDK-style project format only: `<Project Sdk="Microsoft.NET.Sdk">` (or `Microsoft.NET.Sdk.Web`, `Microsoft.NET.Sdk.BlazorWebAssembly`)
- Never use legacy verbose project format; migrate to SDK-style if encountered
- PropertyGroup order: `TargetFramework` → `OutputType` → `RootNamespace` → other settings
- ItemGroup order: `PackageReference` → `ProjectReference` → other items (Content, None, EmbeddedResource, etc.)
- Separate multiple PropertyGroup/ItemGroup sections with a blank line

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <RootNamespace>MyApp</RootNamespace>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Hosting" Version="10.0.0" />
    <PackageReference Include="Serilog" Version="4.*" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\MyLib\MyLib.csproj" />
  </ItemGroup>

</Project>
```

## PropertyGroup Conventions

- `<TargetFramework>net10.0</TargetFramework>` — target .NET 10 unless a specific reason requires multi-targeting
- `<Nullable>enable</Nullable>` — mandatory for all projects; do not suppress nullable warnings globally
- `<ImplicitUsings>enable</ImplicitUsings>` — use implicit usings to reduce boilerplate
- `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` — enforce zero-warning policy
- `<DocumentationFile>` — enable for public API / library projects to generate XML docs
- Use `<LangVersion>preview</LangVersion>` only when C# preview features are intentionally adopted; otherwise omit (defaults to the SDK's stable version)
- For multi-targeting, use `<TargetFrameworks>net10.0;net9.0</TargetFrameworks>` (plural) with semicolon-separated TFMs

## PackageReference Conventions

- Sort `PackageReference` entries alphabetically by the `Include` attribute
- Use the `Version` attribute inline for simple projects:

```xml
<PackageReference Include="xunit" Version="2.*" />
<PackageReference Include="xunit.runner.visualstudio" Version="2.*" />
```

- For solutions with multiple projects, prefer Central Package Management via `Directory.Packages.props` (see below)
- Use self-closing tags: `<PackageReference Include="..." Version="..." />` — never use `<PackageReference>...</PackageReference>` form for empty elements
- Pin to specific major versions or use version ranges deliberately; avoid floating `*` versions in production

## Directory.Build.props

- Place at the solution root to share common settings across all projects
- Any property defined here applies to every project in the directory tree below it
- Include common Roslyn analyzer packages with `PrivateAssets="all"` so they do not flow to consumers:

```xml
<Project>

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Meziantou.Analyzer" Version="2.*" PrivateAssets="all" />
    <PackageReference Include="Roslynator.Analyzers" Version="4.*" PrivateAssets="all" />
    <PackageReference Include="StyleCop.Analyzers" Version="1.*" PrivateAssets="all" />
  </ItemGroup>

</Project>
```

- Common properties to centralize: `TreatWarningsAsErrors`, `Nullable`, `ImplicitUsings`, `LangVersion`, `EnforceCodeStyleInBuild`
- Do not place output-type-specific settings (e.g., `OutputType`, `RootNamespace`) here; keep them in individual .csproj files
- For test projects that need different settings, use a nested `Directory.Build.props` that imports the parent:

```xml
<Import Project="$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)../'))" />
```

## Directory.Packages.props (Central Package Management)

- Enable Central Package Management by setting:

```xml
<Project>

  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>

  <ItemGroup>
    <PackageVersion Include="Microsoft.Extensions.Hosting" Version="10.0.0" />
    <PackageVersion Include="Serilog" Version="4.2.0" />
    <PackageVersion Include="xunit" Version="2.9.3" />
  </ItemGroup>

</Project>
```

- All version pins are centralized in this single file
- Individual .csproj files reference packages without specifying `Version`:

```xml
<PackageReference Include="Microsoft.Extensions.Hosting" />
```

- Sort `PackageVersion` entries alphabetically
- To override a centrally managed version in a specific project, use `VersionOverride`:

```xml
<PackageReference Include="SomePackage" VersionOverride="3.0.0-preview.1" />
```

## .editorconfig

- An `.editorconfig` file must coexist with csproj settings at the solution root
- Use `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>` in `Directory.Build.props` to enforce code style rules during build
- Refer to `csharp-style` Rule for detailed C# formatting and naming convention rules
- Ensure `.editorconfig` severity levels align with `TreatWarningsAsErrors` — any `warning`-level rule will fail the build

## Dependency Hygiene

- Remove unused packages. Use [`Snitch`](https://github.com/spectreconsole/snitch) to detect redundant direct references that are already pulled in transitively:

```bash
dotnet tool install -g snitch
snitch
```

- Prefer packages with active maintenance and no known vulnerabilities
- Run vulnerability checks regularly:

```bash
dotnet list package --vulnerable --include-transitive
```

- Understand transitive dependency chains before adding or upgrading packages:

```bash
dotnet nuget why <project> <package>
```

- Audit the full dependency graph after any package change
- When removing a package, verify no transitive consumers depend on it by running `dotnet build` across the entire solution

## Related Rules / Skills

- Universal constraints: `csharp-style`, `quality-checks` (QC12)
- Related Skills: `aspnet-core`, `entity-framework-core`, `blazor`, `dotnet-build-cache`, `setup-ci`, `tdd-skills-dotnet`, `integration-test-dotnet`
