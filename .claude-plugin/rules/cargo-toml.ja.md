---
paths:
  - "**/Cargo.toml"
---

# Cargo.toml スタイルルール

Cargo.toml は公式 Rust スタイルガイドの規約に従う。

## フォーマット

- インデント: 4スペース（Rust コードと同じ）
- 最大行幅: 100文字
- セクション間に1行の空行（セクションヘッダーとキー・バリューペアの間に空行は入れない）

## セクション順序

- `[package]` をファイルの先頭に配置
- `[package]` 内: `name` → `version` → その他のキー → `description`（最後）
- その他のセクション内: キー名をアルファベット順（バージョンソート）にソート

## キー・バリューペア

- 標準キー名にはベアキーを使用（引用符なし）
- `=` の前後にスペース1つ: `name = "my-crate"`
- キー名にインデントなし（行の先頭から開始）

## 配列値

```toml
# 1行に収まる場合
default = ["feature1", "feature2"]

# 収まらない場合: ブロックインデント + 末尾カンマ
some_feature = [
    "another_feature",
    "yet_another_feature",
    "some_dependency?/some_feature",
]
```

## テーブル値

```toml
# 1行に収まる場合: インライン
[dependencies]
crate1 = { path = "crate1", version = "1.2.3" }

# 収まらない場合: 展開形
[dependencies.long_crate_name]
path = "long_path_name"
version = "4.5.6"
```

## 文字列

- 改行を含む値にはマルチライン文字列を使用する（`\n` エスケープではなく）

## メタデータ

- `authors`: `Full Name <email@address>` 形式を使用
- `license`: 有効な SPDX 式を使用（例: `MIT OR Apache-2.0`）
- `description`: 80カラムで折り返し、クレート名で始めない
