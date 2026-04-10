# P9（運用経済・役割定義）チェックリスト — プラグインスキル組込み計画

## Context

外部プラグイン `harness-maturity-check` の P9（運用経済・役割定義）チェックリスト 5 項目に対応するため、spec-workflow-mcp プラグインの既存ルールを拡充する。プラグインのユーザーが自身のプロジェクトで P9 準拠を達成できるようにする。

P9 は P1〜P8 の最後のピラーであり、P4〜P8 対応は前回までのセッションで完了済み。

---

## P9 チェックリスト

| ID | チェック項目 | 調査対象 |
|----|-------------|----------|
| P9-01 | agent の並列実行（複数 PR 同時進行）が可能 | Sub-Agent 並列実行パターン |
| P9-02 | 技術的負債が定期的に小粒な cleanup PR で返済 | Dependabot 等 + 定期品質チェック |
| P9-03 | レビューコメントが docs 更新やルール追加にフィードバック | ADR/意思決定記録 |
| P9-04 | ユーザーバグがツール実装や lint ルール追加に変換 | ルールエスカレーション/昇格フロー |
| P9-05 | agent の失敗パターンがハーネス改善の入力として扱われている | ハーネス改善サイクルの記録 |

---

## 現状分析

| ID | チェック項目 | 現状カバレッジ | 根拠 |
|----|-------------|--------------|------|
| P9-01 | Agent 並列実行 | **HIGH** | 8 agents + `resource-aware-parallelism.md`（CPU/メモリ動的スケーリング）+ wave-harness-worker（worktree 並列）|
| P9-02 | 技術的負債 cleanup | **HIGH** | `/setup-ci` → `dependabot.yml`（依存自動更新）+ `scheduled-quality.yml`（定期品質チェック）+ `auto-fix-quality.yml`（自動修正 PR）|
| P9-03 | レビュー→ドキュメントフィードバック | **HIGH** | `feedback-loop.md` FL3/FL4（know-how 検出→ルール/ADR 昇格）+ `/knowhow-capture` + `/adr` |
| P9-04 | バグ→ルール変換 | **HIGH** | `enforcement-levels.md`（L1→L5 昇格フロー + 自動昇格提案）+ `regression-test-policy.md` RT1-RT3 |
| P9-05 | Agent 失敗→ハーネス改善 | **LOW** | FL3 がユーザー修正を捕捉、log-implementation が reworkCount を追跡するが、失敗パターン→改善の明示的プロセスなし |

**対応が必要な項目: P9-05 のみ**

---

## 実装計画

### Step 1: P9-05 — feedback-loop.md に FL6 追加

`.claude-plugin/rules/feedback-loop.md` に `## FL6: Agent Failure Pattern Improvement Cycle (P9-05)` セクションを追加する。

FL6 は既存のメカニズム（log-implementation の reworkCount、review-worker の findings、/knowhow-capture、/adr）を**組み合わせるプロセスの文書化**であり、新しいツールやスキルの作成は不要。

#### FL6 セクション構成（約 45 行）

**1. 概要**（1-2 行）: Agent 失敗パターンをハーネス改善に還元する継続的改善サイクル

**2. 失敗シグナル検出テーブル**:

| シグナル源 | 検出条件 | データ所在 |
|-----------|---------|-----------|
| reworkCount | >= 2 | `/log-implementation` reviewProcess |
| review_action: escalate | ユーザーエスカレーション | review-worker 完了レポート |
| FL3 同一修正 | 3 回以上（セッション横断） | know-how エントリ |

**3. 記録方法**: `/knowhow-capture` を使用
- Domain: `agent-improvement`
- Pattern A（即時記録）: escalate シグナル
- Pattern B（提案型）: 高 reworkCount、繰り返し修正

**4. 定期分析**: FL5 知識監査と連動
- タイミング: Phase Review 完了時 or `--audit`
- 出力: Agent 改善レポート（agent 名 | 失敗パターン | 頻度 | 推奨アクション）
- 閾値: 同一パターン 3 回以上 → 改善必須

**5. ハーネス改善アクションテーブル**:

| 失敗パターン | 改善対象 | アーティファクト |
|-------------|---------|----------------|
| カテゴリ X で繰り返し rework | ルール明確化 | ルールファイル編集 |
| ユーザーエスカレーション頻発 | スキル/Agent 定義強化 | agent/skill .md 編集 |
| 構造的ハーネス欠陥 | アーキテクチャ決定記録 | `/adr` |

---

## 対象ファイル

| 操作 | ファイルパス | 対応 P9 |
|------|------------|---------|
| 修正 | `.claude-plugin/rules/feedback-loop.md` | P9-05 |

合計: 修正 1 ファイルのみ

---

## 検証方法

1. `npm run build` — ビルド成功確認
2. `npm test` — 全テスト PASS 確認
3. 各 P9 項目のカバレッジ確認:
   - P9-01: `resource-aware-parallelism.md` + 8 agents + wave-harness-worker
   - P9-02: `setup-ci` → dependabot.yml + scheduled-quality.yml + auto-fix-quality.yml
   - P9-03: `feedback-loop.md` FL3/FL4 + `/knowhow-capture` + `/adr`
   - P9-04: `enforcement-levels.md` 昇格フロー + `regression-test-policy.md` RT1-RT3
   - P9-05: `feedback-loop.md` FL6（新規追加）
