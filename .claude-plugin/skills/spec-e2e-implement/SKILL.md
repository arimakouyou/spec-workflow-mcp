---
name: spec-e2e-implement
description: "Implement IT/E2E tests independently from main implementation. Uses test-design.md IT/E2E specifications to generate test code with container-based infrastructure (testcontainers, Playwright, docker-compose). Can run in parallel with /spec-implement. Triggers on: 'implement e2e tests', 'create e2e tests', 'e2e for X', 'integration tests for X', '/spec-e2e-implement'."
user-invokable: true
argument-hint: "<spec-name> [--scope it|e2e|all] [--spec-id IT-1,E2E-1]"
---

# E2E Test Implementation (Independent Line)

メイン実装（`/spec-implement`）とは独立して、test-design.md の IT/E2E 仕様に基づいてテストコードを生成する。コンテナベースのテストインフラ（testcontainers、docker-compose.test.yml、Playwright）を使用する。

## Prerequisites Check (MANDATORY — DO NOT SKIP)

1. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists
2. Check `.spec-workflow/specs/{spec-name}/design.md` exists
3. Check `.spec-workflow/specs/{spec-name}/test-design.md` exists
4. Check `.spec-workflow/specs/{spec-name}/tasks.md` exists

If ANY file is missing — **STOP immediately.** Inform the user which file is missing and which skill to run.

| Missing File | Required Skill |
|-------------|---------------|
| requirements.md | `/spec-requirements` |
| design.md | `/spec-design` |
| test-design.md | `/spec-test-design` |
| tasks.md | `/spec-tasks` |

## Arguments

| Argument | Required | Description |
|----------|:--------:|-------------|
| `spec-name` | YES | Spec name in kebab-case |
| `--scope` | NO | `it` (統合テストのみ), `e2e` (E2E のみ), `all` (デフォルト: 両方) |
| `--spec-id` | NO | 特定の仕様のみ実装（例: `IT-1,E2E-2`） |

## Process

### 1. Read Test Design

1. Read `.spec-workflow/specs/{spec-name}/test-design.md`
2. IT/E2E 仕様を抽出（`--scope` / `--spec-id` でフィルタ）
3. **E2E Test Infrastructure** セクションから技術選定を取得:
   - テストランナー（Playwright / reqwest / supertest 等）
   - DB 戦略（testcontainers / docker-compose.test.yml）
   - Container Test Setup 方法

### 2. Check Implementation Readiness

IT/E2E テストの対象コンポーネントがメイン実装で実装済みか確認する:

```bash
# tasks.md で対象タスクの完了状態を確認
grep -E '\[x\]|\[-\]|\[ \]' .spec-workflow/specs/{spec-name}/tasks.md
```

| 状態 | アクション |
|------|----------|
| 対象コンポーネントが全て `[x]` | テスト実装を開始 |
| 一部が `[-]` (実装中) | 完了済みコンポーネントの IT のみ実装可。E2E は待機 |
| 対象が `[ ]` (未着手) | ユーザーに報告: 「対象コンポーネントが未実装です。`/spec-implement` でメイン実装を先に進めてください」 |

### 3. Infrastructure Setup (初回のみ)

テストインフラが未セットアップの場合、以下を実行する。`_TDDSkip: true` 相当（テストインフラ自体のテストは不要）。

#### 3.1 docker-compose.test.yml の確認

```bash
# docker-compose.test.yml が存在するか確認
test -f docker-compose.test.yml && echo "exists" || echo "missing"
```

- 存在しない場合 → parallel-worker でdocker-compose.test.ymlを作成
- 存在する場合 → スキップ

#### 3.2 テストランナーのセットアップ

E2E Test Infrastructure の選定に基づいて:

| ランナー | セットアップ |
|---------|-------------|
| Playwright | `npm init playwright@latest`、`playwright.config.ts` 生成 |
| reqwest | `Cargo.toml` に `[dev-dependencies]` 追加 |
| supertest | `npm install --save-dev supertest @types/supertest` |
| testcontainers (Rust) | `Cargo.toml` に `testcontainers` 依存追加 |
| testcontainers (Node) | `npm install --save-dev testcontainers` |

#### 3.3 テストヘルパー・共通フィクスチャの作成

parallel-worker で以下を作成:

- **テスト用 DB ヘルパー**: testcontainers の起動・マイグレーション・シードデータ投入を共通化
- **テスト用 HTTP クライアント**: 認証トークン付きリクエスト送信のヘルパー
- **共通フィクスチャ**: test-design.md の Test Data Requirements に基づくシードデータ

### 4. IT Implementation

test-design.md の各 IT 仕様に対して parallel-worker でテストコードを生成する。

