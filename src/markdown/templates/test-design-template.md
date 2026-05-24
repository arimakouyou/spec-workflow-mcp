---
spec_id: {spec-name}
phase: test-design
version: 1
depends_on:
  - file: requirements.md
    refs: [REQ-1, REQ-2]  # 検証対象の Requirement
  - file: design.md
    refs: [DES-1, DES-2]  # テスト対象のコンポーネント
---

# Test Design Document

> **ID 規則**（`.claude-plugin/rules/spec-dependency-graph.md` SD1）: UT-N.M / IT-N / E2E-N は従来通り `####` 見出しで明示。VRT-N / DOM-N も同形式。末尾の Requirements-Test Traceability Matrix で REQ → テスト ID の対応を記録する。

> **Evidence 引用**（`.claude-plugin/rules/evidence-coverage.md` EC2, 非 legacy 類型のみ）: 各テストケース（UT/IT/E2E）は、検証対象の挙動を現行コードで裏付ける EV を最低 1 件引用すること。`Evidence:` 欄もしくはインライン `(EV-{category}-{NNN})` を利用。典型的には `EV-contract-current-*` / `EV-branches-*` / `EV-regressions-*` / `EV-test-harness-*`。真に新規の挙動でアンカーが存在しない場合のみ per-artifact waiver `<!-- no-evidence: {reason} -->` を記載可（reason 必須、WARN のみ）。

## Test Strategy Overview

### Testing Philosophy
[このフィーチャーのテスト全体方針を記述する。TDD を前提とし、品質保証の考え方を明記]

### Test Pyramid
[UT / IT / E2E のバランスと優先順位を定義する]

| Level | 目的 | 実行タイミング | 想定件数 |
|-------|------|--------------|---------|
| Unit Test (UT) | コンポーネント単体の契約検証 | TDD RED フェーズ | [N] |
| Integration Test (IT) | コンポーネント間結合の検証 | Phase Review | [N] |
| E2E Test | ユーザージャーニーの検証 | Final E2E Gate | [N] |

### Test Environment Requirements

- **Container Runtime:** Docker / Podman (必須)
- **テストフレームワーク:** [例: cargo test + mockall, jest + testcontainers, pytest]
- **テスト用コンテナ:**

| Service | Image | Purpose |
|---------|-------|---------|
| DB | [例: postgres:16-alpine] | テスト用 DB (testcontainers) |
| [Other] | [image] | [purpose] |

#### Required Test Tools

| Tool | Min Version | Purpose | Check Command | Install Command | Required |
|------|-------------|---------|---------------|-----------------|----------|
| [例: cargo] | [(bundled)] | [例: Unit test runner (cargo test)] | [例: cargo --version] | [例: (bundled with rustup)] | Yes |
| [例: docker] | [例: >= 29.0] | [例: testcontainers 用コンテナランタイム] | [例: docker --version] | [例: apt install docker.io] | Yes |
| [例: playwright] | [例: >= 1.58.0] | [例: Browser E2E テストランナー] | [例: npx playwright --version] | [例: npx playwright install] | Yes |
| [例: chromium] | [例: (bundled with playwright)] | [例: E2E ブラウザエンジン（Playwright バージョンに対応するビルドを使用）] | [例: node -e "const { chromium } = require('playwright'); const fs = require('fs'); const p = chromium.executablePath(); if (!p || !fs.existsSync(p)) process.exit(1); console.log(p);"] | [例: npx playwright install chromium] | Yes |

Notes:
- **Yes**: テスト実行前に必須。未インストール = FAIL。実装を停止しユーザーに報告
- **Recommended**: 未インストールでも警告のみで続行可能（ビルドキャッシュ等の最適化ツール向け）
- Min Version は `any`（バージョン不問）/ `(bundled)`（同梱）/ `>= x.y.z`（最低バージョン指定）など、Step 0 でバージョン比較可能な形式で記載すること（`latest` など比較不能な値は使用しない）
- E2E テストに必要なツール（Playwright, Chrome等）は **必ず Required=Yes** とする。環境依存によるテストスキップは許可しない
- 実行不可能なテストがある場合は、design.md の「Excluded Test Environments」セクションで設計時に明示すること
- design.md の Required Build Tools と重複するツールは、テスト用に異なるバージョン要件がある場合のみ記載
- **Version Verification**: Min Version は AI の学習データのデフォルト値を使用しない。WebSearch またはレジストリ CLI で最新安定版を確認し反映すること
- **Browser Version**: Chromium/Chrome のバージョンは Playwright のバージョンと連動する。`npx playwright install chromium` で Playwright バージョンに対応する最新ブラウザを取得すること

