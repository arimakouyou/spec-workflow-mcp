# CoDD 記事からの品質向上機能 採用調査プラン

## Context

対象: `spec-workflow-mcp`（Claude Code 向け仕様駆動開発 MCP プラグイン）。
依頼: 以下4記事の内容で、採用すると本プラグインのワークフロー品質が向上する機能・フローを調査。

- [codd-swebench-diagnose](https://zenn.dev/shio_shoppaize/articles/codd-swebench-diagnose) — 診断の強制化 / Session State
- [codd-skeleton-complete](https://zenn.dev/shio_shoppaize/articles/codd-skeleton-complete) — 依存グラフによる整合性駆動開発
- [codd-swebench-loop](https://zenn.dev/shio_shoppaize/articles/codd-swebench-loop) — テストフィードバックループ / DIVERGENT / 段階エスカレーション
- [shogun-codd-coherence](https://zenn.dev/shio_shoppaize/articles/shogun-codd-coherence) — Wave 実行 / Impact Analysis 3段階帯域 / HITL ゲート

目的: 既存の Phase 0〜5 ワークフロー（spec-request-spec → requirements → design → test-design → tasks → implement）と `parallel-worker` / `review-worker` / TDD サイクル / Severity Classification / Wave 1/2 設計 に対し、重複せず自然に溶け込む形で採用できる機能を ROI 順に特定する。実装は別タスクで段階的に着手する前提。

## 4記事の核心サマリー

| 記事 | 核心機能 | 報告された効果 |
|------|---------|---------------|
| diagnose | 修正前に `{根本原因, 責任個所, 設計との乖離}` の3視点を言語化させる + 試行履歴（Session State）を次回プロンプトに注入 | 無駄リトライ −59% |
| loop | テスト失敗をそのまま返してリトライ + 同種失敗が続けば「共通する誤った仮定に挑戦せよ」（DIVERGENT） + バッチ→agentモード昇格 | 60% → 93.3% |
| skeleton | 設計書フロントマターに `depends_on` を宣言 → 依存グラフ化 → 影響伝搬 `impact/propagate/fix` | 80.8% → 100% |
| coherence | Wave（上流→下流の段階的生成）+ Impact Analysis を Green/Amber/Gray の3帯域で分類 + Wave 間 HITL ゲート | 18本の設計書＋実装自動生成実績 |

## 既存ワークフローとのギャップ

| 候補機能 | 既存に同等物あり? | ギャップ |
|---------|------------------|----------|
| A. 診断駆動リトライ | ✕（review-worker の Anti-Bias Protocol は観察ログ、根本原因の明文化は未要件） | `parallel-worker.md:133-144` の Retry Policy に診断セクション追加が必要 |
| B. Session State（試行履歴の参照） | △（`state.md` に進捗記録はあるが、失敗診断履歴の append-only ログはなし） | 試行ごとの `{category, diagnosis, attempted_fix, result}` を蓄積する仕組みが不在 |
| C. DIVERGENT 戦略 | ✕ | 同種失敗 N 回で仮説転換プロンプトへ切替える分岐なし |
| D. モデル/モード昇格 | ✕（test-run: Sonnet 固定、review: Opus 固定） | 現状のコスト予測性を損なうため優先度低 |
| E. 仕様書間の依存グラフ | △（タスク内 `_DependsOn` / `_Requirements` / Requirements Traceability Matrix あり、仕様書ファイル間の `depends_on` フロントマターはなし） | requirements.md ↔ design.md ↔ test-design.md の宣言的依存が欠落 |
| F. Impact Analysis（Green/Amber/Gray） | ✕（E が前提） | 上流変更時に下流の自動反映／要確認／参考を振り分ける仕組みなし |
| G. 失敗分類の標準化 | △（`spec-impl-test-run.md:60-79` でスキル独自に分類、横断統一なし） | `compile_error / test_failure / quality_check_failure / spec_mismatch` 等の共通語彙が不在 |
| H. 構造地図の提供 | ○（Wave 1 設計の Architecture/Component List、`_Leverage` が実質代替） | 新規導入は重複になる。見送り |
| I. Harness-as-Code 検証 | △（E が前提） | 仕様 ⇔ テスト ⇔ 実装のトレース整合性を自動検証する `/spec-verify` 相当が未実装 |

## 採用候補（ROI 順）

### Tier 1 — 即効・低コスト（短期、1週間以内）

**A. 診断駆動リトライ（最優先）**
- 統合先: `.claude-plugin/agents/parallel-worker.md`（Retry Policy 直前）、`.claude-plugin/agents/review-worker.md`（Anti-Bias Protocol 直後）
- MVP: リトライ前に必ず以下3行を出力させるテンプレート（10行程度）
  ```
  root_cause: <なぜこの失敗が起きたか>
  responsible_location: <ファイル:行 or モジュール>
  design_gap: <design.md / _Requirements との乖離点、なければ "none">
  ```
- 根拠: Anti-Bias Protocol は成功時の観察を求めるが、失敗時の原因明示は別目的。重複せず差別化できる
- 期待効果: 記事実測 −59% リトライ

**G. 失敗分類の標準化**
- 統合先: 新規 `.claude-plugin/rules/failure-taxonomy.md` + `spec-impl-test-run.md` / `parallel-worker.md` / `review-worker.md` の出力フォーマットに `failure_category` 必須追加
- MVP: 4カテゴリ固定（`compile_error` / `test_failure` / `quality_check_failure` / `spec_mismatch`）。既存 `last_error` は自由記述として併存
- 根拠: A/B/C/F すべての基盤になる共通語彙。ルール1本で全スキルに波及

**E. 仕様書間の依存グラフ（宣言のみ）**
- 統合先: `src/markdown/templates/design-template.md` / `test-design-template.md` / `tasks-template.md` の冒頭フロントマター
- MVP: YAML に `depends_on: [requirements.md#REQ-1, design.md#API-3]` を宣言するだけ。可視化・伝搬は後追い
- 根拠: 宣言だけなら既存テンプレ3ファイルの +10行で済み、F/I の前提にもなる

### Tier 2 — 中期（2〜4週間）

**B. Session State（試行履歴）**
- 統合先: `.spec-workflow/.attempts/{spec}/{task-id}.jsonl` への append-only ログ（PoC は MCP 側を触らず直書き）
- MVP: parallel-worker が A の診断3項目＋`failure_category`＋`diff summary` を1行 JSONL で追記。次リトライ時にそのファイルを Read
- 将来: MCP ツール化（`record_attempt` / `get_attempt_history`）して dashboard 連携

**C. DIVERGENT 戦略**
- 統合先: `parallel-worker.md` Retry Policy に「直近3件の `failure_category` が同一 → DIVERGENT プロンプト注入」節追加
- MVP: 固定文言「これまでの試行はすべて失敗した。共通する誤った仮定は何か。その仮定自体に挑戦する修正を提示せよ」＋過去3試行の JSONL サマリを添付
- 根拠: B の履歴が必須。B 完了後に 1 回追記で導入可能

**F. Impact Analysis（Green/Amber/Gray 表出力）**
- 統合先: 新規スキル `/spec-impact-analyze`、または既存 `spec-status` 拡張
- MVP: E のフロントマターを走査し、要件変更差分に対して下流ファイルを3帯域に分類した表を出力（初期は **警告のみ、承認ゲートにしない**）
- 根拠: E が揃えば機械的に実装可能

### Tier 3 — 長期・見送り候補

**I. Harness-as-Code 自己検証** — E/F 成熟後、`_Requirements` タグと requirements.md / test-design.md の三者突合を `/spec-verify` として実装
**D. モデル/モード昇格** — 現状のコスト予測性（test-run: Sonnet / review: Opus 固定）と衝突。B/C で代替可能なため **見送り**
**H. 構造地図** — Wave 1 設計と `_Leverage` が実質代替。**見送り**

## 相乗効果

- **A × B × C** は一体のパイプライン: A で診断を構造化 → B で履歴蓄積 → C で仮説転換。単独導入より合計効果が大きい
- **E × F × I** は一体のパイプライン: E の宣言がなければ F/I は動かない。E を3テンプレに先行投入する価値が高い
- **G** は両系統の合流点: A の診断タグ、F の Amber 判定、いずれも `failure_category` を機械可読キーとして使う

## リスク管理

| リスク | 対策 |
|-------|------|
| プロンプト肥大化 | A/C の追加文言を合計300 tokens 以内に圧縮。`failure-taxonomy.md` はルール参照で本文は短く |
| 承認ループ増加 | F は初期「警告のみ、承認ゲートにしない」運用で慣らす |
| 既存 Anti-Bias Protocol との重複感 | A は「失敗時の根本原因明文化」、Anti-Bias は「成功時の観察ログ」と目的が異なる旨を両ドキュメントに注記 |
| MCP 側変更の波及 | B は当初フラット JSONL で PoC、成熟後に StateManager へ昇格 |

## Critical Files（実装フェーズで触る予定）

- `/home/arimakouyou/github/spec-workflow-mcp/.claude-plugin/agents/parallel-worker.md`
- `/home/arimakouyou/github/spec-workflow-mcp/.claude-plugin/agents/review-worker.md`
- `/home/arimakouyou/github/spec-workflow-mcp/.claude-plugin/skills/spec-impl-test-run/SKILL.md`
- `/home/arimakouyou/github/spec-workflow-mcp/.claude-plugin/rules/failure-taxonomy.md`（新規）
- `/home/arimakouyou/github/spec-workflow-mcp/src/markdown/templates/design-template.md`
- `/home/arimakouyou/github/spec-workflow-mcp/src/markdown/templates/test-design-template.md`
- `/home/arimakouyou/github/spec-workflow-mcp/src/markdown/templates/tasks-template.md`

## 再利用する既存仕組み

- `parallel-worker.md:133-144` の Retry Policy 表 → A の診断セクションをここに挿入
- `review-worker.md:71-78` Anti-Bias Protocol → A と役割分担を明記
- `review-worker.md:159-165` Severity Classification（Minor/Moderate/Critical）→ G の `failure_category` とマッピング
- `spec-design.md` の Wave 1/2 → E の `depends_on` が Wave 順を形式化する自然な発展系
- `feedback-loop.md`（`.claude-plugin/rules/`）→ DIVERGENT で得られた「誤った仮定」を know-how へ昇格する導線として活用可能
- `tasks-template.md:10-33` の `_DependsOn` / `_Leverage` / `_Requirements` → E の仕様書間依存と直交。併存

## 検証（実装フェーズで行う想定）

1. **単体レベル**: A/G を parallel-worker に組み込んだ後、既存の spec（例: 直近 PR #32 相当）を1本走らせ、リトライ時の診断出力が構造化されているか目視確認
2. **相乗レベル**: A+B+C まで揃えた時点で、意図的に失敗させるテストタスクを用意し、DIVERGENT が3回目リトライで発動するかを確認
3. **仕様書間**: E を3テンプレに入れた後、requirements.md を1項目書き換え、`/spec-impact-analyze`（F）が Green/Amber/Gray 表を出力するか確認
4. **回帰**: 既存の TDD サイクル（RED/GREEN/REFACTOR）と Severity Classification が壊れていないことを、`.claude-plugin/skills/spec-implement/` の手順で1本完走させて確認

## 推奨着手順（ロードマップ）

1. **Week 1**: G（`failure-taxonomy.md` 新規 + 3スキルへの `failure_category` 追加）→ A（診断3視点を parallel-worker/review-worker に追記）→ E（3テンプレのフロントマターに `depends_on` 追加）
2. **Week 2-3**: B（JSONL append-only ログ）→ C（DIVERGENT プロンプト、B 完了後）
3. **Week 4+**: F（`/spec-impact-analyze` 新規スキル、E の走査）
4. **以降**: I（`/spec-verify` 三者突合）。D/H は採用見送り、必要性が再検証されたら再考
