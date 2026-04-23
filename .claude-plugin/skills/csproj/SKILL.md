---
name: csproj
description: |
  `.csproj` / `Directory.Build.props` / `Directory.Packages.props` の規約 (.NET 10 SDK スタイル)。PropertyGroup 順序 (TargetFramework → OutputType → RootNamespace)、`<Nullable>enable</Nullable>` / `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` / `<ImplicitUsings>enable</ImplicitUsings>` の必須化、PackageReference アルファベット順、Central Package Management (`ManagePackageVersionsCentrally` + `Directory.Packages.props`)、Roslyn analyzer の `PrivateAssets="all"`、`dotnet list package --vulnerable` / snitch / `dotnet nuget why` による依存衛生をカバー。.csproj 編集、パッケージ追加・更新、Central Package Management 導入、analyzer 設定、NuGet 脆弱性監査時に参照。
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# .csproj / Directory.Build.props Style Rules

Follow SDK-style project format conventions for .NET 10 projects.

## 対象

- 新規 .csproj の作成、レガシープロジェクトの SDK-style への移行
- Directory.Build.props による共通設定の集約（`Nullable`, `TreatWarningsAsErrors`, `EnforceCodeStyleInBuild`）
- Directory.Packages.props による Central Package Management の導入・運用
- PackageReference の追加・更新・アルファベット順維持
- Roslyn analyzer (Meziantou / Roslynator / StyleCop) 導入時の `PrivateAssets="all"`
- NuGet 脆弱性監査、`snitch` による未使用検出、`dotnet nuget why` による transitive 依存解析

## 対象外

- C# コードのスタイル → `csharp-style` Rule
- ASP.NET Core の Program.cs 設定 → `aspnet-core` Skill
- NuGet キャッシュ戦略 → `dotnet-build-cache` Skill
- CI での NuGet キャッシュ設定 → `setup-ci` Skill

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

## 関連 Rule / Skill

- 普遍制約: `csharp-style`, `quality-checks` (QC12)
- 関連 Skill: `aspnet-core`, `entity-framework-core`, `blazor`, `dotnet-build-cache`, `setup-ci`, `tdd-skills-dotnet`, `integration-test-dotnet`
