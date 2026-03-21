# ホワイトボードテンプレート

Command が P1 で作成するホワイトボード。
作成場所: `.claude/_docs/plans/integ-test-wb-{timestamp}.md`

---

```markdown
# Integration Test Whiteboard

## Goal
{対象ドメインのインテグレーションテストを作成する}

## Team Structure
| Role | Name | Assignment |
|------|------|-----------|
| Command | main | 司令塔 |
| Worker alpha | agent-alpha | {domain_a} |
| Worker bravo | agent-bravo | {domain_b} |
| Pentagon | agent-pentagon | 品質レビュー |

## How Our Work Connects
- alpha と bravo は独立したテストファイルを担当する
- 共通ヘルパー（TestContext 等）は Command が事前に準備する
- Pentagon は各 Worker の成果物を品質ゲートで審査する

## Key Questions
1. {Worker 間で共有すべき問い — 例: 認証エラーのレスポンス構造は共通か？}
2. {例: テストデータの seed パターンに共通化できる部分は？}

## Shared Resources
- tests/integration/helpers/mod.rs — 共通ヘルパー
- tests/integration/helpers/app.rs — テスト用 Axum app 構築
- tests/integration/helpers/db.rs — testcontainers セットアップ

## File Assignment
| Worker | File | Status |
|--------|------|--------|
| alpha | tests/integration/test_{domain_a}.rs | pending |
| bravo | tests/integration/test_{domain_b}.rs | pending |

## Analysis Summary
### {domain_a}
- Endpoints: {endpoint_list}
- External deps: {deps}

### {domain_b}
- Endpoints: {endpoint_list}
- External deps: {deps}

## Alpha Findings
(Worker alpha が記入 — Command が転記)

## Bravo Findings
(Worker bravo が記入 — Command が転記)

## Pentagon Reviews
| File | Cycle | Result | Notes |
|------|:-----:|:------:|-------|

## Cross-Cutting Observations
(チーム全体で共有すべき発見)

## Quality Gate Results
| File | Status | Reviewer |
|------|:------:|----------|
```

---

## 読み書きルール

| 操作 | 誰が | いつ |
|------|------|------|
| 作成 | Command | P1 |
| Key Questions 設定 | Command | P1 |
| Analysis Summary 記入 | Command | P0 完了時 |
| Worker Findings 転記 | Command | Worker 完了時 |
| Pentagon Reviews 記入 | Command | Pentagon レビュー完了時 |
| Quality Gate Results 更新 | Command | Pentagon PASS 時 |
| 削除（`.claude/_docs/deleted/` へ移動） | Command | P5 |
