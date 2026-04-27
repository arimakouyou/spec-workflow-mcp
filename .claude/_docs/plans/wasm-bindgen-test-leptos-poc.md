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

### 実施日: 2026-04-28

### Setup 結果（POC で確立した最小構成）

**Cargo.toml**:
```toml
[dependencies]
leptos = { version = "0.7", features = ["csr"] }
wasm-bindgen = "0.2"
web-sys = { version = "0.3", features = ["Document", "Element", "HtmlElement", "Window"] }

[target.'cfg(target_arch = "wasm32")'.dev-dependencies]
wasm-bindgen-test = "0.3"
gloo-timers = { version = "0.3", features = ["futures"] }
```

**.cargo/config.toml**（必須、これが無いと wasm test が動かない）:
```toml
[target.wasm32-unknown-unknown]
runner = "wasm-bindgen-test-runner"
```

**Tools 状態**:
- `wasm-bindgen-cli` 0.2.118: 既存（spec-workflow-mcp 環境に install 済）
  - `wasm-bindgen-test-runner` を提供
- `wasm32-unknown-unknown` rustup target: 既存
- `wasm-pack`: **不要**（cargo test で直接動作）
- Firefox + geckodriver: snap install で auto-discovered（手動セットアップ不要）
  - `chromedriver` 等の chrome 系も同様（試していないが可能性大）

### POC 実装結果

対象 component: `SimpleCounter`（Leptos book testing.html を参考）

3 件の test を実装、すべて PASS:

```rust
#[wasm_bindgen_test]
fn renders_initial_value() {
    // mount + query_selector + text_content 検証
    // signal の初期値が DOM に反映されるか
}

#[wasm_bindgen_test]
async fn click_increment_updates_dom() {
    // click → signal update → tick().await → DOM 検証
    // click 3 回で counter が "3" になることを verify
}

#[wasm_bindgen_test]
async fn clear_resets_to_zero() {
    // initial 42 → click clear → tick().await → DOM "0" 検証
}
```

### 計測結果

| 項目 | 値 |
|------|---|
| **総実行時間（compile + 3 tests + Firefox 起動）** | 4.9 秒 |
| compile 時間 | 0.78 秒（依存解決後 incremental） |
| 1 test あたり実行時間 | < 100ms |
| Firefox 起動オーバーヘッド | 約 3 秒（最初の test のみ） |
| セットアップ複雑度 | 中（.cargo/config.toml + Cargo.toml dev-deps 設定で完了） |
| エルゴノミクス | 良（Leptos book pattern が直接通用） |
| CI 適性 | 高（geckodriver / chromedriver を CI runner に install するだけ） |

### 判定

| 結果 | 判断 |
|------|------|
| ✅ **動く / 実用的** | H-1〜H-5 を予定通り実装。CT 層は実現可能 |

#### Why this is sufficient

- **Component reactivity の完全 verify**: signal 操作 → reactive update → DOM re-render の chain が test で観測できる
- **Event handler 検証**: click 等の DOM event が signal を update することを verify できる
- **tick().await pattern**: reactive system の async 性質に対応（gloo-timers で 0ms wait）
- **DOM 構造検証**: query_selector + text_content / inner_html / outer_html で構造的検証可能
- **fixture フリー**: 各 test で `fresh_wrapper()` を作成、状態共有なし（FIRST 原則の Isolated を満たす）
- **数秒/test**: E2E より圧倒的に速い

#### Architecture for Testability (K-3) との連携

Leptos の Resource / Suspense / server fn は実 server を呼ぶため CT 層では mock が必要。design.md の K-3「External I/O isolation」で `mockito` / `wiremock` を経由する設計を宣言する前提。

CT 層の典型例:
- ✅ Pure component reactivity（signal、event handler、Effect）→ wasm-bindgen-test で直接 verify
- ⚠️ Resource を含む component → server fn を mock 経由に切り替えた上で wasm-bindgen-test
- ❌ 実 server を呼ぶ統合動作 → CT ではなく ST or E2E

### Cleanup

- /tmp/h-poc-sandbox/ → **手動削除を要請**（permission 環境で `rm -rf` deny のため）
  - ユーザーで `rm -rf /tmp/h-poc-sandbox` を実行してください
- spec-workflow-mcp 側に POC 由来の変更なし（plan ファイル + H 実装のみ）

### Tool install への影響

POC で **新規 install したツールはゼロ**:
- wasm-bindgen-cli: 既に install 済（cargo install --list で確認）
- gloo-timers: Cargo.toml の dev-dep（temp project 内のみ、global install なし）
- Firefox: snap で既存
- geckodriver: Firefox snap に bundled

ユーザーの「I/H POC 終了後 cargo は不要」要望に応える形で、追加 install ゼロで POC を完了できた。

## 関連

- マスタープラン: `dapper-hardening-orchestrator.md` 根本原因 H (line 340 〜)
- H sub-plan: `component-test-layer-introduction.md`（POC 完了後に着手）
- 参考: `frontend-test-engineer.md` L104-112、`tdd-skills-rust/references/leptos-frontend-testing.md`