---

## Unit Test Specifications

### Component: [ComponentName1]
- **Target:** [テスト対象のモジュール/ファイルパス]
- **Dependencies to Mock:** [モック対象の依存コンポーネント]

#### UT-1.1: [テストケース名]
- **Category:** Happy Path
- **Preconditions:** [事前条件]
- **Input:** [入力データ]
- **Expected Output:** [期待結果]
- **Verification:** [検証方法（assert 内容等）]
- **Evidence:** [EV-{category}-{NNN} を列挙。このケースが守る現行挙動・契約の根拠 EV]

#### UT-1.2: [テストケース名]
- **Category:** Boundary Values
- **Preconditions:** [事前条件]
- **Input:** [入力データ（境界値）]
- **Expected Output:** [期待結果]
- **Verification:** [検証方法]

#### UT-1.3: [テストケース名]
- **Category:** Error Handling
- **Preconditions:** [事前条件]
- **Input:** [異常入力]
- **Expected Output:** [エラー種別・メッセージ]
- **Verification:** [検証方法]

#### UT-1.4: [テストケース名]
- **Category:** Edge Cases
- **Preconditions:** [事前条件]
- **Input:** [エッジケース入力]
- **Expected Output:** [期待結果]
- **Verification:** [検証方法]

### Component: [ComponentName2]
- **Target:** [テスト対象のモジュール/ファイルパス]
- **Dependencies to Mock:** [モック対象の依存コンポーネント]

#### UT-2.1: [テストケース名]
- **Category:** Happy Path
- **Preconditions:** [事前条件]
- **Input:** [入力データ]
- **Expected Output:** [期待結果]
- **Verification:** [検証方法]

[必要なコンポーネント分だけ繰り返す]

---

## Component Test Specifications

> **責務範囲（H-2 で新設）**: CT (Component Test) は **component reactivity**（mount → signal 操作 → DOM 観測）を対象とする。pure logic は UT の責務。実 server 通信は IT or ST。詳細は `quality-checks.md` QC14 + `tdd-skills-rust/references/leptos-frontend-testing.md` セクション 6 参照。

### CT-1: [コンポーネント名 — 検証シナリオ]
- **Component:** [対象 component（design.md DES-N の Test Layers に CT/CT-N が含まれること）]
- **Mount Setup:** [例: `mount_to(test_wrapper, || view! { <SimpleCounter initial_value=0 /> })`]
- **Action:** [signal 操作 or DOM event trigger。例: `inc_button.click(); tick().await;` (3 回連続 click)]
- **DOM Verification:** [query_selector + text_content / inner_html。例: `wrapper.query_selector("[data-testid='counter-value']").text_content() == "3"`]
- **Signal Verification (該当時):** [reactive update が正しく行われたか。例: counter signal の値が 3 になっていること（DOM 経由で間接観測）]
- **Test Tool:** wasm-bindgen-test（Rust/Leptos）/ bUnit（.NET/Blazor）/ @testing-library（React/Vue）

### CT-2: [コンポーネント名 — 検証シナリオ]
- **Component:** [対象 component]
- **Mount Setup:** [...]
- **Action:** [...]
- **DOM Verification:** [...]
- **Signal Verification (該当時):** [...]
- **Test Tool:** [...]

[必要なシナリオ分だけ繰り返す]

---

## Integration Test Specifications

> **責務範囲（J-1 で厳格化）**: IT は **backend HTTP API のみ**を対象とする。フロントの Resource → server fn 境界を含む統合動作は CT (Component Test) または ST (System Test) の責務。「server fn 経由」表記を IT 仕様で使うことは禁止。詳細は `quality-checks.md` の Test Taxonomy 参照。

### IT-1: [統合テストシナリオ名]
- **Components:** [関与するコンポーネント一覧]
- **Interaction:** [テスト対象の相互作用の説明]
- **Technology:**
  - **DB:** testcontainers (PostgreSQL) | docker-compose.test.yml
  - **External API:** wiremock container | trait-based DI | nock
  - **Setup:** migration + seed data via container
