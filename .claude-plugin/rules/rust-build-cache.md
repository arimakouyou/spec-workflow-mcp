---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Rust ビルドキャッシュ

Rust プロジェクトで cargo コマンドを実行する全エージェント向けのビルドキャッシュ設定ルール。
worktree 間でのコンパイル結果共有により、ビルド・テスト・lint の大幅な高速化を実現する。

## sccache の検出と利用

sccache はコンパイル結果をキャッシュし、同一ソースの再コンパイルを回避する。worktree が異なっても同一のキャッシュを透過的に共有でき、並列ビルドにも安全（内部でロック制御）。

### 推奨パターン: 環境変数前置方式

Claude Code の Bash ツールはコマンド間でシェル状態を保持しない。`export` は同一 Bash 呼び出し内でのみ有効なため、各 cargo コマンドに `RUSTC_WRAPPER=sccache` を前置する方式を推奨する。

```bash
# sccache 検出
if command -v sccache >/dev/null 2>&1; then
  RUSTC_WRAPPER=sccache cargo fmt --all -- --check
  RUSTC_WRAPPER=sccache cargo clippy --quiet --all-targets -- -D warnings
  RUSTC_WRAPPER=sccache cargo test --quiet
else
  cargo fmt --all -- --check
  cargo clippy --quiet --all-targets -- -D warnings
  cargo test --quiet
fi
```

単一コマンドの場合:

```bash
# sccache があれば使う、なければ通常実行
if command -v sccache >/dev/null 2>&1; then
  RUSTC_WRAPPER=sccache cargo test --quiet
else
  cargo test --quiet
fi
```

### export 方式（単一 Bash 呼び出し内でコマンドを連続実行する場合）

```bash
if command -v sccache >/dev/null 2>&1; then
  export RUSTC_WRAPPER=sccache
fi
cargo fmt --all -- --check && cargo clippy --quiet --all-targets -- -D warnings && cargo test --quiet
```

## Worktree 環境でのキャッシュ戦略

| メカニズム | 推奨 | 理由 |
|-----------|------|------|
| sccache (`RUSTC_WRAPPER`) | 推奨 | worktree 間でコンパイル結果を透過的に共有。並列安全 |
| `CARGO_TARGET_DIR` 共有 | **禁止** | 並列 worker がロック競合を起こす。Cargo は `target/` 内でファイルロックを使用しており、複数プロセスが同一 target dir を使うとビルド失敗やデッドロックの原因になる |
| Cargo レジストリキャッシュ | 対応不要 | `~/.cargo/registry` と `~/.cargo/git` は全プロセスで自動共有 |
| インクリメンタルコンパイル | 対応不要 | デバッグビルドではデフォルト有効 |

## cargo-nextest（オプション）

cargo-nextest はテストバイナリの並列実行が高速。利用可能な場合はオプションとして活用できる。ただし `quality-checks.md` の `cargo test` コマンドが正式仕様であり、nextest への切替はそちらで一括管理する。

```bash
# nextest が利用可能か確認（利用は任意）
command -v cargo-nextest >/dev/null 2>&1 && echo "cargo-nextest available"
```

## トラブルシューティング

### sccache キャッシュ破損でビルドが失敗する場合

```bash
sccache --stop-server
sccache --start-server
```

サーバー再起動で解消しない場合はキャッシュをクリア:

```bash
sccache --stop-server
rm -rf ${SCCACHE_DIR:-~/.cache/sccache}
sccache --start-server
```

### sccache が未インストールの場合

フォールバックとして通常の cargo コマンドがそのまま動作する。sccache の有無に関わらずビルドは成功する設計。
