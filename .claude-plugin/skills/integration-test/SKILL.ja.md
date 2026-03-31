---
name: integration-test
description: "Agent Teams を使ってインテグレーションテスト作成を並列化する。Worker（alpha/bravo）がテストを実装し、Pentagon が品質レビューを行う。インテグレーションテスト、Axum、Diesel、testcontainers、Agent Teams、pentagon に関連するタスクに使用する。"
argument-hint: "<domain>[,<domain>...] [--dry-run] [--base-branch <branch>]"
user-invokable: true
---

# integration-test

Agent Teams を使って `tests/integration/` 配下のインテグレーションテストを並列作成するスキル。
Worker（alpha/bravo）がテストを実装し、Pentagon が品質ゲートでレビューする。

技術スタック: Axum + Diesel + diesel-async + Valkey (redis-rs) + testcontainers-rs

## 実行環境ルール

| ルール | 説明 |
|-------|------|
| **自分でブランチ/ワークツリーを作成しない** | `git checkout -b` / `git worktree add` を直接実行しない |
| **`--base-branch` 未指定時** | 現在のディレクトリの現在のブランチで作業する |
| **`--base-branch` 指定時** | `create-git-worktree` スキルでワークツリーを作成する |

## 設計方針

| 依存タイプ | 方針 |
|-----------|------|
| **DB (PostgreSQL)** | testcontainers-rs 経由で実際の PostgreSQL コンテナを使用（モックなし） |
| **外部 HTTP API** | trait ベースの DI でテストダブルに差し替え |
| **Valkey / キャッシュ** | testcontainers-rs または trait DI オーバーライド |

## チーム構成（常に3ロール）

| ロール | エージェント | 責務 |
|-------|-----------|------|
| **Command**（リーダー） | メインエージェント | 指揮と戦略立案 |
| **Worker**（alpha/bravo） | サブエージェント x 1-2 | テスト実装 |
| **Pentagon**（レビュアー） | サブエージェント | 品質レビューと判定 |

## 引数

`$ARGS` はドメイン名のカンマ区切りリストで指定（例: `users,posts`）。

| 引数 | 必須 | 説明 |
|-----|:----:|------|
| `$ARGS` | YES | `{domain}[,{domain}...]`（カンマ区切り） |
| `--dry-run` | - | 割り当てプランを表示して終了 |
| `--base-branch <branch>` | - | ワークツリーの派生元ブランチ |
| `--api <method>` | - | 特定の HTTP メソッドのみを対象 |

### 使用例

```bash
# 並列実行（2ターゲット）
/integration-test users,posts

# dry-run（プランのみ表示）
/integration-test users,posts --dry-run

# 単一ターゲット（alpha 1 + Pentagon 1）
/integration-test sessions

# 特定メソッドのみ
/integration-test users --api GET
```

---

## フロー概要

```
/integration-test users,posts
    |
    +-- [P0] 解析 & 分析
    |     +-- 引数を解析（カンマ区切り）
    |     +-- 各ターゲット: handler → repository → model をトレース
    |     +-- Worker 割り当てプラン
    |     +-- --dry-run: プランのみ表示して終了
    |
    +-- [P1] チームセットアップ
    |     +-- テストヘルパーと共有フィクスチャの事前チェック
    |     +-- ホワイトボード作成
    |
    +-- [P2] エージェント起動
    |     +-- Worker（alpha/bravo）x 1-2 を起動
    |     +-- Pentagon x 1 を起動
    |     +-- 初期タスクの割り当て
    |
    +-- [P3] モニタリング & ファシリテーション
    |     +-- Worker 完了 → Pentagon にレビュー依頼
    |     +-- PASS → ホワイトボード更新、次のタスク割り当て
    |     +-- FAIL → Worker に差し戻し（最大3回）
    |
    +-- [P4] 最終検証
    |     +-- 全テストファイルで cargo test 実行
    |     +-- rustfmt + clippy
    |
    +-- [P5] クリーンアップ & レポート
          +-- 結果の集約
          +-- ホワイトボードのクリーンアップ
          +-- 最終レポート出力
```

---

## 実行者への指示

**あなた（Command）は以下の手順に従ってチームを管理する。**

### P0: 解析 & 分析

1. `$ARGS` をカンマで分割してターゲットリストを構築
2. **各ターゲットについて**:
   - ハンドラーの特定: `src/handlers/{domain}.rs` からルートとハンドラーをトレース
   - リポジトリの特定: `src/db/repository/{domain}.rs` からクエリロジックを分析
   - モデルの特定: `src/models/{domain}.rs` から Diesel モデルを確認
   - 外部依存の特定: trait ベースの依存関係（外部 API クライアントなど）を検出
