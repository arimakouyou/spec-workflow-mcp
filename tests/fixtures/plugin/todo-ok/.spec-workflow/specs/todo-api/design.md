---
spec: todo-api
doc: design
---

# Design: Todo API

## Overview

タイトルの検証はタイトル型の構築時に一度だけ行い、ドメインの他の部分は検証済みの値だけを扱う。保存はプロセス内のストアで行い、ストアはトレイト越しにサービスへ注入する。HTTP 層は要求本文を検証済みの値に変換してサービスを呼び、ドメインのエラーを HTTP の応答に写像する。

## Phases

- P0: ツールチェーンと CI を用意する
- P1: ドメイン型・ストア・サービス
- P2: HTTP API と起動

## Layers

| Layer | Paths | Depends on |
|---|---|---|
| domain | src/domain/** | - |
| http | src/http/** | domain |
| bootstrap | src/app.rs, src/main.rs | domain, http |

## Components

### DES-1: ワークスペース
- Kind: config
- Layer: -
- Phase: 0
- Files: Cargo.toml, rust-toolchain.toml, .github/workflows/ci.yml
- Depends: -
- Satisfies: -
- Purpose: ツールチェーンの版を固定し、CI でテストとフォーマット検査を実行できるようにする

### DES-2: Todo のドメイン型
- Kind: types
- Layer: domain
- Phase: 1
- Files: src/domain/todo.rs
- Depends: -
- Satisfies: REQ-1.1, REQ-1.2, REQ-1.3
- Purpose: 検証済みのタイトルと Todo を表す
- Interfaces:
  ```rust
  impl Title {
      pub fn parse(raw: &str) -> Result<Title, TodoError>;
      pub fn as_str(&self) -> &str;
  }
  ```

### DES-3: Todo ストア
- Kind: logic
- Layer: domain
- Phase: 1
- Files: src/domain/store.rs
- Depends: DES-2
- Satisfies: REQ-2.1
- Held-as: `std::sync::Arc<dyn TodoStore>`
- Purpose: Todo を登録順に保持し、登録時に採番する
- Interfaces:
  ```rust
  pub trait TodoStore: Send + Sync {
      fn insert(&self, title: Title) -> Todo;
      fn list(&self) -> Vec<Todo>;
  }

  impl MemoryTodoStore {
      pub fn new() -> Self;
  }

  impl TodoStore for MemoryTodoStore {
      fn insert(&self, title: Title) -> Todo;
      fn list(&self) -> Vec<Todo>;
  }
  ```

### DES-4: Todo サービス
- Kind: logic
- Layer: domain
- Phase: 1
- Files: src/domain/service.rs
- Depends: DES-2, DES-3
- Satisfies: REQ-1.1, REQ-1.2, REQ-1.3, REQ-2.1
- Held-as: `std::sync::Arc<TodoService>`
- Purpose: タイトルを検証して Todo を登録し、一覧を返す
- Interfaces:
  ```rust
  use std::sync::Arc;

  impl TodoService {
      pub fn new(store: Arc<dyn TodoStore>) -> Self;
      pub fn create(&self, raw_title: &str) -> Result<Todo, TodoError>;
      pub fn list(&self) -> Vec<Todo>;
  }
  ```

### DES-5: HTTP API
- Kind: adapter
- Layer: http
- Phase: 2
- Files: src/http/api.rs
- Depends: DES-4
- Satisfies: REQ-1.1, REQ-1.2, REQ-1.3, REQ-1.4, REQ-2.1, NFR-1
- Implements: `axum::response::IntoResponse`
- Purpose: 要求本文をサービス呼び出しに変換し、ドメインのエラーを HTTP の応答に写像する
- Interfaces:
  ```rust
  use std::sync::Arc;
  use axum::{extract::State, http::StatusCode, response::Response, Json, Router};

  pub fn router(service: Arc<TodoService>) -> Router;
  pub async fn create_todo(State(service): State<Arc<TodoService>>, Json(body): Json<CreateTodoRequest>) -> Result<(StatusCode, Json<TodoResponse>), ApiError>;
  pub async fn list_todos(State(service): State<Arc<TodoService>>) -> Json<Vec<TodoResponse>>;
  pub async fn health() -> StatusCode;

  impl axum::response::IntoResponse for ApiError {
      fn into_response(self) -> Response;
  }
  ```

### DES-6: 起動
- Kind: wiring
- Layer: bootstrap
- Phase: 2
- Files: src/app.rs, src/main.rs
- Depends: DES-3, DES-4, DES-5
- Satisfies: -
- Purpose: ストア・サービス・ルーターを組み立てて待ち受ける
- Interfaces:
  ```rust
  pub fn app() -> axum::Router;
  pub async fn serve(listener: tokio::net::TcpListener) -> std::io::Result<()>;
  ```

## Types

### MOD-1: Title
- Owner: DES-2
- Definition:
  ```rust
  #[derive(Debug, Clone, PartialEq, Eq)]
  pub struct Title(String);
  ```

### MOD-2: Todo
- Owner: DES-2
- Definition:
  ```rust
  #[derive(Debug, Clone, PartialEq, Eq)]
  pub struct Todo {
      pub id: u64,
      pub title: Title,
      pub done: bool,
  }
  ```

### MOD-3: TodoError
- Owner: DES-2
- Definition:
  ```rust
  #[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
  pub enum TodoError {
      #[error("title is empty")]
      EmptyTitle,
      #[error("title exceeds {max} characters")]
      TitleTooLong { max: usize },
  }
  ```
- Raises:
  - EmptyTitle: `DES-2:Title::parse`, `DES-4:TodoService::create` — 前後の空白を除いたタイトルが空
  - TitleTooLong: `DES-2:Title::parse`, `DES-4:TodoService::create` — 前後の空白を除いたタイトルが 100 文字を超える

### MOD-4: MemoryTodoStore
- Owner: DES-3
- Definition:
  ```rust
  pub struct MemoryTodoStore {
      items: std::sync::Mutex<Vec<Todo>>,
  }
  ```

### MOD-5: TodoService
- Owner: DES-4
- Definition:
  ```rust
  pub struct TodoService {
      store: std::sync::Arc<dyn TodoStore>,
  }
  ```

### MOD-6: CreateTodoRequest
- Owner: DES-5
- Definition:
  ```rust
  #[derive(Debug, serde::Deserialize)]
  #[serde(deny_unknown_fields)]
  pub struct CreateTodoRequest {
      pub title: String,
  }
  ```

### MOD-7: TodoResponse
- Owner: DES-5
- Definition:
  ```rust
  #[derive(Debug, PartialEq, serde::Serialize, serde::Deserialize)]
  pub struct TodoResponse {
      pub id: u64,
      pub title: String,
      pub done: bool,
  }
  ```

### MOD-8: ApiError
- Owner: DES-5
- Definition:
  ```rust
  #[derive(Debug)]
  pub enum ApiError {
      Validation(TodoError),
  }
  ```
- Raises:
  - Validation: `DES-5:create_todo` — サービスが検証エラーを返した

## APIs

### API-1: POST /todos
- Handler: `DES-5:create_todo`
- Auth: none
- Request: MOD-6
- Response: 201 MOD-7
- Errors:
  - 400: `MOD-8:ApiError::Validation`
  - 422: DEP-1

### API-2: GET /todos
- Handler: `DES-5:list_todos`
- Auth: none
- Request: -
- Response: 200 MOD-7 (array)

### API-3: GET /health
- Handler: `DES-5:health`
- Auth: none
- Request: -
- Response: 200 -

## Test Support

### TST-1: テストサーバー
- Kind: harness
- Phase: 2
- Files: tests/support/mod.rs
- Depends: DES-6
- Interfaces:
  ```rust
  pub struct TestServer {
      pub base_url: String,
  }

  pub async fn spawn() -> TestServer;
  ```

### TST-2: 記録するストア
- Kind: double
- Phase: 1
- Files: src/domain/store_double.rs
- Depends: DES-3
- Implements: `DES-3:TodoStore`
- Interfaces:
  ```rust
  pub struct RecordingStore {
      pub inserted: std::sync::Mutex<Vec<Title>>,
  }

  impl RecordingStore {
      pub fn new() -> Self;
  }

  impl TodoStore for RecordingStore {
      fn insert(&self, title: Title) -> Todo;
      fn list(&self) -> Vec<Todo>;
  }
  ```

## Dependencies

### DEP-1: axum
- Version: 0.8
- Scope: prod
- Purpose: HTTP のルーティングと要求の抽出
- Contract:
  - 要求本文の JSON が要求型に合わない(未知の項目を含む場合を含む)とき、ハンドラに到達する前に 422 で拒否する (EV-lib-001)

### DEP-2: tokio
- Version: 1
- Features: macros, rt-multi-thread, net
- Scope: prod
- Purpose: 非同期ランタイムと待ち受け

### DEP-3: serde
- Version: 1
- Features: derive
- Scope: prod
- Purpose: 要求と応答の直列化

### DEP-4: thiserror
- Version: 2
- Scope: prod
- Purpose: ドメインのエラー型の定義

### DEP-5: reqwest
- Version: 0.12
- Features: json
- Scope: dev
- Purpose: IT と E2E の HTTP クライアント

## Tools

### TOOL-1: cargo
- Min: 1.93
- Check: cargo --version
- Install: rustup update
- Required: yes

### TOOL-2: cargo-mutants
- Min: 25.0
- Check: cargo mutants --version
- Install: cargo install cargo-mutants
- Required: recommended

## Decisions

### KD-1: タイトルを検証済みの型にする
- Decision: タイトルの検証はタイトル型の構築時だけで行い、検証済みでない文字列はドメインに渡さない
- Rationale: 検証漏れを型で防ぎ、検証の重複をなくすため
- ADR: no
