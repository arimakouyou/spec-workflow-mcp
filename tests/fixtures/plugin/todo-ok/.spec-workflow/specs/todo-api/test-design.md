---
spec: todo-api
doc: test-design
---

# Test Design: Todo API

## Unit Tests

### DES-2

#### UT-2.1: 前後の空白を除いたタイトルを受け入れる
- Target: `DES-2:Title::parse`
- Verifies: REQ-1.1
- Category: Happy
- Given:
  - raw = "  buy milk  "
- Then:
  - `Ok` の値が `MOD-1:Title` で、文字列が "buy milk" である

#### UT-2.2: 100 文字ちょうどを受け入れる
- Target: `DES-2:Title::parse`
- Verifies: REQ-1.1
- Category: Boundary
- Given:
  - raw = "a" を 100 個並べた文字列
- Then:
  - `Ok` の値が `MOD-1:Title` で、文字数が 100 である

#### UT-2.3: 101 文字を拒否する
- Target: `DES-2:Title::parse`
- Verifies: REQ-1.3
- Category: Boundary
- Given:
  - raw = "a" を 101 個並べた文字列
- Then:
  - `Err` の値が `MOD-3:TodoError::TitleTooLong` で、max が 100 である

#### UT-2.4: 空白だけのタイトルを拒否する
- Target: `DES-2:Title::parse`
- Verifies: REQ-1.2
- Category: Error
- Given:
  - raw = "   "
- Then:
  - `Err` の値が `MOD-3:TodoError::EmptyTitle` である

#### UT-2.5: 文字数はバイト数ではなく文字で数える
- Target: `DES-2:Title::parse`
- Verifies: REQ-1.1
- Category: Edge
- Given:
  - raw = "あ" を 100 個並べた文字列(300 バイト)
- Then:
  - `Ok` の値が `MOD-1:Title` で、文字数が 100 である

### DES-3

#### UT-3.1: 登録時に 1 から採番する
- Target: `DES-3:MemoryTodoStore::insert`
- Verifies: REQ-2.1
- Category: Happy
- State: 空のストア
- Given:
  - title = "a" から作った `MOD-1:Title`
- Then:
  - 戻り値の `MOD-2:Todo` の id が 1、done が false である

#### UT-3.2: 一覧は登録順に並ぶ
- Target: `DES-3:MemoryTodoStore::list`
- Verifies: REQ-2.1
- Category: Happy
- State: "a"、"b" の順に登録済みのストア
- Then:
  - 戻り値の `MOD-2:Todo` の列のタイトルが "a"、"b" の順である

### DES-4

#### UT-4.1: 検証したタイトルで登録する
- Target: `DES-4:TodoService::create`
- Verifies: REQ-1.1
- Category: Happy
- State: `TST-2:RecordingStore` を注入したサービス
- Given:
  - raw_title = " buy milk "
- Then:
  - `Ok` の値が `MOD-2:Todo` で、タイトルが "buy milk"、done が false である

#### UT-4.2: 空のタイトルは検証エラーを返す
- Target: `DES-4:TodoService::create`
- Verifies: REQ-1.2
- Category: Error
- State: `TST-2:RecordingStore` を注入したサービス
- Given:
  - raw_title = ""
- Then:
  - `Err` の値が `MOD-3:TodoError::EmptyTitle` である

#### UT-4.3: 長すぎるタイトルは検証エラーを返す
- Target: `DES-4:TodoService::create`
- Verifies: REQ-1.3
- Category: Error
- State: `TST-2:RecordingStore` を注入したサービス
- Given:
  - raw_title = "a" を 101 個並べた文字列
- Then:
  - `Err` の値が `MOD-3:TodoError::TitleTooLong` である

#### UT-4.4: 拒否したタイトルはストアに渡さない
- Target: `DES-4:TodoService::create`
- Verifies: REQ-1.2
- Category: Negative
- State: `TST-2:RecordingStore` を注入したサービス
- Given:
  - raw_title = ""
- Then:
  - `TST-2:RecordingStore` の inserted が空のままである

#### UT-4.5: 一覧はストアの順序を保つ
- Target: `DES-4:TodoService::list`
- Verifies: REQ-2.1
- Category: Happy
- State: "a"、"b" の順に登録したサービス
- Then:
  - 戻り値の `MOD-2:Todo` の列のタイトルが "a"、"b" の順である

## Integration Tests

### IT-1: 有効なタイトルで登録すると 201 を返す
- Target: API-1
- Verifies: REQ-1.1
- File: tests/it_todos.rs
- Uses: TST-1
- Setup:
  - `TST-1:spawn`
- Request: POST /todos {"title": "  buy milk  "}
- Then:
  - status 201
  - 本文が `MOD-7:TodoResponse` で、title が "buy milk"、done が false である

### IT-2: 空のタイトルは 400 を返す
- Target: API-1
- Verifies: REQ-1.2
- File: tests/it_todos.rs
- Uses: TST-1
- Setup:
  - `TST-1:spawn`
- Request: POST /todos {"title": "   "}
- Then:
  - status 400
  - 本文が `MOD-8:ApiError::Validation` の表現で、"title is empty" を含む

### IT-3: 101 文字のタイトルは上限を示して 400 を返す
- Target: API-1
- Verifies: REQ-1.3
- File: tests/it_todos.rs
- Uses: TST-1
- Setup:
  - `TST-1:spawn`
- Request: POST /todos {"title": "a を 101 個並べた文字列"}
- Then:
  - status 400
  - 本文が "100" を含む

### IT-4: title 以外の項目を含む本文は 422 を返す
- Target: API-1
- Verifies: REQ-1.4
- File: tests/it_todos.rs
- Uses: TST-1
- Setup:
  - `TST-1:spawn`
- Request: POST /todos {"title": "a", "done": true}
- Then:
  - status 422

### IT-5: 一覧は登録順の配列を返す
- Target: API-2
- Verifies: REQ-2.1
- File: tests/it_todos.rs
- Uses: TST-1
- Setup:
  - `TST-1:spawn`
- Request: GET /todos(事前に "a"、"b" の順で POST /todos を送る)
- Then:
  - status 200
  - 本文が `MOD-7:TodoResponse` の配列で、title が "a"、"b" の順である

### IT-6: 稼働確認は 200 を返す
- Target: API-3
- Verifies: NFR-1
- File: tests/it_health.rs
- Uses: TST-1
- Setup:
  - `TST-1:spawn`
- Request: GET /health
- Then:
  - status 200

## E2E Tests

### E2E-1: 登録して一覧で確かめる
- Target: JRN-1
- File: tests/e2e_journey.rs
- Uses: TST-1
- Steps:
  - POST /todos で "a" を登録する
  - POST /todos で "b" を登録する
  - GET /todos で一覧を取得する
- Then:
  - 一覧の title が "a"、"b" の順である
