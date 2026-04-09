---
always_apply: true
---

# Feedback Loop

## FL1: Distinction from Built-in Memory

- **know-how** (`.claude/_docs/know-how/`): Project-specific practical knowledge. Managed under Git and shared with the team. Technical decisions, pitfalls, and best practices.
- **built-in memory** (`~/.claude/projects/.../memory/`): Personal preferences and working style. Not under Git management.

When in doubt, ask "Should team members know this?" Yes → know-how, No → memory.

## FL2: Referencing at Task Start

Before starting a task, check `.claude/_docs/know-how/INDEX.md`, and if there is relevant know-how, Read the corresponding file.

Reference flow:
1. Check the domain list in INDEX.md
2. Identify domains that match the task's keywords (e.g., "testing", "migration", "cache")
3. Reflect the relevant know-how's "checklists" and "counter-examples" in your implementation decisions

If INDEX.md is empty or no matching domain exists, you may skip this step.

## FL3: Detecting and Recording Feedback

When any of the following is detected, use the `/knowhow-capture` skill to record know-how:

- The user says something like "remember this" or "from next time, do ~" → Skill Pattern A (record immediately)
- The user corrects or negates an AI judgment → Skill Pattern B (proposal type)
- The same feedback has been received two or more times → Skill Pattern B (proposal type)

For recording procedures, format, and rule promotion, follow the `/knowhow-capture` skill.

## FL4: Promotion Paths

Know-how that matures beyond practical tips can be promoted to more formal artifacts:

| From | To | Condition | Skill |
|------|----|-----------|-------|
| know-how | `.claude-plugin/rules/` | Established convention that should be enforced | `/knowhow-capture` ("make it a rule") |
| know-how (domain: architecture) | `.claude/_docs/adr/` | Significant irreversible architectural decision | `/adr` |
| know-how (domain: debugging/architecture) | `.claude/_docs/tech-debt/` | 個別の tips ではなく構造的・慢性的な問題 | `/tech-debt add` |

When promoting to an ADR, the know-how file is kept (as background context) and the ADR references it.
When promoting to tech-debt, the know-how file is kept and the tech-debt entry's 概要 section references the original know-how.

## FL5: Periodic Knowledge Audit (P5-04)

定期的に暗黙知の特定を行い、「あの人に聞けばわかる」状態を解消する。

- **タイミング**: Phase Review 完了時、または `/knowhow-capture --audit` で手動実行
- **対象**: 単一著者に集中しているファイル、ドキュメントのないドメインロジック、非自明な設定値
- **出力**: Knowledge Gap Report → know-how 記録（Pattern A）または ADR 作成
- **CI 連携**: `scheduled-quality.yml` に知識集中チェックを組み込み可能（`--with-scheduled` で有効化）

## FL6: Agent Failure Pattern Improvement Cycle (P9-05)

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

- 重大な変更は `/adr` で ADR を作成し、元の agent-improvement know-how エントリをコンテキストとして参照
- 軽微な改善（プロンプト調整、閾値変更）は know-how エントリ自体のステータスを「適用済み」に更新
