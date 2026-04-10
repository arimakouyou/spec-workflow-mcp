---
name: generate-api-docs
description: >
  ソースコードからOpenAPI 3.1ドキュメントを自動生成する。APIルート定義の解析、
  ハンドラシグネチャ・型定義・doc comment収集、OpenAPI YAML生成、doc comment改善提案を行う。
  Triggers: 'generate API docs', 'OpenAPI生成', 'APIドキュメント生成', '/generate-api-docs'.
argument-hint: "[--output <path>] [--framework <axum|actix-web|express|fastify|auto>]"
user-invokable: true
---

# OpenAPI ドキュメント自動生成

ソースコードの API ルート定義・ハンドラ・型定義を解析し、OpenAPI 3.1 YAML を生成する。

## 引数パース

| 引数 | デフォルト | 説明 |
|------|-----------|------|
| `--output <path>` | `docs/openapi.yaml` | 出力先パス |
| `--framework <name>` | `auto` | フレームワーク指定（`axum` / `actix-web` / `express` / `fastify` / `auto`） |

## Step 1: フレームワーク検出

`--framework auto`（デフォルト）の場合、以下の優先順で検出する:

| 優先度 | 検出条件 | フレームワーク |
|--------|---------|---------------|
| 1 | `Cargo.toml` に `axum` 依存 | Axum |
| 2 | `Cargo.toml` に `actix-web` 依存 | Actix-web |
| 3 | `package.json` に `express` 依存 | Express |
| 4 | `package.json` に `fastify` 依存 | Fastify |

いずれにも該当しない場合はエラーを報告し終了する。`--framework` で明示指定されている場合はこのステップをスキップする。

## Step 2: API ルート解析

フレームワーク別のパターンでソースコードを検索し、ルート定義を収集する。

### Axum

```bash
# Router 定義の検索
grep -rn 'Router::new\(\)\|\.route(\|\.nest(' --include='*.rs' src/
```

抽出対象:
- `.route("/path", get(handler))` → メソッド: GET、パス: `/path`、ハンドラ: `handler`
- `.nest("/prefix", router)` → ネストされたルーターのプレフィックス
- `.with_state(...)` → 共有状態の型

### Actix-web

```bash
grep -rn '\.route(\|\.resource(\|web::\(get\|post\|put\|delete\|patch\)' --include='*.rs' src/
```

### Express / Fastify

```bash
grep -rn 'app\.\(get\|post\|put\|delete\|patch\)\|router\.\(get\|post\|put\|delete\|patch\)' --include='*.ts' --include='*.js' src/
```

各ルートについて以下を記録する:
- HTTP メソッド
- パス
- ハンドラ関数名
- ハンドラ定義のファイルパスと行番号

## Step 3: ハンドラ分析

各ハンドラ関数について以下を収集する:

### 3.1 関数シグネチャ

ハンドラ関数の引数型（リクエストボディ）と戻り値型（レスポンス）を抽出する。

**Rust (Axum) の例:**
```rust
async fn create_user(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateUserRequest>,  // → リクエスト型
) -> Result<Json<UserResponse>, AppError>    // → レスポンス型
```

**TypeScript (Express) の例:**
```typescript
async function createUser(
  req: Request<{}, {}, CreateUserBody>,  // → リクエスト型
  res: Response<UserResponse>            // → レスポンス型
): Promise<void>
```

### 3.2 Doc Comment 収集

ハンドラ関数の直上にある Rustdoc (`///`) または JSDoc (`/** */`) コメントを収集する。これが OpenAPI の operation `description` になる。

### 3.3 型定義の解析

リクエスト/レスポンス型の定義を辿り、各フィールドの情報を収集する:

- フィールド名
- 型（OpenAPI の type/format にマッピング）
- Doc comment（OpenAPI の field `description` にマッピング）
- `Option<T>` / `?` → `required: false`
- バリデーション属性（`#[validate]`, `@IsEmail()` 等）→ OpenAPI の format/pattern

**Rust 型マッピング:**

| Rust 型 | OpenAPI type | OpenAPI format |
|---------|-------------|----------------|
| `String` | string | — |
| `i32` / `i64` | integer | int32 / int64 |
| `f32` / `f64` | number | float / double |
| `bool` | boolean | — |
| `Uuid` | string | uuid |
| `DateTime<Utc>` / `NaiveDateTime` | string | date-time |
| `Vec<T>` | array (items: T) | — |
| `Option<T>` | T (required: false) | — |

## Step 4: OpenAPI 3.1 YAML 生成

収集した情報から OpenAPI 3.1 準拠の YAML を構成する:

```yaml
openapi: "3.1.0"
info:
  title: "{プロジェクト名（Cargo.toml の package.name または package.json の name）}"
  version: "{バージョン}"
  description: "{Cargo.toml の description または package.json の description}"
paths:
  /path:
    get:
      summary: "{ハンドラの doc comment 1行目}"
      description: "{ハンドラの doc comment 全文}"
      parameters: [...]
      responses:
        "200":
          description: "成功"
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ResponseType"
        "400": ...
        "404": ...
components:
  schemas:
    RequestType:
      type: object
      required: [field1, field2]
      properties:
        field1:
          type: string
          description: "{フィールドの doc comment}"
```

### エラーレスポンスのマッピング

design.md の Error Handling セクションが存在する場合、そのテーブルからエラーコードとHTTPステータスを取得し、各エンドポイントの responses に反映する。存在しない場合は一般的なエラーレスポンス（400, 404, 500）を生成する。

### 出力

生成した YAML を `--output` パス（デフォルト: `docs/openapi.yaml`）に書き出す。`docs/` ディレクトリが存在しない場合は作成する。

既存ファイルがある場合は差分を表示し、上書き前にユーザーに確認する。

## Step 5: Doc Comment ギャップ分析

型定義の各フィールドを走査し、doc comment が不足しているフィールドを一覧で報告する:

```
## Doc Comment 改善提案

| ファイル | 行 | 型 | フィールド | 提案 |
|---------|-----|-----|-----------|------|
| src/models/user.rs | 15 | UserResponse | display_name | /// 表示用ユーザー名 |
| src/models/user.rs | 16 | UserResponse | created_at | /// アカウント作成日時（UTC） |
```

不足がない場合は「全フィールドに doc comment が記述されています」と報告する。

## Step 6: Design.md クロスリファレンス（オプション）

`.spec-workflow/specs/*/design.md` が存在する場合、設計書の API Design セクションと生成した OpenAPI を比較する:

### 差分検出

| 差分タイプ | 説明 | アクション |
|-----------|------|----------|
| 設計にあるがコードにない | design.md に定義されたエンドポイントが未実装 | 警告として報告 |
| コードにあるが設計にない | 実装済みだが design.md に未定義 | 警告として報告（設計逸脱の可能性） |
| 型の不一致 | リクエスト/レスポンスのフィールドが異なる | 差分を詳細に報告 |

design.md が存在しない場合はこのステップをスキップする。

## 完了レポート

```
## /generate-api-docs 完了レポート

- フレームワーク: {検出されたフレームワーク}
- 出力先: {出力パス}
- エンドポイント数: {N}
- スキーマ数: {M}
- Doc comment カバレッジ: {X}/{Y} フィールド ({Z}%)
- 改善提案: {K} 件
- Design.md 差分: {あり/なし/スキップ}
```
