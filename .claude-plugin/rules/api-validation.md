# API バリデーションスキーマ

API リクエストのバリデーションを厳格に定義し、未知フィールドの拒否とスキーマの一貫性を確保する。

## 基本原則

1. **未知フィールド拒否**: リクエスト DTO は未定義フィールドを受け入れない
2. **バリデーション層の明確化**: 型バリデーション → ビジネスバリデーション の2段階
3. **エラーレスポンスの一貫性**: design.md の Error Handling テーブルに準拠

## Rust (Serde) バリデーションパターン

### AV-R1: deny_unknown_fields

全リクエスト DTO に `#[serde(deny_unknown_fields)]` を付与する:

```rust
// OK: 未知フィールドを拒否
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CreateUserRequest {
    /// ユーザー名（2-50文字）
    name: String,
    /// メールアドレス
    email: String,
}

// NG: deny_unknown_fields なし — 任意のフィールドが黙殺される
#[derive(Deserialize)]
struct CreateUserRequest {
    name: String,
    email: String,
}
```

> **注意**: レスポンス DTO には `deny_unknown_fields` を付与しない（API バージョニングで新フィールドが追加される可能性があるため）。

### AV-R2: 型レベルバリデーション

Extractor レベルで型バリデーションを実行する（Axum パターン）:

```rust
// Axum: Json extractor がデシリアライズ時にバリデーション
async fn create_user(
    Json(payload): Json<CreateUserRequest>,  // 型不一致は自動的に 400
) -> Result<Json<UserResponse>, AppError> {
    // ここに到達した時点で payload は型安全
    service.create_user(payload).await
}
```

### AV-R3: ビジネスバリデーション

ビジネスルールのバリデーションはサービス層で実行する:

```rust
impl UserService {
    fn validate_create(&self, req: &CreateUserRequest) -> Result<(), AppError> {
        if req.name.len() < 2 || req.name.len() > 50 {
            return Err(AppError::BadRequest("name must be 2-50 chars"));
        }
        if !req.email.contains('@') {
            return Err(AppError::BadRequest("invalid email format"));
        }
        Ok(())
    }
}
```

### AV-R4: Enum バリデーション

文字列から Enum への変換には `#[serde(rename_all = "snake_case")]` を使用し、未定義値を拒否する:

```rust
#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum UserRole {
    Admin,
    Editor,
    Viewer,
}
// "admin" → OK, "superadmin" → デシリアライズエラー (400)
```

### AV-R5: Optional フィールドの明示

必須/任意フィールドを型で明示する:

```rust
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct UpdateUserRequest {
    /// 更新する場合のみ指定
    name: Option<String>,
    /// 更新する場合のみ指定
    email: Option<String>,
}
```

`Option<T>` のないフィールドは必須。リクエストに含まれなければ 400 エラー。

## C# (ASP.NET Core) バリデーションパターン

### AV-C1: [ApiController] + Model Validation

`[ApiController]` 属性で自動モデルバリデーションを有効化する:

```csharp
// OK: [ApiController] により ModelState 自動検証 + ProblemDetails レスポンス
[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> CreateUser(CreateUserRequest request)
    {
        // ここに到達した時点で request は ModelState 検証済み
        var user = await _service.CreateUserAsync(request);
        return CreatedAtAction(nameof(GetUser), new { id = user.Id }, user);
    }
}
```

Minimal API の場合は `[AsParameters]` または手動バリデーションを使用:

```csharp
app.MapPost("/users", async ([FromBody] CreateUserRequest request, IValidator<CreateUserRequest> validator) =>
{
    var result = validator.Validate(request);
    if (!result.IsValid)
        return Results.ValidationProblem(result.ToDictionary());
    // ...
});
```

### AV-C2: Data Annotations + FluentValidation

型レベルバリデーションは Data Annotations、ビジネスルールは FluentValidation で分離する:

```csharp
// Data Annotations: 型レベル制約
public class CreateUserRequest
{
    [Required]
    [StringLength(50, MinimumLength = 2)]
    public required string Name { get; init; }

    [Required]
    [EmailAddress]
    public required string Email { get; init; }
}

// FluentValidation: ビジネスルール
public class CreateUserRequestValidator : AbstractValidator<CreateUserRequest>
{
    public CreateUserRequestValidator(IUserRepository repository)
    {
        RuleFor(x => x.Email)
            .MustAsync(async (email, ct) => !await repository.ExistsAsync(email, ct))
            .WithMessage("Email already registered");
    }
}
```

