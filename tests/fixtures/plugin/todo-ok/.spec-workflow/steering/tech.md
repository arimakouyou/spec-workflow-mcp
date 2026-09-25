# Tech

## Stack

| Item | Choice | Version |
|---|---|---|
| language | rust | 1.93 |
| framework | axum | 0.8 |

## Test Commands

| Layer | Command |
|---|---|
| UT | cargo test --lib |
| CT | - |
| IT | cargo test --test 'it_*' |
| ST | - |
| E2E | cargo test --test 'e2e_*' |
| SMK | cargo test --test 'smoke_*' |

## Quality Commands

| Check | Command |
|---|---|
| format | cargo fmt --check |
| lint | cargo clippy --all-targets -- -D warnings |
| audit | - |

## Test Layout

- UT: {stem}_tests.rs beside the source file, included via #[cfg(test)] #[path] mod tests
- IT: tests/it_{name}.rs

## Wiring Files

- Cargo.toml
- src/lib.rs
- src/*/mod.rs

## Health

- Path: /health

## Sigcheck

- Language: rust
