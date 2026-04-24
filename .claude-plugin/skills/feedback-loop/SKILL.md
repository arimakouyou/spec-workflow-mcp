---
name: feedback-loop
description: |
  フィードバックループ運用: know-how と built-in memory の使い分け (FL1)、
  タスク開始時の know-how INDEX 参照 (FL2)、ユーザー訂正・再発フィードバック検知時の
  know-how 記録 (FL3)、know-how から rule/ADR/tech-debt への昇格パス (FL4)、
  Phase Review 完了時の定期知識監査 (FL5)、Agent 失敗パターン（reworkCount >= 2、
  review_action: escalate 等）の分析・ハーネス改善サイクル (FL6) を扱う。
  新タスク開始で関連 know-how を参照したいとき、ユーザーから訂正や
  「覚えておいて」の指示を受けたとき、同じフィードバックが 2 回以上再発したとき、
  know-how の成熟度判定やルール・ADR・tech-debt への昇格を検討するとき、
  Phase Review で単一著者集中や暗黙知の監査を行うとき、
  Agent の失敗パターン（差し戻し・エスカレーション）を分析してハーネス
  （ルール・スキル・Agent 定義）を改善したいときに参照する。
allowed-tools: [Read, Edit, Write, Bash, Grep]
---

# Feedback Loop

## FL1: know-how と built-in memory の使い分け

- **know-how** (`.claude/_docs/know-how/`): プロジェクト固有の実践的知識。Git 管理下でチームと共有する。技術的判断、落とし穴、ベストプラクティス。
- **built-in memory** (`~/.claude/projects/.../memory/`): 個人の好みや作業スタイル。Git 管理外。

迷ったときの判断基準: 「チームメンバーが知るべきか?」 Yes → know-how / No → memory。

## FL2: タスク開始時の know-how 参照

タスク開始前に `.claude/_docs/know-how/INDEX.md` を確認し、関連する know-how が
あれば対応ファイルを Read する。

参照フロー:

1. INDEX.md のドメイン一覧を確認
2. タスクのキーワード（例: "testing", "migration", "cache"）に一致するドメインを特定
3. 該当 know-how の「チェックリスト」「反例」を実装判断に反映

INDEX.md が空、または一致ドメインが無ければこのステップはスキップしてよい。

## FL3: フィードバックの検知と記録

以下のいずれかを検知した場合、`/knowhow-capture` スキルで know-how を記録する:

- ユーザーが「覚えておいて」「次からは〜」などと発言 → Pattern A（即時記録）
- ユーザーが AI の判断を訂正・否定 → Pattern B（提案型）
- 同じフィードバックを 2 回以上受けている → Pattern B（提案型）

記録手順・フォーマット・ルール昇格については `/knowhow-capture` スキルに従う。

## FL4: 昇格パス

実践的 tips を超えて成熟した know-how は、より形式的なアーティファクトに昇格できる:

| 移行元 | 移行先 | 条件 | スキル |
|------|----|-----------|-------|
| know-how | `.claude-plugin/rules/` | 強制すべき確立された規約 | `/knowhow-capture`（"make it a rule"） |
| know-how（ドメイン: architecture） | `.claude/_docs/adr/` | 重大かつ不可逆なアーキテクチャ判断 | `/adr` |
| know-how（ドメイン: debugging/architecture） | `.claude/_docs/tech-debt/` | 個別の tips ではなく構造的・慢性的な問題 | `/tech-debt add` |

- ADR に昇格する場合、know-how ファイルは背景コンテキストとして残し、ADR から参照する。
- tech-debt に昇格する場合、know-how ファイルは残し、tech-debt エントリの概要から元 know-how を参照する。

## FL5: 定期知識監査 (P5-04)

定期的に暗黙知を特定し、「あの人に聞けばわかる」状態を解消する。

- **タイミング**: Phase Review 完了時、または `/knowhow-capture --audit` で手動実行
- **対象**: 単一著者に集中しているファイル、ドキュメントのないドメインロジック、非自明な設定値
- **出力**: Knowledge Gap Report → know-how 記録（Pattern A）または ADR 作成
- **CI 連携**: `scheduled-quality.yml` に知識集中チェックを組み込み可能（`--with-scheduled` で有効化）

## FL6: Agent 失敗パターン改善サイクル (P9-05)

Agent の失敗パターンを体系的に収集・分析し、ハーネス（ルール・スキル・Agent 定義）の改善に還元する継続的改善サイクル。

### 失敗シグナルの検出

以下のシグナルを Agent 失敗パターンとして検出する:

| シグナル源 | 検出条件 | データ所在 |
|-----------|---------|-----------|
| reworkCount | >= 2（同一タスクで 2 回以上差し戻し） | `/log-implementation` の `reviewProcess.reworkCount` |
| review_action: escalate | review-worker がユーザーエスカレーション判定 | review-worker 完了レポート |
| FL3 同一修正 | セッション横断で同種の修正が 3 回以上 | know-how エントリの重複検出 |
| wave エラー | CHECK_FAILED / IMPLEMENTATION_FAILED | wave-harness-worker エラーコード |

### 記録

`/knowhow-capture` を使用して失敗パターンを記録する:

- **Domain**: `agent-improvement`
- **Pattern A**（即時記録）: `review_action: escalate` が発生した場合 — ユーザー介入が必要な重大な失敗
- **Pattern B**（提案型）: `reworkCount >= 2` や FL3 同一修正検出の場合 — 「Agent 改善 know-how として記録しますか？」と提案
- **記録必須フィールド**: Agent 名、失敗タイプ、発生頻度、根本原因仮説

### 定期分析

FL5 の知識監査と連動して agent-improvement ドメインの know-how を定期分析する:

- **タイミング**: Phase Review 完了時、または `/knowhow-capture --audit` で手動実行
- **プロセス**: agent-improvement ドメインのエントリを失敗タイプ別に集約
- **出力**: Agent 改善レポート（Agent 名 | 失敗パターン | 頻度 | 推奨アクション）
- **閾値**: 同一パターン 3 回以上 → 改善アクション必須

### ハーネス改善アクション

分析結果に基づき、以下のアクションでハーネスを改善する:

| 失敗パターン | 改善対象 | アーティファクト |
|-------------|---------|----------------|
| 特定カテゴリで繰り返し rework | ルールの明確化・反例追加 | `.claude-plugin/rules/` のルールファイル編集 |
| Agent が要件を誤解 | スキル/Agent 定義の指示強化 | `.claude-plugin/agents/` or `skills/` の .md 編集 |
| 品質チェックが問題を見逃し | チェック項目の追加・強化 | `quality-checks.md` 更新 + enforcement-levels 昇格 |
| 構造的なハーネス欠陥 | アーキテクチャ決定として記録 | `/adr` で ADR 作成（know-how エントリを参照） |

- 重大な変更は `/adr` で ADR を作成し、元の agent-improvement know-how エントリをコンテキストとして参照する。
- 軽微な改善（プロンプト調整、閾値変更）は know-how エントリ自体のステータスを「適用済み」に更新する。
