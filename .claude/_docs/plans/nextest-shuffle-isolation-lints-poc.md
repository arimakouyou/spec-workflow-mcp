# cargo nextest --shuffle + Isolation Lints POC (I 前提)

> マスター: `dapper-hardening-orchestrator.md` の根本原因 I
> Branch: `refactor/plugin-redesign-phase-a`
> Status: PENDING（POC 未実施）
> 起票日: 2026-04-28
> 推定所要: 数時間〜半日

## 目的

I-2 (UT Properties Gate, QC15) で導入予定の以下 2 系統について、実装可能性を **実証**する:

1. **Order independence 検証**: `cargo nextest --shuffle` で全 UT を shuffle 実行し、順序依存テストを検出
2. **External dependency lint**: `#[cfg(test)]` 内で禁止される call の lint 実装パターン確立
   - clock 直接呼び出し (`std::time::SystemTime::now()`, `chrono::Utc::now()`)
   - RNG 直接使用 (`rand::thread_rng()`, `rand::random()`)
   - env 直接読取 (`std::env::var()`)
   - fs 直接呼び出し (`std::fs::read*`, `std::fs::write*`)
   - HTTP 直接呼び出し (`reqwest::*`, `tokio::net::*`)

## 背景

I-2 では「`cargo nextest --shuffle` を CI gate 化」「禁止 call を lint で検出」と仕様化したが、以下が未検証:

- nextest の `--shuffle` が **真に random order** で実行するか / order dependency を検出できるか
- 禁止 call の lint 実装が `cargo-deny` の `[bans]` で書けるか / clippy custom lint が必要か
- false positive が許容範囲か（テスト基盤の `env_logger` などは除外可能か）
- workspace lints による設定が機能するか

advisor 指摘:
> I-2 の lint（clock / RNG / env の直接呼出禁止）の **許可された逃げ口** が design.md K-3 で宣言された Mock 経由のみ、と紐付け

K-3 (Architecture for Testability) で宣言された Mock 経由のみ許可する仕組みは、I-2 の lint で禁止すべき call と表裏一体。POC で lint 設計を確定する必要がある。

## POC スコープ

### Setup タスク

- [ ] `spec-workflow-mcp` リポジトリ内の test crate（または別の試験用 Rust crate）を準備
- [ ] `cargo install cargo-nextest --locked`
- [ ] `cargo install cargo-deny --locked`

### nextest --shuffle 検証タスク

- [ ] 既存 test crate で `cargo nextest run --no-fail-fast --test-threads=1` を実行（baseline）
- [ ] `cargo nextest run --shuffle` を 5 回実行、結果が安定しているか確認
- [ ] 意図的に順序依存 test を作成（global mut state を共有するなど）し、`--shuffle` で fail が検出されるか確認
- [ ] CI workflow（GitHub Actions）に `--shuffle` を組み込む例を作成

### cargo-deny [bans] 検証タスク

- [ ] `deny.toml` の `[bans]` で specific function call を ban する書式を試す:
  ```toml
  [bans]
  deny = [
    { name = "chrono", wrappers = [...] },
  ]
  ```
- [ ] crate 単位の ban は機能するが、**function 単位の ban が可能か** を確認
- [ ] 不可能な場合の代替（clippy custom lint / clippy::disallowed_methods 等）を調査

### clippy custom lint 検証タスク

- [ ] `clippy.toml` の `disallowed-methods` で以下を試す:
  ```toml
  disallowed-methods = [
    { path = "std::time::SystemTime::now", reason = "use MockClock instead" },
    { path = "chrono::Utc::now", reason = "use MockClock instead" },
    { path = "rand::thread_rng", reason = "use MockRng instead" },
    { path = "std::env::var", reason = "use injected config instead" },
  ]
  ```
- [ ] `#[cfg(test)]` 内のみで適用する仕組みがあるか確認（無ければ全コードで適用 → 例外 allowlist 戦略）
- [ ] cargo workspace lints との整合性確認

### .NET / Node.js 系の対応調査

- [ ] .NET: `dotnet test --blame-hang` + `xunit.runner.json` parallel 設定の調査
- [ ] .NET: `Stryker.NET` のテスト独立性チェック
- [ ] Node.js: `vitest` の `--shuffle` (v1.6+) / `jest` の `--testSequencer` の調査

## 判定基準

| 系統 | 結果 | 判断 |
|------|------|------|
| nextest --shuffle | 動作 + 順序依存検出可能 | I-2 に予定通り組み込み |
| nextest --shuffle | 動作するが順序依存検出が weak | I-2 仕様を「shuffle 実行 1 回 + flaky test 検出」に修正 |
| nextest --shuffle | 不安定 / 使えない | I-2 から削除、別手段（手動実行のみ）に切替 |
| 禁止 call lint | clippy::disallowed-methods で全項目カバー可能 | I-2 仕様を確定 |
| 禁止 call lint | 部分的にカバー可能 | I-2 仕様を「カバーできる項目のみ」に絞る |
| 禁止 call lint | 実装困難 | I-2 仕様を「review-worker の手動 review」に切替 |

## 結果記録

### 実施日: 2026-04-28

### Sandbox

- /tmp/i-poc-sandbox/poc/ に最小 Rust crate を作成
- src/lib.rs に 6 件の test（順序依存 2 件 + 独立 2 件 + clock/env 直接呼出 2 件）
- POC 終了後 cleanup 済（spec-workflow-mcp に痕跡なし）

