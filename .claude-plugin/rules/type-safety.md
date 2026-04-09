# 型安全性ガイドライン

プロジェクトの型チェック設定と型安全なコーディングパターンを定義する。

## Rust 型安全性

Rust はコンパイラレベルで強い型安全性を提供するが、以下のパターンで更に安全性を高める。

### TS-R1: Newtype パターン

ドメイン固有の値には newtype を使用し、型の取り違えを防止する:

```rust
// NG: 生の型をそのまま使用
fn get_user(id: i64) -> User { ... }
fn get_order(id: i64) -> Order { ... }
// get_user(order_id) がコンパイル可能 — 危険

// OK: newtype で区別
struct UserId(i64);
struct OrderId(i64);
fn get_user(id: UserId) -> User { ... }
fn get_order(id: OrderId) -> Order { ... }
// get_user(order_id) はコンパイルエラー
```

適用対象: ID、金額、メールアドレス等のドメイン値

### TS-R2: 安全な数値キャスト

`as` による数値キャストは精度損失やオーバーフローのリスクがある:

```rust
// NG: 暗黙の切り捨て
let x: i64 = 300;
let y: i8 = x as i8; // 44 — サイレントオーバーフロー

// OK: 明示的な変換
let y: i8 = x.try_into().map_err(|_| AppError::Overflow)?;
```

`as` は `usize` ↔ ポインタ変換等の安全が保証される場合のみ許可。

### TS-R3: 網羅的パターンマッチ

`match` は必ず全パターンを網羅し、`_ =>` ワイルドカードは避ける:

```rust
// NG: 新しいバリアント追加時にコンパイルエラーにならない
match status {
    Status::Active => { ... },
    _ => { ... },  // 新バリアントが暗黙的にここに落ちる
}

// OK: 明示的に全バリアントを列挙
match status {
    Status::Active => { ... },
    Status::Inactive => { ... },
    Status::Suspended => { ... },
}
```

例外: 外部クレートの `#[non_exhaustive]` 列挙型は `_ =>` が必要。

### TS-R4: Option/Result の安全な処理

```rust
// NG: パニックのリスク
let value = map.get("key").unwrap();

// OK: エラーハンドリング
let value = map.get("key").ok_or(AppError::NotFound("key"))?;

// OK: デフォルト値
let value = map.get("key").unwrap_or(&default);
```

`unwrap()` はテストコードでのみ許可。プロダクションコードでは `?` 演算子、`unwrap_or`、`unwrap_or_else` を使用する。

### TS-R5: PhantomData による型レベル状態管理

状態遷移を型で表現し、不正な状態遷移をコンパイル時に防止する:

```rust
struct Draft;
struct Published;

struct Article<State> {
    title: String,
    body: String,
    _state: std::marker::PhantomData<State>,
}

impl Article<Draft> {
    fn publish(self) -> Article<Published> { ... }
}
// Article<Published> には publish() がない — 二重公開を防止
```

## TypeScript 型安全性（将来対応）

TypeScript プロジェクトでは以下の設定を必須とする:

### TS-T1: tsconfig.json 厳格モード

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "exactOptionalPropertyTypes": true
  }
}
```

### TS-T2: any 禁止

`any` の使用は原則禁止。やむを得ない場合は `unknown` + 型ガードを使用する:

```typescript
// NG
function parse(data: any): User { ... }

// OK
function parse(data: unknown): User {
  if (!isUser(data)) throw new ValidationError();
  return data;
}
```

## review-worker との連携

review-worker のカテゴリ B（Design and Structure）で以下を確認:

- TS-R1: ドメイン値に newtype が使用されているか
- TS-R2: `as` キャストに正当な理由があるか
- TS-R3: `match` が `_ =>` ワイルドカードを避けているか
- TS-R4: `unwrap()` がプロダクションコードで使用されていないか

## 執行レベル

| ルール | 現在の執行レベル | 目標 |
|--------|---------------|------|
| TS-R1 (Newtype) | L1 ドキュメント | L2 AI レビュー |
| TS-R2 (安全キャスト) | L3 CI (`clippy::cast_possible_truncation`) | L3 維持 |
| TS-R3 (網羅的 match) | L5 コンパイラ（`#[deny(unreachable_patterns)]`） | L5 維持 |
| TS-R4 (unwrap 禁止) | L2 AI レビュー | L3 CI (`clippy::unwrap_used`) |
| TS-R5 (PhantomData) | L1 ドキュメント | L2 AI レビュー |