### AV-C3: 未知フィールド拒否

ASP.NET Core ではデフォルトで未知 JSON プロパティを無視する。拒否するには `JsonSerializerOptions` を設定する:

```csharp
// Program.cs
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow;
});
```

> **注意**: レスポンス DTO には適用しない。リクエスト DTO のみ対象。

### AV-C4: Enum バリデーション

JSON 文字列と Enum の変換には `JsonStringEnumConverter` を使用し、未定義値を拒否する:

```csharp
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum UserRole
{
    Admin,
    Editor,
    Viewer,
}
// "Admin" → OK, "SuperAdmin" → デシリアライズエラー (400)
```

### AV-C5: Required / Optional の明示

`required` keyword と nullability で必須/任意を型レベルで明示する:

```csharp
public class UpdateUserRequest
{
    /// 更新する場合のみ指定
    public string? Name { get; init; }

    /// 更新する場合のみ指定
    public string? Email { get; init; }
}

public class CreateUserRequest
{
    /// 必須（required + non-nullable）
    public required string Name { get; init; }

    /// 必須
    public required string Email { get; init; }
}
```

`required` + non-nullable = 必須。`nullable (?)` = 任意。

## バリデーションエラーレスポンス

エラーレスポンス形式は design.md の Error Handling セクションに準拠する:

```json
{
  "error": {
    "code": "BadRequest",
    "message": "Validation failed: name must be 2-50 characters"
  }
}
```

| エラー種別 | HTTP Status | 発生元 |
|-----------|-------------|--------|
| 型不一致（JSON パースエラー） | 400 | Extractor (自動) |
| 未知フィールド | 400 | serde deny_unknown_fields (自動) |
| ビジネスルール違反 | 400 | サービス層 (手動) |
| 認証失敗 | 401 | 認証ミドルウェア |
| 認可失敗 | 403 | 認可ミドルウェア |

## spec-design との連携

design.md の Data Models セクションで DTO を定義する際に、以下を明記すること:

- 各フィールドの必須/任意
- 文字列フィールドの長さ制限
- Enum フィールドの許容値
- Rust: `deny_unknown_fields` の適用対象（リクエスト DTO）
- C#: `UnmappedMemberHandling.Disallow` の適用対象（リクエスト DTO）

## review-worker との連携

review-worker のカテゴリ C（Security）で以下を確認:

### Rust
- AV-R1: リクエスト DTO に `deny_unknown_fields` が付与されているか
- AV-R3: ビジネスバリデーションがサービス層で実行されているか
- AV-R5: 必須/任意フィールドが型で明示されているか

### C#
- AV-C1: `[ApiController]` またはバリデータが適用されているか
- AV-C2: 型制約と業務ルールが分離されているか（Data Annotations + FluentValidation）
- AV-C3: リクエスト DTO で未知フィールドが拒否されているか
- AV-C5: `required` / nullable で必須/任意が明示されているか

## 執行レベル

| ルール | 現在の執行レベル | 目標 |
|--------|---------------|------|
| AV-R1 (deny_unknown_fields) | L1 ドキュメント | L4 構造テスト（アーキテクチャテストで検証可能） |
| AV-R2 (型レベルバリデーション) | L5 型システム（Axum Extractor） | L5 維持 |
| AV-R3 (ビジネスバリデーション) | L2 AI レビュー | L2 維持 |
| AV-R4 (Enum バリデーション) | L5 型システム（serde） | L5 維持 |
| AV-R5 (Optional 明示) | L5 型システム（Rust Option） | L5 維持 |
| AV-C1 (ApiController 自動検証) | L5 フレームワーク（ASP.NET Core） | L5 維持 |
| AV-C2 (FluentValidation) | L2 AI レビュー | L3 CI（バリデータ登録テスト） |
| AV-C3 (未知フィールド拒否) | L1 ドキュメント | L4 構造テスト |
| AV-C4 (Enum バリデーション) | L5 型システム（JsonStringEnumConverter） | L5 維持 |
| AV-C5 (Required/Optional 明示) | L5 型システム（required + NRT） | L5 維持 |