- **Preconditions:** [事前条件（DB状態、外部サービス状態等）]
- **Steps:**
  1. [操作手順1]
  2. [操作手順2]
  3. [操作手順3]
- **Expected Result:** [期待される最終結果]
- **Verification Points:**
  - [検証ポイント1: 例 — DB にレコードが挿入されていること]
  - [検証ポイント2: 例 — レスポンスの HTTP ステータスが 201 であること]

### IT-2: [統合テストシナリオ名]
- **Components:** [関与するコンポーネント一覧]
- **Interaction:** [テスト対象の相互作用の説明]
- **Technology:**
  - **DB:** testcontainers (PostgreSQL) | docker-compose.test.yml
  - **External API:** wiremock container | trait-based DI | nock
  - **Setup:** migration + seed data via container
- **Preconditions:** [事前条件]
- **Steps:**
  1. [操作手順1]
  2. [操作手順2]
- **Expected Result:** [期待される最終結果]
- **Verification Points:**
  - [検証ポイント1]
  - [検証ポイント2]

[必要なシナリオ分だけ繰り返す]

---

## System Test Specifications

> **責務範囲（J-6 で新設）**: ST は **単一機能の full-stack 動作**（UI 操作 → backend 応答 → UI 反映）を 1 機能分検証する。複数機能の連鎖を含むシナリオは E2E に振る。pure logic / component reactivity 単独 / backend HTTP API のみ は対象外。詳細は `quality-checks.md` の Test Taxonomy 参照。

### ST-1: [機能名]
- **Feature Scope:** [対象機能の範囲（例: ログイン機能のみ、検索機能のみ）]
- **Requirement:** [対応する REQ-N / Acceptance Criteria]
- **Technology:**
  - **Runner:** Playwright | Cypress
  - **App Container:** docker-compose up で実 server 起動
  - **DB Setup:** migration + seed via container
  - **Browser:** Chromium | Firefox | WebKit
- **Test Path:**
  1. [UI 操作1] → [backend 応答] → [UI 反映]
  2. [UI 操作2] → [backend 応答] → [UI 反映]
- **Verification Points:**
  - [検証ポイント1: 例 — 入力に対して期待されるレスポンスが UI に表示されること]
  - [検証ポイント2: 例 — エラー時に適切なメッセージが UI に表示されること]
- **Expected Outcome:** [機能が期待通り動作する全体像]

### ST-2: [機能名]
- **Feature Scope:** [対象機能]
- **Requirement:** [対応する REQ-N]
- **Technology:**
  - **Runner:** Playwright | Cypress
- **Test Path:**
  1. [UI 操作] → [backend 応答] → [UI 反映]
- **Verification Points:**
  - [検証ポイント]
- **Expected Outcome:** [期待結果]

[必要な機能分だけ繰り返す]

---

## E2E Test Specifications

> **責務範囲（J-2 で厳格化）**: E2E は **user journey 専用**（複数機能の連鎖を含むエンドツーエンドのフロー）。個別機能の単独テスト（zoom のみ、検索のみ など）は ST の責務。「e2e-zoom-rotate.spec.ts」のような単一機能 E2E は禁止。詳細は `quality-checks.md` の Test Taxonomy 参照。

### E2E-1: [ユーザージャーニー名]
- **User Story:** [対応するユーザーストーリー（REQ-N の参照）]
- **Test Type:** API E2E | Browser E2E | Full-Stack E2E
- **Technology:**
  - **Runner:** Playwright | Cypress | reqwest | supertest
  - **App Container:** docker-compose up で全サービス起動
  - **DB Setup:** migration + seed via container
  - **Browser:** Chromium | Firefox | WebKit (Browser E2E のみ)
- **Preconditions:** [システム状態の前提条件]
- **Scenario Steps:**
  1. [ユーザー操作1] → [期待されるシステム応答]
  2. [ユーザー操作2] → [期待されるシステム応答]
  3. [ユーザー操作3] → [期待されるシステム応答]
- **Success Criteria:** [最終的な成功判定条件]
- **Failure Scenarios:**
  - [想定される失敗パターン1 → 期待される挙動]
  - [想定される失敗パターン2 → 期待される挙動]