3. **Worker 割り当て**: テストファイル単位で Worker に割り当て。割当前に `resource-aware-parallelism.md` のリソース検出スニペットを実行し `MAX_HEAVY_AGENTS` を取得する。Worker 数は `min(下表の Workers 列, MAX_HEAVY_AGENTS)` に制限する。

   | ターゲット数 | MAX_HEAVY_AGENTS | Worker 数 | 割り当て方法 |
   |:------:|:------:|:---------:|---------|
   | 1 | any | 1 | すべて alpha |
   | 2 | >= 2 | 2 | alpha / bravo に1つずつ |
   | 2 | 1 | 1 | すべて alpha（逐次） |
   | 3+ | >= 2 | 2 | ラウンドロビン |
   | 3+ | 1 | 1 | すべて alpha（逐次） |

4. **`--dry-run` の場合**: 以下を出力して終了

```
[dry-run] Assignment plan:
  alpha: {domain_a} -> tests/integration/test_{domain_a}.rs
    - {method} {path}
  bravo: {domain_b} -> tests/integration/test_{domain_b}.rs
    - {method} {path}
  pentagon: quality review
```

### P1: チームセットアップ

1. 共有テストヘルパー（`tests/integration/helpers/`）の確認・更新
2. ホワイトボード作成: [whiteboard-template.md](references/whiteboard-template.md) に従って作成
   - **必ず Key Questions を設定**（1-3項目）

### P2: エージェント起動

Worker と Pentagon をサブエージェントとして起動する。`.claude/agents/` 配下のエージェント定義を `subagent_type` で指定する。

**リソース適応型並列制御**: P0 で取得した `MAX_HEAVY_AGENTS` に基づき Worker 数を制限する。リソース検出結果をログに記録する:
```
[resource-check] CPU: {CPU_CORES} cores, Free memory: {FREE_MEM_MB}MB, MAX_HEAVY_AGENTS: {MAX_HEAVY_AGENTS}
[worker-limit] Requested {N} workers, launching {M} (limited by MAX_HEAVY_AGENTS)
```

**Pentagon を起動**（レビューリクエスト待機状態にするため先に起動）:
```
Agent(
  subagent_type: "spec-workflow-mcp:integ-test-auditor",
  prompt: "Whiteboard: {whiteboard_path}\nPlease wait for a review request from Command."
)
```

**Worker を起動**（[worker-prompt.md](references/worker-prompt.md) から変数を埋める）:
```
Agent(
  subagent_type: "spec-workflow-mcp:integ-test-worker",
  prompt: "Worker name: {worker_name}\nDomain: {domain}\nTest file: tests/integration/test_{domain}.rs\nTarget endpoints:\n{endpoint_list}\nWhiteboard: {whiteboard_path}"
)
```

ターゲットが2つ以上かつ `MAX_HEAVY_AGENTS >= 2` の場合、alpha/bravo を並列起動。それ以外は alpha のみ起動し、すべてのターゲットを逐次割り当て。

### P3: モニタリング & ファシリテーション

メインループ: すべてのタスクが完了するまでモニタリング。

**Worker が完了した場合**:
1. Worker の Findings をホワイトボードにコピー
2. Pentagon にレビューをリクエスト

**Pentagon が PASS を返した場合**:
1. ホワイトボードの Quality Gate Results を更新
2. 未割り当てタスクがあれば Worker に割り当て

**Pentagon が FAIL を返した場合**:
1. レビュー回数をカウント（テストファイル単位）
2. 3回未満: レビューコメントを含むプロンプトで Worker を再実行
3. 3回目: 残存問題をホワイトボードに記録して完了とする

### P4: 最終検証

```bash
# 全テストファイルで実行
cargo test --test test_{domain} -- --nocapture

# コード品質
cargo fmt --all -- --check
cargo clippy --quiet --all-targets -- -D warnings
```

検証に失敗した場合、Command が直接修正する。

### P5: クリーンアップ & レポート

1. ホワイトボードを `.claude/_docs/deleted/` に移動
2. 最終レポートを出力:

```
integration-test parallel implementation complete

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Targets: {targets}

Generated files:
  {file_list}

Test results:
  {test_summary}

Quality gate:
  {quality_gate_results}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## リファレンス

| ドキュメント | 目的 |
|-----------|------|
| [quality-gate.md](references/quality-gate.md) | Pentagon の判定基準 |
| [test-case-design.md](references/test-case-design.md) | テストケース5分類 |
| [test-patterns.md](references/test-patterns.md) | テスト実装パターン |
| [fixture-catalog.md](references/fixture-catalog.md) | 共有ヘルパー・フィクスチャカタログ |
| [external-api-mock.md](references/external-api-mock.md) | 外部 API モックパターン |
| [worker-prompt.md](references/worker-prompt.md) | Worker プロンプトテンプレート |
| [auditor-prompt.md](references/auditor-prompt.md) | Pentagon プロンプトテンプレート |
| [whiteboard-template.md](references/whiteboard-template.md) | ホワイトボードテンプレート |
| [parallel-execution.md](references/parallel-execution.md) | 並列実行フロー詳細 |
