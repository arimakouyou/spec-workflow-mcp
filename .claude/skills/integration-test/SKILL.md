---
name: integration-test
description: "Agent Teams でインテグレーションテストを並列作成する。Workers（alpha/bravo）がテストを実装し、Pentagon が品質レビューを実施。integration test, Axum, Diesel, testcontainers, Agent Teams, pentagon に関連するタスクで使用。"
argument-hint: "<domain> <resource> [--dry-run] [--base-branch <branch>]"
user-invokable: true
---

# integration-test

Agent Teams で `tests/integration/` にインテグレーションテストを並列作成するスキル。
Workers（alpha/bravo）がテストを実装し、Pentagon が品質ゲートでレビューする。

技術スタック: Axum + Diesel + diesel-async + Valkey (redis-rs) + testcontainers-rs

## 実行環境ルール

| ルール | 説明 |
|--------|------|
| **ブランチ/worktree の独自作成禁止** | `git checkout -b` / `git worktree add` を直接実行しない |
| **`--base-branch` 未指定時** | カレントディレクトリ・カレントブランチで作業 |
| **`--base-branch` 指定時** | `create-git-worktree` スキル経由で worktree を作成 |

## 設計方針

| 依存種別 | 方針 |
|----------|------|
| **DB (PostgreSQL)** | testcontainers-rs で実 PostgreSQL コンテナ（モック不可） |
| **外部 HTTP API** | trait ベースの DI でテストダブルに差し替え |
| **Valkey / キャッシュ** | testcontainers-rs or trait DI override |

## チーム構成（常時 3 役）

| 役割 | エージェント | 責務 |
|------|------------|------|
| **Command** (Leader) | メインエージェント | 司令塔・作戦立案 |
| **Workers**（alpha/bravo） | サブエージェント x 1-2 | テスト実装 |
| **Pentagon** (Reviewer) | サブエージェント | 品質レビュー・判定 |

## Arguments

`$ARGS` はカンマ区切りの `{domain}/{resource}` で指定する。

| 引数 | 必須 | 説明 |
|------|:----:|------|
| `$ARGS` | YES | `{domain}/{resource}[,...]` |
| `--dry-run` | - | 分担計画を表示して終了 |
| `--base-branch <branch>` | - | worktree 派生元ブランチ |
| `--api <method>` | - | 特定 HTTP メソッドのみ |

### Usage Examples

```bash
# 並列実行（2 対象）
/integration-test users,posts

# dry-run（計画のみ表示）
/integration-test users,posts --dry-run

# 単一対象（alpha 1 + Pentagon 1）
/integration-test sessions

# 特定メソッドのみ
/integration-test users --api GET
```

---

## Flow Overview

```
/integration-test users,posts
    |
    +-- [P0] Parse & Analyze
    |     +-- 引数パース（カンマ区切り）
    |     +-- 各対象: handler → repository → model を追跡
    |     +-- Worker 分担計画
    |     +-- --dry-run: 計画表示のみで終了
    |
    +-- [P1] Setup Team
    |     +-- テスト用ヘルパー・共通 fixture 事前確認
    |     +-- ホワイトボード作成
    |
    +-- [P2] Launch Agents
    |     +-- Workers（alpha/bravo）x 1-2 起動
    |     +-- Pentagon x 1 起動
    |     +-- 最初のタスク割当
    |
    +-- [P3] Monitor & Facilitate
    |     +-- Worker 完了 -> Pentagon レビュー依頼
    |     +-- PASS -> ホワイトボード更新、次タスク割当
    |     +-- FAIL -> Worker に差し戻し（最大 3 回）
    |
    +-- [P4] Final Verification
    |     +-- cargo test 横断実行
    |     +-- rustfmt + clippy
    |
    +-- [P5] Cleanup & Report
          +-- 結果集約
          +-- ホワイトボード整理
          +-- 最終レポート出力
```

---

## Executor Instructions

**あなた（Command）が以下の手順でチームを運営してください。**

### P0: Parse & Analyze

