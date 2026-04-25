# Phase 3 #9: 3 ロール構成集約 — 進捗ドキュメント

> 元計画: `tmp/plugin-redesign.md` 第 3 段階 #9 「8 エージェント → 3 ロール (Orchestrator / Implementer / Reviewer) 集約」
> ブランチ: `refactor/plugin-redesign-phase-a`
> 最終更新: 2026-04-25
> **Status: CLOSED**（partial collapse + structural quality preservation）

## クロージャサマリ (2026-04-25)

agents 数: **10 → 7**（削減 3、統合 2）

| 操作 | 旧 | 新 / 備考 |
|------|----|-----------|
| 削除 | code-simplifier | review-worker の Anti-Bias + auto-fix で機能カバー（α） |
| 統合 | integ-test-worker (Rust) + integ-test-dotnet-worker (.NET) | integ-test-worker（Language 引数で分岐、δ partial） |
| 統合 | integ-test-auditor (Rust) + integ-test-dotnet-auditor (.NET) | integ-test-auditor（Language 引数で分岐、read-only L3 維持、γ partial） |
| 維持 | parallel-worker | TDD core（ε skip） |
| 維持 | wave-harness-worker | parallel framework 用、責務が異質（ε skip） |
| 維持 | unit-test-engineer | UT 補完（δ remainder skip、認知的分離維持） |
| 維持 | frontend-test-engineer | Leptos フロントテスト（δ remainder skip、認知的分離維持） |
| 維持・拡張 | review-worker | コードレビュー + commit + Phase Review 多角観点（β/β-followup） |

### plan-redesign 5.1 との対応関係

- 「**3 ロール思想**」(Orchestrator / Implementer / Reviewer) は実装した:
  - **Orchestrator** = `spec-implement` skill（agent ではなく skill 化）
  - **Implementer** = parallel-worker (TDD core) + 補完系 agent 群
  - **Reviewer** = review-worker（Phase Review 単発呼び出し統合済み）
- 「**3 ファイルに物理集約**」は意図的に採用しない:
  - 認知的分離 (D)、read-only L3 (A)、異質 protocol (B) は**構造的保証**として維持
  - 数の削減ではなく**責務の同一性**に基づく統合のみ採用（γ/δ の Language 引数 1 本化）

## 完了条件 (Definition of Done) — 達成判定

- [x] 「3 ロール思想」での再構成（Orchestrator/Implementer/Reviewer 役の明確化）
- [x] 旧構造の物理的削減: 10 → 7 agents（3 削減）
- [x] phase-review-team 5 並列の review-worker 単発呼び出し化（β）
- [x] code-simplifier の機能を review-worker Anti-Bias で代替（α）
- [x] integration test 系の言語間重複削除（γ + δ partial）
- [x] vitest pass（203 passed / 2 skipped）を全 sub で維持
- [x] rumdl 新規違反 0 を全 sub で維持
- [x] 構造的保証（read-only L3 / 認知的分離 / 異質 protocol）の維持

## 最終 agents 構成 (7 個 / 2026-04-25)

| ファイル | model | 主な機能 | 統合状態 |
|---------|-------|--------|--------|
| parallel-worker.md | sonnet | TDD Red→Green→Refactor + 品質チェック | 維持（TDD core） |
| wave-harness-worker.md | sonnet | wave-harness 用、taskflow-worker.v3 JSON 返却 | 維持（ε skip） |
| unit-test-engineer.md | sonnet | UT 補完、Design by Contract、Rust + C#/.NET | 維持（δ remainder skip） |
| frontend-test-engineer.md | sonnet | Leptos フロントテスト、ロジック抽出 | 維持（δ remainder skip） |
| integ-test-worker.md | sonnet | Rust + .NET 統合テスト実装（Language 引数） | δ partial で 1 本化 |
| integ-test-auditor.md | opus | Rust + .NET 統合テスト品質ゲート（Language 引数、read-only） | γ partial で 1 本化 |
| review-worker.md | opus | コードレビュー + commit、Phase Review は CVE/多角観点も担う | 拡張（β/β-followup） |

## 設計ブロッカーと最終判断結果

### A. tools 権限衝突 — auditor の read-only 保証

- `integ-test-auditor` 系: `Write/Edit/Bash` を**意図的に持たない**（"Write No Code, Only Evaluate" / L3 強制）
- `review-worker`: `Write/Edit/Bash` 完備（commit + auto-fix）
- review-worker に統合すると read-only 保証が L2（自己抑制）に降格
- **判断結果**: (ii) **γ partial** を採用。auditor 2 種を Language 引数で 1 個に統合、read-only tools 維持。review-worker への統合は見送り（L3 強制を構造的に保つ）

