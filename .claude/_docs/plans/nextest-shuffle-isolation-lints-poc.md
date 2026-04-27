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

（POC 実施後に追記）

### 実施日: -

### nextest --shuffle 結果

- baseline 実行時間: -
- shuffle 実行時間: -
- 順序依存 test の検出: -
- CI 統合の例: -

### cargo-deny [bans] 結果

- crate 単位 ban: -
- function 単位 ban: -
- 結論: -

### clippy disallowed-methods 結果

- 動作確認: -
- `#[cfg(test)]` 限定の可否: -
- workspace lints 整合性: -
- 結論: -

### .NET / Node.js 系

- .NET: -
- Node.js: -

### 判定

- nextest --shuffle: -
- 禁止 call lint: -
- I-2 への影響: -

## 関連

- マスタープラン: `dapper-hardening-orchestrator.md` 根本原因 I (line 493 〜)
- I sub-plan: `ut-quality-properties-enforce.md`（POC 完了後に着手）
- 関連 plan: `wasm-bindgen-test-leptos-poc.md`（H 前提 POC、独立並行可能）
