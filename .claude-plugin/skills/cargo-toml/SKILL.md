---
name: cargo-toml
description: |
  Conventions for the formatting and structure of Cargo.toml. Covers placement and key order of the `[package]` section (name → version → ... → description), indentation (4 spaces), line width (100 characters), how to write array/table values, SPDX license expressions, the authors format, and dependency hygiene (detecting unused dependencies with `cargo +nightly udeps`, checking vulnerabilities with `cargo audit`). Reference this when editing Cargo.toml, adding dependencies, configuring package metadata, configuring a workspace, or reviewing a Rust project manifest. Triggers on: 'cargo toml format', 'package metadata', 'workspace configuration', 'dependency hygiene', 'Cargo.toml 編集', '依存追加', 'workspace 設定'.
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Cargo.toml Style & Structure

## Scope

- Creating new and editing existing Cargo.toml files
- Adding and updating dependencies
- Setting package metadata (authors, license, description)
- Editing workspace configuration (`[workspace]`, member crates)
- Reviewing Rust project manifests

## Out of Scope

- Style for Rust source code → see the `rust-style` Rule
- Build cache configuration → see the `rust-build-cache` Rule
- Integrating dependency vulnerability detection into CI → see the `setup-ci` Skill

## Key Points

### 1. Formatting

- Use 4-space indentation (same as Rust code)
- Maximum line width is 100 characters
- Insert one blank line between sections (no blank line between a section header and its key-value lines)

### 2. Section Order

- Place `[package]` at the very top of the file
- Within `[package]`: `name` → `version` → other keys → `description` (last)
- Within other sections: alphabetical (version sort) on key names

### 3. Key-Value Pairs

- Standard key names are bare keys (no quoting)
- One ASCII space around `=`: `name = "my-crate"`
- Key names start at the beginning of the line (no indentation)

### 4. Array Values

```toml
# When it fits on one line
default = ["feature1", "feature2"]

# When it does not: block indent + trailing comma
some_feature = [
    "another_feature",
    "yet_another_feature",
    "some_dependency?/some_feature",
]
```

### 5. Table Values

```toml
# When it fits on one line: inline
[dependencies]
crate1 = { path = "crate1", version = "1.2.3" }

# When it does not: expanded form
[dependencies.long_crate_name]
path = "long_path_name"
version = "4.5.6"
```

### 6. Strings

- Use multi-line strings for values that contain newlines (avoid `\n` escapes)

### 7. Metadata

- `authors`: `Full Name <email@address>` format
- `license`: a valid SPDX expression (e.g., `MIT OR Apache-2.0`)
- `description`: wrap at 80 columns; do not start with the crate name

### 8. Dependency Hygiene

- Remove unused dependencies. Detect with `cargo +nightly udeps` (see "Dependency Analysis" in the `quality-checks` Rule for details)
- Prefer dependencies that are actively maintained and have no known vulnerabilities (verify with `cargo audit`)

## Common Pitfalls

1. **Key order violation in `[package]`**: writing `description` first, or `version` before `name` → reorder to the prescribed order
2. **Blank line between section header and key-value lines**: an unintentional blank line → remove it
3. **Free-form text in `license`**: use SPDX expressions instead of phrases like "MIT License"
4. **`authors` without an email**: keep the `Taro Tanaka <taro@example.com>` format
5. **Leaving unused dependencies in place**: a debt in build time and security. Check periodically with `cargo +nightly udeps`

## Project-Specific Conventions

- When using a workspace: consolidate the common parts of `[package]` fields between the root `Cargo.toml` and member crates' `Cargo.toml` into `[workspace.package]`
- Unify versions in `[workspace.dependencies]` and have each member crate inherit them via `{ workspace = true }`

## Related Rules / Skills

- Universal constraints: `rust-style`, `quality-checks` (Dependency Analysis section)
- Related Skills: `setup-ci` (integrate `cargo audit` / `cargo +nightly udeps` into CI), `rust-build-cache` (sccache configuration)

## References

- Rust Style Guide (Cargo.toml): <https://doc.rust-lang.org/nightly/style-guide/>
- Cargo Book — Manifest Format: <https://doc.rust-lang.org/cargo/reference/manifest.html>
- SPDX License List: <https://spdx.org/licenses/>