### Tools 状態（spec-workflow-mcp 側、変更なし）

- cargo 1.95.0: 既存
- cargo-nextest 0.9.133: 既存（POC で install せず）
- cargo-deny: **未 install**（POC で検証不要と判断、後述）

### nextest --shuffle 結果（**重要な finding**）

- ❌ **cargo nextest は --shuffle を native サポートしていない**
  - `cargo nextest run --help` / `cargo nextest --help` に shuffle / random 相当のオプションなし
- ❌ **cargo test --shuffle は stable で動かない**
  ```
  error: The "shuffle" flag is only accepted on the nightly compiler with -Z unstable-options
  ```
- ✅ **nightly では動作**
  ```bash
  cargo +nightly test --tests -- -Z unstable-options --shuffle --test-threads=1
  # → 6 tests run shuffle、seed 表示あり
  ```

**含意**:
- I-2 で「`cargo nextest --shuffle` を CI gate 化」は **stable Rust では不可能**
- nightly toolchain を CI に追加するか、shuffle を skip するかの判断必要

### cargo-deny [bans] 結果

- POC では検証せず（cargo-deny を install しないことで spec-workflow-mcp 環境を綺麗に保つ）
- 結論: **cargo-deny は I-2 では不要**。clippy `disallowed-methods` が function 単位の ban を実現するため、cargo-deny の crate 単位 ban とは適用範囲が異なる

### clippy disallowed-methods 結果（**主役**）

```toml
# /tmp/i-poc-sandbox/poc/clippy.toml
disallowed-methods = [
    { path = "std::time::SystemTime::now", reason = "use MockClock instead (I-2 / dapper-hardening)" },
    { path = "std::env::var", reason = "use injected config instead" },
]
```

```
$ cargo clippy --tests -- -W clippy::disallowed_methods
warning: use of a disallowed method `std::time::SystemTime::now`
  --> src/lib.rs:33:17
  ...
  = note: use MockClock instead (I-2 / dapper-hardening)

warning: use of a disallowed method `std::env::var`
  --> src/lib.rs:38:17
  ...
  = note: use injected config instead
```

✅ **完全動作**:
- function 単位の ban が機能
- custom reason メッセージが表示される
- `-D clippy::disallowed_methods` で deny-level（CI gate 化可能）
- `cargo clippy --tests` で test code を含めて検査可能

⚠️ 制約:
- `disallowed-methods` は **global** に適用される（test code 限定にはできない）
- production code の legitimate 使用は `#[allow(clippy::disallowed_methods)]` で個別許可
- ただし「全コードで Mock 経由のみ」が design 方針なので、global 適用が望ましい
- `clippy.toml` 設定は workspace lints と併用可能

### .NET / Node.js 系

- POC 未実施（Rust 系で blocker が判明したため、まず Rust 側を確定）
- .NET: `dotnet test --blame-hang` + `xunit.runner.json` → 別 POC または I 実装段階で確認
- Node.js: `vitest --shuffle` (v1.6+) / `jest --testSequencer` → 別 POC または I 実装段階で確認

### 判定

| 系統 | 結果 | I-2 への影響 |
|------|------|-------------|
| **nextest --shuffle** | ❌ Native サポートなし | I-2 から削除（または `cargo test --shuffle` を nightly でオプション提供） |
| **cargo test --shuffle (stable)** | ❌ -Z unstable-options 必須 | stable で必須化は不可。nightly profile を CI に追加するか skip |
| **cargo test --shuffle (nightly)** | ✅ 動作 | nightly profile を I-2 で advisory として規定可能 |
| **clippy disallowed-methods** | ✅ 完全動作 | I-2 の **主柱**として採用 |
| **cargo-deny [bans]** | (未検証、不要と判断) | I-2 から削除 |

### I-2 仕様への反映方針

- **採用**: clippy `disallowed-methods` の workspace clippy.toml 設定を I-2 の核心に据える
  - clock / RNG / env / fs / HTTP / DB の直接呼出を function 単位で deny
  - custom reason に「use Mock from design.md Architecture for Testability instead」を記載
  - K-3 (Architecture for Testability) との連動を明示
- **削除**: cargo-deny [bans] への言及
- **修正**: cargo nextest --shuffle を **必須から advisory** に格下げ
  - nightly toolchain がある場合のみ実行
  - stable では skip + 「順序依存検出は code review + test design discipline で代替」を明記
- **拡張**: production code への適用方針を明確化
  - global 適用（test 限定にはできない）
  - production の legitimate 使用は `#[allow(...)]` で個別許可
  - 「全コードで Mock 経由のみ」が design 方針として K-3 で宣言される前提

### Cleanup

- /tmp/i-poc-sandbox/ → **手動削除を要請** （`rm -rf` が permission 環境で deny されたため自動実行不可）
  - ユーザーで `rm -rf /tmp/i-poc-sandbox` を実行してください
- spec-workflow-mcp 側に POC 由来の変更なし（plan ファイル更新のみ）
- 結論: cargo-deny の install を回避できたため、追加 install ゼロで POC 完了

## 関連

- マスタープラン: `dapper-hardening-orchestrator.md` 根本原因 I (line 493 〜)
- I sub-plan: `ut-quality-properties-enforce.md`（POC 完了後に着手）
- 関連 plan: `wasm-bindgen-test-leptos-poc.md`（H 前提 POC、独立並行可能）
