---
spec: [spec-name]
doc: design
---

# Design: [タイトル]

## Overview

[設計の全体像を 3〜5 文で。コード片・型名・関数名は書かない(DES / MOD の中だけに書く)]

## Phases

- P0: [ブートストラップ / ツール準備。greenfield では必須]
- P1: [目的 1 行]

## Layers

| Layer | Paths | Depends on |
|---|---|---|
| [domain] | [crates/app/src/domain/**] | - |
| [http] | [crates/app/src/http/**] | [domain] |
| [bootstrap] | [crates/app/src/main.rs] | [domain, http] |

## Components

### DES-1: [コンポーネント名]
- Kind: [logic | types | adapter | ui | wiring | config]
- Layer: [Layers 表の Layer(config は -)]
- Phase: [N]
- Files: [このコンポーネントだけが所有する本番ファイル]
- Depends: [DES-N, … または -]
- Satisfies: [REQ-N.M, … または -(wiring / config のみ)]
- Evidence: [EV-{category}-{NNN}(任意)]
- Held-as: [`Arc<dyn Trait>` など、他のコンポーネントが保持する形(任意)]
- Implements: [`crate::Trait` など、実装する外部 trait(任意)]
- Purpose: [1 文。コード片は書かない]
- Interfaces:
  ```rust
  [pub fn new(...) -> Self;  // 他から構築される場合は必須]
  [pub fn operation(&self, arg: Type) -> Result<Output, Error>;]
  ```

## Types

### MOD-1: [型名]
- Owner: [DES-N]
- Definition:
  ```rust
  [pub struct / pub enum の完全な定義。derive や serde 属性も含める]
  ```
- Raises:
  - [Variant]: [DES-N:fn] — [この variant を返す条件]

## APIs

### API-1: [METHOD] [/path]
- Handler: [`DES-N:fn`]
- Auth: [none | required]
- Request: [MOD-N または -]
- Response: [status] [MOD-N]
- Errors:
  - [status]: [`MOD-N:ErrorType::Variant`]

## Test Support

### TST-1: [ハーネス / フィクスチャ / テストダブルの名前]
- Kind: [harness | fixture | double]
- Phase: [N]
- Files: [テスト支援コードのファイル]
- Depends: [DES-N, … または -]
- Implements: [`DES-N:Trait`(double のみ)]
- Interfaces:
  ```rust
  [pub async fn spawn(port: u16) -> TestServer;]
  ```

## Dependencies

### DEP-1: [crate / package 名]
- Version: [レジストリで確認した最新安定版]
- Scope: [prod | dev]
- Purpose: [用途]
- Contract:
  - [設計が前提にしている実行時の振る舞い] ([EV-lib-NNN])

## Tools

### TOOL-1: [ツール名]
- Min: [最小バージョン]
- Check: [バージョン確認コマンド]
- Install: [導入コマンド]
- Required: [yes | recommended]

## Decisions

### KD-1: [判断の名前]
- Decision: [何を決めたか]
- Rationale: [なぜそう決めたか]
- ADR: [yes | no]