1. `$ARGS` をカンマで分割し、対象リストを作成
2. **各対象に対して**:
   - handler 特定: `src/handlers/{domain}.rs` からルート・ハンドラを追跡
   - repository 特定: `src/db/repository/{domain}.rs` からクエリロジックを分析
   - model 特定: `src/models/{domain}.rs` から Diesel モデルを確認
   - 外部依存特定: trait ベースの依存 (外部 API クライアント等) を特定
3. **Worker 分担**: テストファイル単位で Worker に割当

   | 対象数 | Worker 数 | 割当方法 |
   |:------:|:---------:|---------|
   | 1 | 1 | alpha に全て |
   | 2 | 2 | alpha / bravo に 1 つずつ |
   | 3+ | 2 | ラウンドロビン |

4. **`--dry-run` 時**: 以下を出力して終了

```
[dry-run] 分担計画:
  alpha: {domain_a} -> tests/integration/test_{domain_a}.rs
    - {method} {path}
  bravo: {domain_b} -> tests/integration/test_{domain_b}.rs
    - {method} {path}
  pentagon: 品質レビュー
```

### P1: Setup Team

1. テスト用共通ヘルパーの確認・更新（`tests/integration/helpers/` 以下）
2. ホワイトボード作成: [whiteboard-template.md](references/whiteboard-template.md) に従い Write
   - **Key Questions を必ず設定**（1-3 個）

### P2: Launch Agents

Workers と Pentagon をサブエージェントとして起動。`.claude/agents/` のエージェント定義を `subagent_type` で指定する。

**Pentagon 起動**（先に起動してレビュー依頼待ちにする）:
```
Agent(
  subagent_type: "integ-test-auditor",
  prompt: "ホワイトボード: {whiteboard_path}\nCommand からのレビュー依頼を待機してください。"
)
```

**Worker 起動**（[worker-prompt.md](references/worker-prompt.md) の変数を埋め込み）:
```
Agent(
  subagent_type: "integ-test-worker",
  prompt: "Worker名: {worker_name}\nドメイン: {domain}\nテストファイル: tests/integration/test_{domain}.rs\n対象エンドポイント:\n{endpoint_list}\nホワイトボード: {whiteboard_path}"
)
```

対象が2つ以上の場合は alpha/bravo を並列起動する。

### P3: Monitor & Facilitate

メインループ: 全タスク完了まで監視する。

**Worker 完了時**:
1. ホワイトボードに Worker Findings を転記
2. Pentagon にレビュー依頼

**Pentagon PASS 時**:
1. ホワイトボードの Quality Gate Results を更新
2. 次の未割当タスクがあれば Worker に割当

**Pentagon FAIL 時**:
1. レビュー回数をカウント（テストファイルごと）
2. 3 回未満: 指摘事項を含む prompt で Worker を再実行
3. 3 回目: 残存指摘付きで完了扱い、ホワイトボードに注記

### P4: Final Verification

```bash
# 全テストファイル横断
cargo test --test integration_{domain} -- --nocapture

# コード品質
rustfmt tests/integration/test_{domain}.rs
cargo clippy --tests --quiet
```

失敗時は Command が直接修正。

### P5: Cleanup & Report

1. ホワイトボードを `.claude/_docs/deleted/` に移動
2. 最終レポート出力:

```
integration-test 並列実装完了

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
対象: {targets}

生成ファイル:
  {file_list}

テスト結果:
  {test_summary}

品質ゲート:
  {quality_gate_results}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## References

| ドキュメント | 用途 |
|------------|------|
| [quality-gate.md](references/quality-gate.md) | Pentagon の判定基準 |
| [test-case-design.md](references/test-case-design.md) | テストケース 5 分類 |
| [test-patterns.md](references/test-patterns.md) | テスト実装パターン |
| [fixture-catalog.md](references/fixture-catalog.md) | 共通ヘルパー・fixture 一覧 |
| [external-api-mock.md](references/external-api-mock.md) | 外部 API モックパターン |
| [worker-prompt.md](references/worker-prompt.md) | Worker プロンプトテンプレート |
| [auditor-prompt.md](references/auditor-prompt.md) | Pentagon プロンプトテンプレート |
| [whiteboard-template.md](references/whiteboard-template.md) | ホワイトボードテンプレート |
| [parallel-execution.md](references/parallel-execution.md) | 並列実行フロー詳細 |
