---
paths:
  - "**/*.rs"
---

# Rust Coding Style Rules

Follow the official Rust Style Guide (https://doc.rust-lang.org/style-guide/).
Use `rustfmt` defaults as the baseline and adhere to the rules below.

## Formatting Basics

- Indentation: 4 spaces (no tabs)
- Max line width: 100 characters
- Comment lines: 80 characters (excluding indentation) or max width, whichever is smaller
- Use block indent, not visual indent
- No trailing whitespace
- Newline at end of file

## Trailing Commas

Use trailing commas in multi-line comma-separated lists. Omit them on single lines.

```rust
// Multi-line: trailing comma
function_call(
    argument,
    another_argument,
);

// Single line: no trailing comma
function_call(argument, another_argument)
```

## Naming Conventions

| Item | Style | Example |
|---|---|---|
| Types, Traits, Enums | `UpperCamelCase` | `MyStruct`, `MyTrait` |
| Enum variants | `UpperCamelCase` | `Some`, `None` |
| Functions, Methods | `snake_case` | `do_something` |
| Local variables | `snake_case` | `my_var` |
| Struct fields | `snake_case` | `field_name` |
| Constants, immutable statics | `SCREAMING_SNAKE_CASE` | `MAX_SIZE` |
| Macros | `snake_case` | `my_macro!` |
| Modules | `snake_case` | `my_module` |

When a reserved word is needed as a name, use raw identifiers (`r#type`) or a trailing underscore (`type_`). Avoid misspelling (`typ`).

## Item Order in Files

1. `extern crate` statements
2. `use` statements (`self`/`super` first, glob imports last)
3. Module declarations (`mod foo;`)
4. Other items

## Function Definitions

```rust
// Fits on one line
fn foo(arg1: i32, arg2: i32) -> i32 {
    ...
}

// Does not fit: each argument on its own line
fn foo(
    arg1: i32,
    arg2: i32,
) -> i32 {
    ...
}
```

- No comments inside signatures
- When the argument list is multi-line, place each argument on its own line with a trailing comma

## Structs and Enums

```rust
struct Foo {
    a: A,
    b: B,
}

enum FooBar {
    First(u32),
    Second,
    Error {
        err: Box<Error>,
        line: u32,
    },
}
```

- Prefer unit structs: `struct Foo;` over `struct Foo {}` or `struct Foo()`
- When a field type is long, break after `:` with block indent

## Traits and Impls

```rust
trait Foo: Debug + Bar {}

impl Bar for Foo {
    ...
}
```

- When trait bounds are long, break before `+` with block indent

## Where Clauses

```rust
fn function<T, U>(args)
where
    T: Bound,
    U: AnotherBound,
{
    body
}
```

- Place `where` right after the closing parenthesis (same line)
- Each constraint on its own line with block indent
- Use trailing commas

## Use Statements

```rust
use std::collections::HashMap;
use std::io::{self, Read, Write};
```

- Sort alphabetically (version sort) within groups
- Place `self` and `super` before other names
- Normalize unnecessary nesting: `use a::{b};` → `use a::b;`

## Expressions

### Block Expressions
- Empty blocks: `{}`
- Single-expression blocks may be one line in expression context: `let foo = { expr };`

### Closures
- Omit `{}` when possible
- `|arg1, arg2| expr`

### Method Chains
- When multi-line, break before `.` with block indent

```rust
let foo = bar
    .baz?
    .qux();
```

### Match Expressions
- Do not place `|` at the beginning of patterns
- Block indent each arm
- Single-expression arms on the same line; multiple statements use a block

```rust
match foo {
    Foo::Bar => value,
    Foo::Baz(x) => {
        let y = process(x);
        y.result()
    }
}
```

### If/Else
- Prefer expression form when possible

```rust
// Preferred
let x = if y { 1 } else { 0 };

// Avoid
let x;
if y { x = 1; } else { x = 0; }
```

## Types

- Break type expressions at the outermost scope
- Break trait bounds before `+`

```rust
// Preferred
Foo<
    Bar,
    Baz<Type1, Type2>,
>

// Avoid
Foo<Bar, Baz<
    Type1,
    Type2,
>>
```

## Let Statements

```rust
let pattern: Type = expr;

// Long expression: break after =
let pattern: Type =
    expr;

// Long type too: break after :
let pattern:
    Type =
    expr;
```

## Comments

- Prefer line comments (`//`) over block comments (`/* */`)
- Use `///` for doc comments (outer) and `//!` for module/crate-level docs only
- Single space after `//`

## Attributes

- Place each attribute on its own line
- Merge multiple `#[derive(...)]` into one

```rust
#[derive(Debug, Clone, PartialEq)]
#[repr(C)]
struct Foo { ... }
```

## Extern

- Always specify the ABI explicitly: `extern "C" fn` (avoid bare `extern fn`)

## General Advice

- Avoid `#[path]` attribute on modules
- Leverage expression-oriented programming (return values from `if`, `match`, etc.)
- Use `rustfmt` and `clippy` actively