```javascript
Agent({
  subagent_type: "parallel-worker",
  description: "IT: Implement integration test IT-{N}",
  prompt: `Implement integration test based on the following specification.

    Project path: {project-path}
    Spec name: {spec-name}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}

    IT Specification (from test-design.md):
    {paste IT-N specification including Technology, Steps, Verification Points}

    Test design doc path: {project-path}/.spec-workflow/specs/{spec-name}/test-design.md
    Design doc path: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Container setup:
    - DB: Use testcontainers to start a clean DB container for each test
    - Apply migrations before test execution
    - Seed test data as defined in Test Data Requirements

    Important:
    - Always cd {WORKTREE_PATH} before starting
    - Test must be self-contained: start container → migrate → seed → test → cleanup
    - Each test function must clean up its own state
    - Use the test helpers created in step 3.3

    After implementation, run the test to confirm it passes.`
})
```

### 5. E2E Implementation

test-design.md の各 E2E 仕様に対してテストコードを生成する。

#### 5.1 API E2E (Test Type: API E2E)

```javascript
Agent({
  subagent_type: "parallel-worker",
  description: "E2E: Implement API E2E test E2E-{N}",
  prompt: `Implement API E2E test based on the following specification.

    {same context as IT implementation}

    E2E Specification (from test-design.md):
    {paste E2E-N specification}

    Server startup:
    1. docker-compose -f docker-compose.test.yml up -d
    2. Wait for health check to pass
    3. Run test scenarios against the running server
    4. docker-compose -f docker-compose.test.yml down after tests

    Use reqwest (Rust) or supertest (Node.js) to send HTTP requests.`
})
```

#### 5.2 Browser E2E (Test Type: Browser E2E / Full-Stack E2E)

```javascript
Agent({
  subagent_type: "parallel-worker",
  description: "E2E: Implement browser E2E test E2E-{N}",
  prompt: `Implement browser E2E test using Playwright based on the following specification.

    {same context as IT implementation}

    E2E Specification (from test-design.md):
    {paste E2E-N specification including Scenario Steps}

    Server startup:
    1. docker-compose -f docker-compose.test.yml up -d
    2. Wait for health check + frontend readiness
    3. Run Playwright tests (Scenario Steps → test code conversion)
    4. Capture screenshots on failure
    5. docker-compose -f docker-compose.test.yml down after tests

    Playwright guidelines:
    - Use page.goto(), page.click(), page.fill() for user interactions
    - Use page.waitForSelector() for dynamic content
    - Use expect(page).toHaveURL() for navigation assertions
    - Use expect(locator).toHaveText() for content assertions`
})
```

### 6. Quality Verification

全 IT/E2E テストを実行し、品質を検証する。

```bash
# IT テスト実行
cargo test --tests --quiet                 # Rust
npm run test:integration                   # Node.js

# E2E テスト実行
docker-compose -f docker-compose.test.yml up -d
npx playwright test                        # Browser E2E
cargo test --tests --quiet                 # Rust API E2E
npm run test:e2e                           # Node.js API E2E
docker-compose -f docker-compose.test.yml down
```

review-worker でテストコードのレビュー:
- テストが test-design.md の仕様を正しく反映しているか
- テストの独立性（他テストへの依存がないか）
- コンテナの適切なクリーンアップ
- テストデータの適切な管理

### 7. Report

結果を `.spec-workflow/specs/{spec-name}/reviews/e2e-implementation.md` に保存:

```markdown
# E2E Test Implementation Report

## Spec: {spec-name}
## Date: {date}
## Scope: {it|e2e|all}

## IT Tests
| Spec ID | Test File | Status | Notes |
|---------|-----------|--------|-------|
| IT-1 | tests/integration/test_xxx.rs | PASS | |
| IT-2 | tests/integration/test_yyy.rs | PASS | |

## E2E Tests
| Spec ID | Test File | Type | Status | Notes |
|---------|-----------|------|--------|-------|
| E2E-1 | tests/e2e/test_xxx.rs | API | PASS | |
| E2E-2 | e2e/journey.spec.ts | Browser | PASS | |

## Infrastructure
- docker-compose.test.yml: [created|existing]
- Test helpers: [created|existing]
- Playwright config: [created|N/A]

## Coverage
| Spec Type | Total | Implemented | Skipped (not ready) |
|-----------|-------|-------------|---------------------|
| IT | {N} | {M} | {K} |
| E2E | {N} | {M} | {K} |
```

## メイン実装との関係

- `/spec-implement` と `/spec-e2e-implement` は**独立して実行可能**
- `/spec-implement` の Final E2E Gate (Step 9) は `/spec-e2e-implement` で作成したテストも自動的に実行する
- メイン実装の進捗に応じて、実装済みコンポーネントから順次 IT テストを作成できる
- E2E テストは全コンポーネントが実装済みになってから実行する

## Rules

- Feature names use kebab-case
- テストコードはコンテナベースで実装する（testcontainers / docker-compose.test.yml）
- テストは自己完結的であること（他テストへの依存禁止）
- コンテナは必ずクリーンアップすること
- test-design.md の仕様に忠実に実装すること
- 口頭承認は不要（テスト実装は承認プロセスなし、Final E2E Gate で検証）
