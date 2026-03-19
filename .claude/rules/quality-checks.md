---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Quality Check Commands

parallel-worker, review-worker, およびその他のエージェントが品質チェックを実行する際の統一コマンド仕様。全エージェントはこのルールに定義されたコマンドを使用すること。

## rustfmt

```bash
rustfmt --check src/**/*.rs tests/**/*.rs
```

- src と tests の両方を対象とする（片方だけチェックしない）
- 自動修正時は `--check` を外して実行: `rustfmt src/**/*.rs tests/**/*.rs`

## clippy

```bash
cargo clippy --quiet --all-targets -- -D warnings
```

- `--all-targets`: テストコード、ベンチマーク、examples も含めてチェック
- `-D warnings`: 全警告をエラーとして扱う
- `--quiet`: 進捗表示を抑制

## test

```bash
cargo test --quiet
```

- 全テスト（ユニット + 統合）を実行
- 特定テストのみ実行する場合: `cargo test --test {test_name} -- --nocapture`
