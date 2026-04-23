---
name: cargo-toml
description: |
  Cargo.toml のフォーマットと構造に関する規約。`[package]` セクションの配置とキー順 (name → version → ... → description)、インデント (4 spaces)、行幅 (100 文字)、配列/テーブル値の書き方、SPDX ライセンス式、authors 形式、依存衛生（`cargo +nightly udeps` による未使用検出、`cargo audit` による脆弱性チェック）をカバー。Cargo.toml 編集時、依存追加時、パッケージメタデータ設定時、workspace 設定時、Rust プロジェクトのマニフェスト review 時に参照。
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Cargo.toml Style & Structure

## 対象

- Cargo.toml の新規作成および編集
- 依存関係の追加・更新
- パッケージメタデータ (authors, license, description) の設定
- workspace 設定（`[workspace]`、member crate）の編集
- Rust プロジェクト manifest のレビュー

## 対象外

- Rust ソースコードのスタイル → `rust-style` Rule を参照
- ビルドキャッシュの設定 → `rust-build-cache` Rule を参照
- 依存関係の脆弱性検出の CI 組み込み → `setup-ci` Skill を参照

## 主要観点

### 1. Formatting

- インデントは 4 スペース（Rust コードと同じ）
- 最大行幅は 100 文字
- セクション間には空行 1 行を入れる（セクションヘッダとその key-value の間には空行を入れない）

### 2. Section Order

- `[package]` はファイル最上部に配置
- `[package]` 内: `name` → `version` → その他のキー → `description`（最後）
- その他のセクション内: キー名をアルファベット順（version sort）

### 3. Key-Value Pairs

- 標準的なキー名は bare keys（quote なし）
- `=` の周囲は半角スペース 1 つ: `name = "my-crate"`
- キー名は行頭から記述（インデントなし）

### 4. Array Values

```toml
# 1 行に収まる場合
default = ["feature1", "feature2"]

# 収まらない場合: block indent + trailing comma
some_feature = [
    "another_feature",
    "yet_another_feature",
    "some_dependency?/some_feature",
]
```

### 5. Table Values

```toml
# 1 行に収まる場合: inline
[dependencies]
crate1 = { path = "crate1", version = "1.2.3" }

# 収まらない場合: expanded form
[dependencies.long_crate_name]
path = "long_path_name"
version = "4.5.6"
```

### 6. Strings

- 改行を含む値は multi-line string を使う（`\n` エスケープを避ける）

### 7. Metadata

- `authors`: `Full Name <email@address>` 形式
- `license`: 有効な SPDX 表現（例: `MIT OR Apache-2.0`）
- `description`: 80 桁で折り返し、crate 名で書き出さない

### 8. Dependency Hygiene

- 未使用の依存は削除する。`cargo +nightly udeps` で検出（詳細は `quality-checks` Rule の "Dependency Analysis" を参照）
- 継続的にメンテナンスされ既知の脆弱性がない依存を優先する（`cargo audit` で検証）

## よくある落とし穴

1. **`[package]` 内のキー順違反**: `description` を先頭に書く / `version` が `name` の上 → 規定順に並べ直す
2. **セクションヘッダと key-value の間に空行**: 意図せず空行を入れる → 削除する
3. **`license` に自由記述**: 「MIT License」などではなく SPDX 表現を使う
4. **`authors` に email なし**: `Taro Tanaka <taro@example.com>` の形式を守る
5. **未使用依存の放置**: ビルド時間とセキュリティ面の負債。`cargo +nightly udeps` で定期確認

## プロジェクト固有の規約

- workspace 利用時: ルート `Cargo.toml` と member crate の `Cargo.toml` で `[package]` フィールドの共通部分を `[workspace.package]` に集約する
- `[workspace.dependencies]` でバージョン統一を行い、各 member crate は `{ workspace = true }` で継承

## 関連 Rule / Skill

- 普遍制約: `rust-style`, `quality-checks`（Dependency Analysis セクション）
- 関連 Skill: `setup-ci`（CI に `cargo audit` / `cargo +nightly udeps` を組み込む）、`rust-build-cache`（sccache 設定）

## 参考リンク

- Rust Style Guide (Cargo.toml): <https://doc.rust-lang.org/nightly/style-guide/>
- Cargo Book — Manifest Format: <https://doc.rust-lang.org/cargo/reference/manifest.html>
- SPDX License List: <https://spdx.org/licenses/>
