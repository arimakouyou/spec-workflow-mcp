# Tech

プロジェクト全体の技術的事実の正本。spec 固有の追加依存・ツールは各 spec の design(DEP / TOOL)が所有する。
greenfield では、ここに書く値は計画値として扱う。P0 のブートストラップが完了した時点で実体になる。

## Stack

| Item | Choice | Version |
|---|---|---|
| language | [rust] | [レジストリで確認した版] |
| [framework] | [axum] | [版] |

## Test Commands

| Layer | Command |
|---|---|
| UT | [cargo test --lib] |
| CT | [コマンド または -] |
| IT | [cargo test --test 'it_*'] |
| ST | [コマンド または -] |
| E2E | [コマンド または -] |
| SMK | [スモークテストのコマンド または -] |

## Quality Commands

| Check | Command |
|---|---|
| format | [cargo fmt --check] |
| lint | [cargo clippy --all-targets -- -D warnings] |
| audit | [cargo audit または -] |

## Test Layout

- UT: [{stem}_tests.rs をソースの隣に置き、#[cfg(test)] #[path] mod tests で読み込む]
- CT: [tests/ct_{component}.rs]
- IT: [tests/it_{name}.rs]

## Wiring Files

- [Cargo.toml]

## Health

- Path: [/health]

## Sigcheck

- Language: [rust | dotnet | unsupported (理由)]
