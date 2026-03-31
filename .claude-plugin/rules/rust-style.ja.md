---
paths:
  - "**/*.rs"
---

# Rust コーディングスタイルルール

公式 Rust スタイルガイド (https://doc.rust-lang.org/style-guide/) に従う。
`rustfmt` のデフォルトをベースラインとし、以下のルールに準拠する。

## フォーマットの基本

- インデント: 4スペース（タブ不可）
- 最大行幅: 100文字
- コメント行: 80文字（インデントを除く）または最大幅のいずれか小さい方
- ビジュアルインデントではなく、ブロックインデントを使用する
- 末尾の空白は不可
- ファイル末尾に改行を入れる

## 末尾カンマ

複数行のカンマ区切りリストでは末尾カンマを使用する。1行の場合は省略する。

```rust
// 複数行: 末尾カンマあり
function_call(
    argument,
    another_argument,
);

// 1行: 末尾カンマなし
function_call(argument, another_argument)
```

## 命名規則

| 項目 | スタイル | 例 |
|------|---------|-----|
| 型、トレイト、列挙型 | `UpperCamelCase` | `MyStruct`, `MyTrait` |
| 列挙型バリアント | `UpperCamelCase` | `Some`, `None` |
| 関数、メソッド | `snake_case` | `do_something` |
| ローカル変数 | `snake_case` | `my_var` |
| 構造体フィールド | `snake_case` | `field_name` |
| 定数、不変 static | `SCREAMING_SNAKE_CASE` | `MAX_SIZE` |
| マクロ | `snake_case` | `my_macro!` |
| モジュール | `snake_case` | `my_module` |

予約語を名前として使用する必要がある場合は、生識別子（`r#type`）または末尾アンダースコア（`type_`）を使用する。スペルミス（`typ`）は避ける。

## ファイル内の項目順序

1. `extern crate` 文
2. `use` 文（`self`/`super` を先頭に、グロブインポートを最後に）
3. モジュール宣言（`mod foo;`）
4. その他の項目

## 関数定義

```rust
// 1行に収まる場合
fn foo(arg1: i32, arg2: i32) -> i32 {
    ...
}

// 収まらない場合: 各引数を個別の行に
fn foo(
    arg1: i32,
    arg2: i32,
) -> i32 {
    ...
}
```

- シグネチャ内にコメントを入れない
- 引数リストが複数行の場合、各引数を個別の行に配置し末尾カンマを付ける

## 構造体と列挙型

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

- ユニット構造体を優先: `struct Foo;`（`struct Foo {}` や `struct Foo()` より）
- フィールドの型が長い場合は `:` の後でブロックインデントして改行する

## トレイトと impl

```rust
trait Foo: Debug + Bar {}

impl Bar for Foo {
    ...
}
```

- トレイト境界が長い場合は `+` の前でブロックインデントして改行する

## where 句

```rust
fn function<T, U>(args)
where
    T: Bound,
    U: AnotherBound,
{
    body
}
```

- `where` は閉じ括弧の直後（同じ行）に配置する
- 各制約を個別の行にブロックインデントで配置する
- 末尾カンマを使用する

## use 文

```rust
use std::collections::HashMap;
use std::io::{self, Read, Write};
```

- グループ内でアルファベット順（バージョンソート）に並べる
- `self` と `super` は他の名前より前に配置する
- 不要なネストを正規化する: `use a::{b};` → `use a::b;`

## 式

### ブロック式
- 空ブロック: `{}`
- 単一式ブロックは式コンテキストでは1行にしてもよい: `let foo = { expr };`

### クロージャ
- 可能な場合は `{}` を省略する
- `|arg1, arg2| expr`

### メソッドチェーン
- 複数行の場合、`.` の前でブロックインデントして改行する

```rust
let foo = bar
    .baz?
    .qux();
```

### match 式
- パターンの先頭に `|` を付けない
- 各アームをブロックインデントする
- 単一式のアームは同じ行に、複数文はブロックを使用する

```rust
match foo {
    Foo::Bar => value,
    Foo::Baz(x) => {
        let y = process(x);
        y.result()
    }
}
```

### if/else
- 可能な場合は式形式を優先する

```rust
// 推奨
let x = if y { 1 } else { 0 };

// 非推奨
let x;
if y { x = 1; } else { x = 0; }
```

## 型

- 型式は最も外側のスコープで改行する
- トレイト境界は `+` の前で改行する

```rust
// 推奨
Foo<
    Bar,
    Baz<Type1, Type2>,
>

// 非推奨
Foo<Bar, Baz<
    Type1,
    Type2,
>>
```

## let 文

```rust
let pattern: Type = expr;

// 式が長い場合: = の後で改行
let pattern: Type =
    expr;

// 型も長い場合: : の後で改行
let pattern:
    Type =
    expr;
```

## コメント

- ブロックコメント（`/* */`）よりも行コメント（`//`）を優先する
- ドキュメントコメントには `///`（外部）を使用し、`//!` はモジュール/クレートレベルのドキュメントにのみ使用する
- `//` の後にスペースを1つ入れる

## アトリビュート

- 各アトリビュートを個別の行に配置する
- 複数の `#[derive(...)]` は1つにまとめる

```rust
#[derive(Debug, Clone, PartialEq)]
#[repr(C)]
struct Foo { ... }
```

## extern

- ABI は常に明示的に指定する: `extern "C" fn`（裸の `extern fn` は避ける）

## 一般的なアドバイス

- モジュールで `#[path]` アトリビュートを使用しない
- 式指向プログラミングを活用する（`if`、`match` などから値を返す）
- `rustfmt` と `clippy` を積極的に使用する
