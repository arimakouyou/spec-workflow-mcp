# Test Design Document

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

## Integration Test Specifications

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

## E2E Test Specifications

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
- ポート衝突回避: 本番用ポートからオフセット（例: 5432 → 15432）
- DB 初期化: テスト用マイグレーション + シードデータ
- ボリューム: tmpfs で永続化しない（テストごとにクリーン）

### Test Server Setup
[テスト時のアプリケーションサーバ起動方法]
- `docker-compose -f docker-compose.test.yml up -d`
- ヘルスチェック待機後にテスト開始

### Browser Test Configuration (フロントエンドがある場合)
[Playwright / Cypress の設定]
- **baseURL:** [例: http://localhost:13000]
- **viewport:** [例: 1280x720]
- **timeout:** [例: 30000ms]
- **screenshot:** on failure
