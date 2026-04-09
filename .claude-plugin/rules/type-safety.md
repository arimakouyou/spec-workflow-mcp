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

## C# 型安全性

C# は .NET の型システムと Nullable Reference Types (NRT) により強い型安全性を提供する。以下のパターンで更に安全性を高める。

### TS-C1: Nullable Reference Types (NRT)

プロジェクト全体で NRT を有効化し、null 安全性をコンパイラで検証する:

```xml
<!-- Directory.Build.props -->
<PropertyGroup>
  <Nullable>enable</Nullable>
</PropertyGroup>
```

```csharp
// NG: null-forgiving operator をプロダクションコードで使用
var user = repository.FindById(id)!;

// OK: null チェックを明示
var user = await repository.FindByIdAsync(id)
    ?? throw new NotFoundException($"User {id} not found");

// OK: nullable 型で明示
public async Task<User?> FindByIdAsync(UserId id);
```

`!` null-forgiving operator はテストコードでのみ許可。プロダクションコードでは `??`、`?.`、`??=` を使用する。

### TS-C2: Strong Typing（readonly record struct）

ドメイン固有の値には readonly record struct を使用し、型の取り違えを防止する:

```csharp
// NG: 生の型をそのまま使用
public User GetUser(int id) { ... }
public Order GetOrder(int id) { ... }
// GetUser(orderId) がコンパイル可能 — 危険

// OK: readonly record struct で区別
public readonly record struct UserId(int Value);
public readonly record struct OrderId(int Value);
public User GetUser(UserId id) { ... }
public Order GetOrder(OrderId id) { ... }
// GetUser(orderId) はコンパイルエラー
```

適用対象: ID、金額、メールアドレス等のドメイン値

### TS-C3: 網羅的パターンマッチ（switch expression）

switch expression は全パターンを網羅し、`_` ワイルドカードは避ける:

```csharp
// NG: 新しいバリアント追加時にコンパイル警告にならない
var message = status switch
{
    Status.Active => "Active",
    _ => "Unknown",  // 新バリアントが暗黙的にここに落ちる
};

// OK: 明示的に全バリアントを列挙
var message = status switch
{
    Status.Active => "Active",
    Status.Inactive => "Inactive",
    Status.Suspended => "Suspended",
};
// 新バリアント追加時にコンパイラ警告 CS8509
```

`<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` と併用し、網羅漏れをビルドエラーにする。

### TS-C4: Result パターン

予期されるエラーには例外ではなく Result パターンを使用する:

```csharp
// NG: 業務エラーに例外を使用
public User CreateUser(CreateUserRequest req)
{
    if (string.IsNullOrEmpty(req.Name))
        throw new ValidationException("Name is required");
    // ...
}

// OK: OneOf / カスタム Result で表現
public OneOf<User, ValidationError> CreateUser(CreateUserRequest req)
{
    if (string.IsNullOrEmpty(req.Name))
        return new ValidationError("Name is required");
    // ...
    return user;
}
```

例外は真に例外的な状況（ネットワーク障害、DB 接続断等）にのみ使用する。

### TS-C5: Immutability Defaults

デフォルトで不変を志向し、可変は必要な場合のみ許可する:

```csharp
// OK: record で不変データ型
public record UserResponse(string Name, string Email, DateTime CreatedAt);

// OK: init-only property
public class AppConfig
{
    public required string DatabaseUrl { get; init; }
    public required int Port { get; init; }
}

// OK: readonly コレクション
public IReadOnlyList<User> GetUsers() => users.AsReadOnly();
```

`record`、`init`、`required`、`IReadOnlyList<T>`、`IReadOnlyDictionary<K,V>` を活用する。

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

### Rust
- TS-R1: ドメイン値に newtype が使用されているか
- TS-R2: `as` キャストに正当な理由があるか
- TS-R3: `match` が `_ =>` ワイルドカードを避けているか
- TS-R4: `unwrap()` がプロダクションコードで使用されていないか

### C#
- TS-C1: NRT が有効で `!` null-forgiving operator がプロダクションコードで使用されていないか
- TS-C2: ドメイン値に readonly record struct が使用されているか
- TS-C3: switch expression が網羅的か（`_` ワイルドカードを避けているか）
- TS-C4: 業務エラーに Result パターンが使用されているか
- TS-C5: デフォルトで不変（record, init, IReadOnlyList）が使用されているか

## 執行レベル

| ルール | 現在の執行レベル | 目標 |
|--------|---------------|------|
| TS-R1 (Newtype) | L1 ドキュメント | L2 AI レビュー |
| TS-R2 (安全キャスト) | L3 CI (`clippy::cast_possible_truncation`) | L3 維持 |
| TS-R3 (網羅的 match) | L5 コンパイラ（`#[deny(unreachable_patterns)]`） | L5 維持 |
| TS-R4 (unwrap 禁止) | L2 AI レビュー | L3 CI (`clippy::unwrap_used`) |
| TS-R5 (PhantomData) | L1 ドキュメント | L2 AI レビュー |
| TS-C1 (NRT 有効化) | L5 コンパイラ（`<Nullable>enable</Nullable>`） | L5 維持 |
| TS-C2 (Strong Typing) | L1 ドキュメント | L2 AI レビュー |
| TS-C3 (網羅的 switch) | L3 CI（CS8509 + TreatWarningsAsErrors） | L3 維持 |
| TS-C4 (Result パターン) | L1 ドキュメント | L2 AI レビュー |
| TS-C5 (Immutability) | L1 ドキュメント | L2 AI レビュー |