### B. wave-harness の返却スキーマ衝突

- `wave-harness-worker`: `taskflow-worker.v3` JSON 返却（schema_version, status, checks, …）
- `parallel-worker`: 自然文 completion report（`- status: completed` 形式）
- 加えて、起動 protocol（work_item_id / session_id / attempt / retry_mode）/ git 責務 / retry mental model / whiteboard 前提が**全て異なる**
- **判断結果**: (II) **ε skip** を採用。wave-harness-worker は別 agent のまま正式維持。
  理由:
  1. parallel-worker と wave-harness-worker は 90% 同一ではない（γ/δ と性質が違う）
  2. 統合すると caller の誤用リスクが増える（mode 別 protocol を 1 prompt に並べる弊害）
  3. agents 7→6 の削減価値 < 統合コスト + 誤用リスク
  4. plan #9 の意図は「3 ロール思想で再構成」であって「3 ファイルに物理集約」ではないと解釈
- 関連: (III) 「共通部分を `.claude-plugin/rules/` に切り出す」案は副作用（他 agent への意図せぬ影響）と確実に読まれない懸念から不採用

### C. 第 3 段階の作業量

- plan-redesign.md 8 節: 「第 3 段階: 2-3 週間」
- **判断結果**: 段階分割（α / β / γ partial / δ partial / ε skip）で対応。3 セッション内でクロージャ達成。

### D. δ の認知的分離降格

- 現状 Step 4 (parallel-worker) と Step 5 (test engineer) は別 agent process。「実装した本人とは違う agent がテスト十分性を見直す」認知的分離自体が品質保証メカニズム
- test engineer 2 種を implementer に統合すると、Step 5 が同 agent type になり、認知的分離が**構造的保証 → 手続き的注意事項**に降格（γ の A と同型）
- **判断結果**: (ii) **δ partial** を採用。integ-test 2 種のみ統合し、test engineer 2 種は維持。
- **δ remainder（test engineer 統合）の追加判断（ε と同時、2026-04-25）**: ε と同じ線（構造的質を優先）で **skip** を正式採用。test engineer 2 種は **plan 5.1 から意図的に逸脱して別 agent のまま維持**。fresh review の構造的保証を残す。

## 段階分割と最終 Status

| Sub | 内容 | 最終 Status | 関連コミット |
|-----|------|------------|-------------|
| α | code-simplifier 削除 | DONE | `c36e9ba` |
| β | phase-review-team 廃止 → review-worker 単発呼び出し | DONE | `ccabf85` |
| β-followup | review-worker.md の Phase Review Context 拡張 | DONE | `a92dd01` |
| γ partial | integ-test-auditor 系を Language 引数で 1 本化（read-only L3 維持） | DONE | `888f6d4` |
| δ partial | integ-test-worker 系を Language 引数で 1 本化 | DONE | `2c31cda` |
| δ remainder | test engineer 2 種統合 | **SKIP**（plan 5.1 から意図的逸脱、認知的分離維持） |
| ε | wave-harness-worker 統合 | **SKIP**（plan 5.1 から意図的逸脱、ブロッカー B 判断結果） |

## 完了履歴

- **α (2026-04-25)**: `code-simplifier.md` 削除 / spec-implement SKILL.md の Step 5.5 セクション削除 / review-worker.md Anti-Bias の「3段階」→「2段階」更新 / 関連 prompt から simplify_result 等を撤去。vitest 203 passed、rumdl 153→146（新規違反 0）
- **β (2026-04-25)**: `phase-review-team` Skill 削除 / spec-implement SKILL.md 3.5.2 (Expert Team Review 5 並列) を 3.5.2 review-worker 単発呼び出しに統合（CVE 監査 + 統合検証 + 多角レビューを 1 回の review-worker prompt に集約）/ resource-aware-parallelism から軽量エージェントセクション全削除（唯一の利用者だった phase-review-team が消えたため YAGNI 原則で）。vitest 203 passed、rumdl 146→105（新規違反 0）
- **β-followup (2026-04-25)**: review-worker.md の Phase Review Context 節に CVE 監査結果評価サブセクションと多角観点レビューサブセクションを追加（advisor 指摘により agent 定義を spec-implement prompt の責務拡張に整合）。完了レポートに `cve-audit` キー追加。vitest 203 passed、rumdl 新規違反 0
- **δ partial (2026-04-25)**: `integ-test-dotnet-worker` 削除 / `integ-test-worker` を `Language: rust|dotnet` 引数で 1 個に統合（共通手順 + 言語別セクション構成）/ integration-test SKILL.md と integration-test-dotnet SKILL.md の Agent 呼び出しに `Language:` 引数を明示。agents 9 → 8。test engineer 2 種は維持（認知的分離保持、ブロッカー D 判断結果）。vitest 203 passed、rumdl 新規違反 0
- **γ partial (2026-04-25)**: `integ-test-dotnet-auditor` 削除 / `integ-test-auditor` を `Language: rust|dotnet` 引数で 1 個に統合（read-only tools 維持、Language 別 startup-load ファイル + E 項目 + Determinism specifics）/ integration-test SKILL.md と integration-test-dotnet SKILL.md の Pentagon 起動 prompt に `Language:` 引数を明示。agents 8 → 7。review-worker への統合は見送り（ブロッカー A 判断結果、L3 read-only 保証を構造的に維持）。vitest 203 passed、rumdl 70→69（新規違反 0、減少 1）
- **closure (2026-04-25)**: ε と δ remainder を **skip** として正式記録。wave-harness-worker と test engineer 2 種は plan 5.1 から意図的に逸脱して別 agent のまま維持（ブロッカー B / D 判断結果）。Phase 3 #9 をクローズし、本ドキュメントを履歴として保持。

