# wasm-bindgen-test for Leptos 0.7 POC (H 前提)

> マスター: `dapper-hardening-orchestrator.md` の根本原因 H
> Branch: `refactor/plugin-redesign-phase-a`
> Status: PENDING（POC 未実施）
> 起票日: 2026-04-28
> 推定所要: 数時間〜半日

## 目的

`wasm-bindgen-test` で Leptos 0.7 component を mount → signal 操作 → DOM 観測する CT (Component Test) 層が実用的に成立するかを **実証**する。動かない / 重すぎる場合は H 全体を別技術に pivot する判断材料にする。

## 背景

- `frontend-test-engineer.md` L104-112 が **明示的に** 「`view!` / DOM 配線 / Suspense / Resource / hydration は **すべて E2E の責務**」と排除している
- `tdd-skills-rust/references/leptos-frontend-testing.md` も「ロジック抽出 + standard #[test]」のみ言及、wasm-bindgen-test 言及なし
- dojin-viewer に wasm-bindgen-test 不在
- → 過去に「できない / 採用しない」と判断された可能性が高く、未検証仮説のまま H を進めるとリスク大

advisor 指摘 (2026-04-27):
> H 全体は「Leptos component を `wasm-bindgen-test` で mount → signal 操作 → DOM 観測する CT 層が実現可能」を前提にしている。「数秒/test」「実 browser 起動不要」は推測。この仮定が崩れると H 全体が崩れる。

## POC スコープ（最小実証）

dojin-viewer の `crates/app/src/components/toolbar.rs` 相当の **最も単純な component** を対象に、以下を実装して動作確認:

### Setup タスク

- [ ] dojin-viewer の `Cargo.toml` に追加（または別の Leptos 0.7 プロジェクトを用意）:
  ```toml
  [target.'cfg(target_arch = "wasm32")'.dev-dependencies]
  wasm-bindgen-test = "0.3"
  leptos = { version = "0.7", features = ["csr"] }
  ```
- [ ] `wasm-pack` がインストール済か確認、未導入なら `cargo install wasm-pack`
- [ ] Chromium または `chromedriver` がインストール済か確認

### POC 実装タスク

- [ ] 対象 component を 1 つ選定（`toolbar.rs` 相当の simple component）
- [ ] 以下 3 種の test を作成:
  1. **Mount test**: component を mount し、初期 DOM が期待通りか確認
  2. **Signal test**: signal を変化させ、view! 内の derive memo が再計算されるか確認
  3. **Event test**: button などの click handler が signal を更新するか確認（DOM event dispatch 経由）
- [ ] `wasm-pack test --headless --chrome` で実行
- [ ] 各 test の動作を確認

### 計測タスク

- [ ] **実行時間**: 1 test あたりの所要を計測（target: 数秒以内）
- [ ] **セットアップ複雑度**: Cargo.toml / 各種依存追加の作業量を記録
- [ ] **エルゴノミクス**: `mount_to`, `Suspense`, `Resource` のモック方法、テストランナーとの統合の操作感
- [ ] **CI 適性**: GitHub Actions などで `wasm-pack test --headless --chrome` を回した際の所要時間と安定性

## 判定基準

| 結果 | 判断 | H への影響 |
|------|------|----------|
| **動く / 実用的**（1 test 数秒、setup 30 分以内） | H-1〜H-5 を予定通り実装 | H sub-plan の実装フェーズに進む |
| **動くが重い**（1 test 30 秒 +、setup 数時間） | H-1 の手段を「wasm-bindgen-test + 軽量化工夫」に修正、または部分採用 | H sub-plan を再設計 |
| **動かない**（mount できない / signal 反映されない / 不安定） | H 全体を別技術に pivot:<br>・Playwright Component Testing (Rust/WASM 対応版があれば)<br>・E2E を Phase 内で部分実行する軽量 gate (E に統合)<br>・Trunk + WebDriverIO + page object pattern | H sub-plan を全面書換 |

## 結果記録

（POC 実施後に追記）

### 実施日: -

### Setup 結果

- Cargo.toml 追加内容: -
- wasm-pack バージョン: -
- chromedriver バージョン: -

### POC 実装結果

- 対象 component: -
- 実装した test: -

### 計測結果

- 1 test あたり実行時間: -
- セットアップ所要時間: -
- エルゴノミクス所感: -
- CI 適性: -

### 判定

- 結果: -
- H への影響: -

## 関連

- マスタープラン: `dapper-hardening-orchestrator.md` 根本原因 H (line 340 〜)
- H sub-plan: `component-test-layer-introduction.md`（POC 完了後に着手）
- 参考: `frontend-test-engineer.md` L104-112、`tdd-skills-rust/references/leptos-frontend-testing.md`