### E2E-2: [ユーザージャーニー名]
- **User Story:** [対応するユーザーストーリー]
- **Test Type:** API E2E | Browser E2E | Full-Stack E2E
- **Technology:**
  - **Runner:** Playwright | Cypress | reqwest | supertest
  - **App Container:** docker-compose up で全サービス起動
  - **DB Setup:** migration + seed via container
  - **Browser:** Chromium | Firefox | WebKit (Browser E2E のみ)
- **Preconditions:** [前提条件]
- **Scenario Steps:**
  1. [操作1] → [応答]
  2. [操作2] → [応答]
- **Success Criteria:** [成功判定条件]
- **Failure Scenarios:**
  - [失敗パターン → 期待される挙動]

[必要なジャーニー分だけ繰り返す]

---

## Visual Regression Test Specifications

> **適用条件**: UI を持つプロジェクト（フロントエンド、デスクトップアプリ等）のみ。
> UI を持たないプロジェクト（API サーバー、CLI ツール、ライブラリ等）はこのセクションを「N/A — UI コンポーネントなし」と記載して省略する。

### VRT ツール設定

| 設定項目 | 値 |
|---------|-----|
| ツール | [例: Playwright screenshot comparison / Percy / Chromatic / BackstopJS] |
| ベースライン管理 | [例: スナップショットを Git 管理 / クラウドサービスで管理] |
| 許容閾値 | [例: ピクセル差分 0.1% 以下] |
| 対象ビューポート | [例: 1280x720 (Desktop), 375x812 (Mobile)] |

### VRT-1: [ビジュアルテストシナリオ名]
- **対象ページ/コンポーネント:** [例: ログインページ, ダッシュボード]
- **状態:** [例: 初期表示、データ読み込み済み、エラー表示]
- **ビューポート:** [例: Desktop + Mobile]
- **スナップショット比較:** [例: ベースライン画像との全体比較]

### Playwright VRT 設定例（参考）

```typescript
// playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.001,  // 0.1% 以下の差分を許容
    },
  },
});

// tests/vrt/login.spec.ts
import { test, expect } from '@playwright/test';

test('login page visual regression', async ({ page }) => {
  await page.goto('/login');
  await expect(page).toHaveScreenshot('login-page.png');
});
```

### CI 統合

- **PR CI**: VRT を実行し、差分がある場合は PR コメントにスクリーンショット差分を投稿
- **ベースライン更新**: `npx playwright test --update-snapshots` でベースラインを更新し commit
- **失敗時**: 意図的なデザイン変更なら `--update-snapshots` で更新、意図しない変更ならバグとして修正

### DOM スナップショット・アクセシビリティツリー検証

> **適用条件**: Browser E2E テストを持つプロジェクトのみ。API のみのプロジェクトは「N/A — ブラウザテストなし」と記載。

#### 検証手法

| 手法 | ツール | 用途 |
|------|--------|------|
| DOM スナップショット | Playwright `page.content()` / Playwright MCP `browser_snapshot` | ページ構造の変更検出 |
| アクセシビリティツリー | Playwright `page.accessibility.snapshot()` / Playwright MCP `browser_snapshot` | a11y 構造の検証 |
| スクリーンショット比較 | Playwright `page.screenshot()` / Playwright MCP `browser_take_screenshot` | ビジュアル差分検出 |

#### Playwright MCP を使ったランタイム検証（参考）

エージェントが Playwright MCP サーバー経由で CDP (Chrome DevTools Protocol) を使用し、
ランタイムでブラウザ操作・DOM 検査・スクリーンショット取得を行うことができる。

- `.mcp.json` に `@playwright/mcp` が設定されている場合、エージェントは `browser_snapshot` でアクセシビリティツリーを取得し DOM 構造を意味的に検証できる
- `browser_take_screenshot` で VRT ベースラインとの比較用スクリーンショットを取得できる
- `browser_evaluate` で CDP 経由の JavaScript 実行（パフォーマンス計測、DOM 操作等）が可能

#### DOM-1: [DOM スナップショットシナリオ名]
- **対象ページ:** [例: ダッシュボード]
- **検証内容:** [例: 主要なセマンティック要素（nav, main, aside）の存在と構造]
- **キャプチャタイミング:** [例: データ読み込み完了後]
- **比較方法:** [例: アクセシビリティツリーのスナップショット比較]

[必要なシナリオ分だけ繰り返す]

---

## Requirements-Test Traceability Matrix