## クローズ後の方針

本フェーズは 2026-04-25 にクローズしました。

- 将来 wave-harness-worker / test engineer 2 種の追加 collapse が必要になった場合は、新規 plan ファイル（`.claude/_docs/plans/<name>.md`）を起こすこと
- 本ドキュメントは判断履歴として保持し、上書きしない
- 構造的保証（read-only L3 / 認知的分離 / 異質 protocol）を覆す決定は、必ず advisor 経由で再評価すること

## Appendix A: 着手時点の影響ファイル一覧（2026-04-25 時点 grep 結果、参考）

旧 agent 名を参照する `.claude-plugin/` 配下のファイル（着手時点）:

```
.claude-plugin/agents/integ-test-dotnet-auditor.md  ← γ で削除
.claude-plugin/agents/frontend-test-engineer.md     ← 維持
.claude-plugin/agents/integ-test-worker.md          ← δ で書き換え (Lang 引数)
.claude-plugin/agents/code-simplifier.md            ← α で削除
.claude-plugin/agents/review-worker.md              ← β/β-followup で拡張
.claude-plugin/agents/integ-test-dotnet-worker.md   ← δ で削除
.claude-plugin/agents/integ-test-auditor.md         ← γ で書き換え (Lang 引数)
.claude-plugin/agents/parallel-worker.md            ← 維持
.claude-plugin/agents/unit-test-engineer.md         ← 維持
.claude-plugin/agents/wave-harness-worker.md        ← 維持 (ε skip)
.claude-plugin/rules/* (8 files)                    ← 維持（言及のみ）
.claude-plugin/skills/integration-test/*            ← 統合呼び出し更新
.claude-plugin/skills/integration-test-dotnet/*     ← 統合呼び出し更新
.claude-plugin/skills/spec-implement/SKILL.md       ← α/β/β-followup で大幅更新
.claude-plugin/skills/phase-review-team/SKILL.md    ← β で削除
.claude-plugin/skills/resource-aware-parallelism/*  ← β で軽量エージェントセクション削除
.claude-plugin/skills/{api-validation, cargo-mutants, create-pr, doc-freshness,
                       dotnet-build-cache, feedback-loop, handle-pr-comments,
                       rust-build-cache, setup-ci, spec-e2e-implement,
                       spec-impl-test-write, spec-tasks}                 ← 維持（言及のみ）
```

## Appendix B: spec-implement SKILL.md の subagent_type 呼び出し位置（着手時点、参考）

行番号は 2026-04-25 時点の着手時。各 sub 完了後に行番号は変動。

```
L8   parallel-worker / review-worker（フロー説明）
L201 parallel-worker（Step 4）
L225 parallel-worker / review-worker（multi-task wave）
L412 review-worker（PhaseReview Step 3.5.3 / β で 3.5.2 に番号繰り上げ）
L431 spec-workflow-mcp:review-worker（subagent_type）
L488 parallel-worker（_TDDSkip フロー）
L489 review-worker（5.5 / 6 飛ばし方 / α で 5.5 削除）
L513-532 parallel-worker（Step 4 本体）
L621-644 frontend-test-engineer / unit-test-engineer（Step 5）
L676-685 code-simplifier（Step 5.5）← α で削除済み
L709-720 review-worker（Step 6）
L783-789 parallel-worker（rework 差し戻し）
```
