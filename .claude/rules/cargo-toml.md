---
paths:
  - "**/Cargo.toml"
---

# Cargo.toml Style Rules

Follow the official Rust Style Guide conventions for Cargo.toml.

## Formatting

- Indentation: 4 spaces (same as Rust code)
- Max line width: 100 characters
- One blank line between sections (no blank line between a section header and its key-value pairs)

## Section Order

- Place `[package]` at the top of the file
- Within `[package]`: `name` → `version` → other keys → `description` (last)
- Within other sections: sort key names alphabetically (version sort)

## Key-Value Pairs

- Use bare keys for standard key names (no quotes)
- Single space around `=`: `name = "my-crate"`
- No indentation on key names (start at the beginning of the line)

## Array Values

```toml
# Fits on one line
default = ["feature1", "feature2"]

# Does not fit: block indent + trailing comma
some_feature = [
    "another_feature",
    "yet_another_feature",
    "some_dependency?/some_feature",
]
```

## Table Values

```toml
# Fits on one line: inline
[dependencies]
crate1 = { path = "crate1", version = "1.2.3" }

# Does not fit: expanded form
[dependencies.long_crate_name]
path = "long_path_name"
version = "4.5.6"
```

## Strings

- Use multi-line strings for values containing newlines (not `\n` escapes)

## Metadata

- `authors`: use `Full Name <email@address>` format
- `license`: use valid SPDX expressions (e.g., `MIT OR Apache-2.0`)
- `description`: wrap at 80 columns, do not start with the crate name