| Requirement ID | UT Specs | IT Specs | E2E Specs | Notes |
|---------------|----------|----------|-----------|-------|
| REQ-1 | UT-1.1, UT-1.2 | IT-1 | E2E-1 | |
| REQ-2 | UT-2.1 | IT-2 | E2E-1, E2E-2 | |
| REQ-N | | | | |

**カバレッジ基準**: 全 Requirement ID に対して、最低1つの UT と、関連する IT または E2E が紐づいていること。

---

## Test Data Requirements

### Shared Test Fixtures
[テスト間で共有するテストデータの定義]

| Fixture Name | Description | Used By |
|-------------|-------------|---------|
| [fixture1] | [説明] | UT-1.1, IT-1 |
| [fixture2] | [説明] | UT-2.1, E2E-1 |

### Test Data Generation Strategy
[テストデータの生成方針: ファクトリパターン、ビルダーパターン、フィクスチャファイル等]

- **ユニットテスト**: [例 — テスト内でインラインで生成、ビルダーパターン使用]
- **統合テスト**: [例 — testcontainers で DB コンテナ起動 + マイグレーション + シードデータ]
- **E2Eテスト**: [例 — docker-compose.test.yml で全サービス起動、API 経由でデータ投入]

---

## E2E Test Infrastructure

### Project Type Detection

| 検出条件 | テストランナー | DB 戦略 |
|----------|-------------|---------|
| `Cargo.toml` + `[package.metadata.leptos]` | Playwright + reqwest | testcontainers |
| `Cargo.toml` + axum/actix-web | reqwest | testcontainers |
| `package.json` + React/Next.js | Playwright | testcontainers / docker-compose |
| `package.json` + Express/Fastify | supertest + Playwright | testcontainers |

### Container Test Setup

- **IT (統合テスト)**: testcontainers でテストプロセス内からコンテナを起動・破棄。テストごとにクリーンな状態を保証
- **E2E**: docker-compose.test.yml で全サービスを起動後にテスト実行。終了後にコンテナ停止・クリーンアップ

### docker-compose.test.yml
[テスト専用の compose 定義]
- ポート衝突回避: 5桁のランダムポート（10000-65535）を環境変数で渡す。固定オフセット（5432→15432 等）は他プロセスと競合しやすいため使用しない
- ポート生成例: `shuf -i 10000-65535 -n 1`、`python3 -c 'import random; print(random.randint(10000, 65535))'`、または `node -e "console.log(Math.floor(Math.random() * (65535 - 10000 + 1)) + 10000)"`
- docker-compose.test.yml ではポートを環境変数で参照し、未設定時は fail させる（例: `${TEST_DB_PORT:?TEST_DB_PORT must be set}:5432`）
- DB 初期化: テスト用マイグレーション + シードデータ
- ボリューム: tmpfs で永続化しない（テストごとにクリーン）

### Test Server Setup
[テスト時のアプリケーションサーバ起動方法]
- ランダムポートを生成してから compose を起動:
  ```bash
  export TEST_DB_PORT=$(python3 -c 'import random; print(random.randint(10000, 65535))')
  export TEST_APP_PORT=$(python3 -c 'import random; print(random.randint(10000, 65535))')
  docker-compose -f docker-compose.test.yml up -d
  ```
- ヘルスチェック待機後にテスト開始

### Browser Test Configuration (フロントエンドがある場合)
[Playwright / Cypress の設定]
- **baseURL:** [例: http://localhost:${TEST_APP_PORT}]（環境変数で動的に解決）
- **viewport:** [例: 1280x720]
- **timeout:** [例: 30000ms]
- **screenshot:** on failure

### ランタイムブラウザ操作（Playwright MCP / CDP）

エージェントが UI 検証を行う場合、Playwright MCP サーバーを使用してランタイムでブラウザを操作できる。
プラグインの `.mcp.json` に Playwright MCP サーバーが設定されている場合、以下のツールが利用可能:

| ツール | 用途 |
|--------|------|
| `browser_navigate` | ページ遷移 |
| `browser_snapshot` | DOM スナップショット・アクセシビリティツリー取得 |
| `browser_take_screenshot` | スクリーンショット取得 |
| `browser_click` / `browser_fill_form` | UI 操作 |
| `browser_evaluate` | JavaScript 実行（CDP 経由） |

> **N/A 条件**: UI を持たないプロジェクトでは不要。test-design.md で「N/A — UI コンポーネントなし」と記載。
