---
spec: [spec-name]
doc: test-design
---

# Test Design: [タイトル]

型・関数・値の構造に触れるときは必ず限定参照(`` `MOD-N:Type` ``、`` `DES-N:fn` ``)で書く。design にない関数・型・テストダブルは使えない(必要なら先に design を直す)。

## Unit Tests

### DES-1

#### UT-1.1: [テストの名前]
- Target: [`DES-1:fn`]
- Verifies: [REQ-N.M]
- Category: [Happy | Boundary | Error | Edge | Negative]
- Given:
  - [引数名] = [値]
- Then:
  - [観測できる結果を 1 つ。「A または B」は書かない]

## Component Tests

### DES-2

#### CT-2.1: [テストの名前]
- Target: [DES-2]
- Verifies: [REQ-N.M]
- Mount: [マウント条件]
- Action: [操作]
- Then:
  - [DOM / signal の状態]

## Integration Tests

### IT-1: [テストの名前]
- Target: [API-N]
- Verifies: [REQ-N.M]
- File: [テストファイルのパス]
- Uses: [TST-N]
- Setup:
  - [`TST-N:fn`] [引数名] = [値]
- Request: [METHOD] [/path] [本文(JSON)]
- Then:
  - status [N]
  - [本文 / 永続化された状態]

## System Tests

### ST-1: [テストの名前]
- Target: [REQ-N]
- Verifies: [REQ-N.M, …]
- File: [テストファイルのパス]
- Uses: [TST-N]
- Setup:
  - [`TST-N:fn`] [引数名] = [値]
- Steps:
  - [UI 操作]
- Then:
  - [画面に表示される結果]

## E2E Tests

### E2E-1: [テストの名前]
- Target: [JRN-N]
- File: [テストファイルのパス]
- Uses: [TST-N]
- Steps:
  - [利用者の操作]
- Then:
  - [ジャーニー完了時の状態]
