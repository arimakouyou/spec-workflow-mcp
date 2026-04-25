# Phase 3 #9: 3 ロール構成集約 — 進捗ドキュメント

> 元計画: `tmp/plugin-redesign.md` 第 3 段階 #9 「8 エージェント → 3 ロール (Orchestrator / Implementer / Reviewer) 集約」
> ブランチ: `refactor/plugin-redesign-phase-a`
> 最終更新: 2026-04-25

## 完了条件 (Definition of Done)

- `.claude-plugin/agents/` が `implementer.md` と `reviewer.md` の 2 ファイルのみ（Orchestrator は spec-implement skill が担当）
- spec-implement / integration-test / phase-review-team 等の `subagent_type` 参照が新名に置換
- vitest が pass（既存 203 件）
- rumdl が新規違反なし
- 削除した agent の機能が新 agent でカバーされている（read-only 保証など特殊ケースは ブロッカー A の判断による）

## 現状エージェント (10 個 / 2026-04-25)

| ファイル | model | 移行先 | 主な機能 |
|---------|-------|-------|--------|
| parallel-worker.md | sonnet | implementer (TDD core) | TDD Red→Green→Refactor + 品質チェック |
| wave-harness-worker.md | sonnet | implementer (mode: wave) | wave-harness 用、JSON schema 返却 |
| unit-test-engineer.md | sonnet | implementer (mode: unit-test-suppl) | UT 補完、Design by Contract |
| frontend-test-engineer.md | sonnet | implementer (mode: frontend-test-suppl) | Leptos フロントテスト補完 |
| integ-test-worker.md | sonnet | implementer (mode: integ-rust) | Rust 統合テスト実装 |
| integ-test-dotnet-worker.md | sonnet | implementer (mode: integ-dotnet) | .NET 統合テスト実装 |
| review-worker.md | opus | reviewer (mode: code) | コードレビュー + commit |
| integ-test-auditor.md | opus | reviewer (mode: integ-rust audit) | Rust 統合テスト品質ゲート (read-only) |
| integ-test-dotnet-auditor.md | opus | reviewer (mode: integ-dotnet audit) | .NET 統合テスト品質ゲート (read-only) |
| code-simplifier.md | sonnet | (削除) | review-worker の Anti-Bias で機能カバー済 |

## 設計ブロッカー（advisor 指摘）

### D. δ の認知的分離降格（advisor 指摘）

- 現状 Step 4 (parallel-worker) と Step 5 (test engineer) は別 agent process — 「実装した本人とは違う agent がテスト十分性を見直す」認知的分離自体が品質保証メカニズム
- test engineer 2 種を implementer に統合すると、Step 5 が同 agent type になり、認知的分離が**構造的保証 → 手続き的注意事項**に降格（γ の A と同型）
- **判断結果（2026-04-25）**: (ii) **δ partial** を採用。integ-test 2 種（rust + dotnet、90% 同一）のみ統合。test engineer 2 種は維持し fresh review の構造的保証を残す
- 将来 ε で wave-harness 統合後に test engineer 統合の必要性を再評価可能

### A. tools 権限衝突 — auditor の read-only 保証

- `integ-test-auditor` / `integ-test-dotnet-auditor`: `Write/Edit/Bash` を**意図的に持たない**（"Write No Code, Only Evaluate" / L3 強制）
- `review-worker`: `Write/Edit/Bash` 完備（commit + auto-fix する）
- 統合すると read-only 保証が L2（自己抑制）に降格する
- **判断ポイント**: γ 着手時に必要。選択肢:
  - (i) 降格を許容して reviewer に統合（plan 5.1 通り）
  - (ii) auditor を別 agent として残す（plan 逸脱、安全）

### B. wave-harness の返却スキーマ衝突

- `wave-harness-worker`: `taskflow-worker.v3` JSON 返却（`schema_version`, `status`, `checks`, …）
- `parallel-worker`: 自然文 completion report（`- status: completed` 形式）
- implementer に統合すると呼び出し側が mode で分岐必要
- **判断ポイント**: ε 着手時に必要。schema 互換維持 or implementer mode 引数で分岐。

### C. 第 3 段階の作業量

- plan-redesign.md 8 節: 「第 3 段階: 2-3 週間」
- 1 セッションで δ/ε まで一気通貫は過大 → 段階分割が前提

## 段階分割と DoD

| Sub | 内容 | 影響範囲 | DoD | Status |
|-----|------|---------|-----|-------|
| α | code-simplifier 削除 | spec-implement Step 5.5 削除のみ | `code-simplifier.md` 削除 / Step 5.5 削除 / 5.5 を参照する記述全削除 / vitest pass / rumdl 新規違反 0 | DONE |
| β | phase-review-team 廃止 | `phase-review-team/` 削除 + spec-implement 3.5.x 書き換え | skill 削除 / Phase 末尾は review-worker 単発呼び出しに置換 / vitest pass | DONE |
| γ | integ-test-auditor 系 → reviewer 統合 | 2 agent 削除 + integration-test/integration-test-dotnet SKILL.md 更新 | ブロッカー A をユーザー判断後に着手 / reviewer に integration audit mode 追加 | BLOCKED (要 A 判断) |
| δ | test engineer 3 種 → implementer 統合 | spec-implement Step 4-5 + tdd-skills + 各参照箇所 | implementer.md に mode 引数 / 5 agent 削除 / spec-implement 大量更新 | PARTIAL DONE（integ-test 2 種のみ統合、test engineer 2 種は維持） |
| ε | wave-harness-worker 統合 | resource-aware-parallelism + wave-harness 呼び出し元 | ブロッカー B 解決後 / implementer に mode: wave 追加 | BLOCKED (要 B 判断) |

## 再開手順（次セッション着手時）

1. 本ドキュメントの **Status 列**で完了済 sub と未着手 sub を確認
2. 未着手の最初の sub に着手（依存順: α → β → γ/δ → ε）
3. `ls .claude-plugin/agents/` で物理状態を確認（agent 数で進捗が分かる）
4. `grep -nE "<旧 agent 名>" .claude-plugin/skills/spec-implement/SKILL.md` で残参照を確認
5. ブロッカー A/B のユーザー判断が必要な sub かを上表で確認
6. vitest と rumdl を最後に必ず通す

## 完了履歴

（各 sub 完了時にコミット hash と要点を追記）

- **α (2026-04-25)**: `code-simplifier.md` 削除 / spec-implement SKILL.md の Step 5.5 セクション削除 / review-worker.md Anti-Bias の「3段階」→「2段階」更新 / 関連 prompt から simplify_result 等を撤去。vitest 203 passed、rumdl 153→146 (新規違反 0)
- **β (2026-04-25)**: `phase-review-team` Skill 削除 / spec-implement SKILL.md 3.5.2 (Expert Team Review 5 並列) を 3.5.2 review-worker 単発呼び出しに統合（CVE 監査 + 統合検証 + 多角レビューを 1 回の review-worker prompt に集約）/ resource-aware-parallelism から軽量エージェントセクション全削除（唯一の利用者だった phase-review-team が消えたため YAGNI 原則で）。vitest 203 passed、rumdl 146→105（新規違反 0）
- **β-followup (2026-04-25)**: review-worker.md の Phase Review Context 節に CVE 監査結果評価サブセクションと多角観点レビューサブセクションを追加（advisor 指摘により agent 定義を spec-implement prompt の責務拡張に整合）。完了レポートに `cve-audit` キー追加。vitest 203 passed、rumdl 新規違反 0
- **δ partial (2026-04-25)**: `integ-test-dotnet-worker` 削除 / `integ-test-worker` を `Language: rust|dotnet` 引数で 1 個に統合（共通手順 + 言語別セクション構成）/ integration-test SKILL.md と integration-test-dotnet SKILL.md の Agent 呼び出しに `Language:` 引数を明示。agents 9 → 8。test engineer 2 種は維持（認知的分離保持、ブロッカー D 判断結果）。vitest 203 passed、rumdl 新規違反 0

## Appendix A: 影響ファイル一覧（2026-04-25 時点 grep 結果）

旧 agent 名（parallel-worker / wave-harness-worker / unit-test-engineer / frontend-test-engineer / integ-test-worker / integ-test-dotnet-worker / review-worker / integ-test-auditor / integ-test-dotnet-auditor / code-simplifier）を参照する `.claude-plugin/` 配下のファイル:

```
.claude-plugin/agents/integ-test-dotnet-auditor.md
.claude-plugin/agents/frontend-test-engineer.md
.claude-plugin/agents/integ-test-worker.md
.claude-plugin/agents/code-simplifier.md
.claude-plugin/agents/review-worker.md
.claude-plugin/agents/integ-test-dotnet-worker.md
.claude-plugin/agents/integ-test-auditor.md
.claude-plugin/agents/parallel-worker.md
.claude-plugin/agents/unit-test-engineer.md
.claude-plugin/agents/wave-harness-worker.md
.claude-plugin/rules/design-conformance.md
.claude-plugin/rules/spec-workflow-enforcement.md
.claude-plugin/rules/design-principles.md
.claude-plugin/rules/quality-checks.md
.claude-plugin/rules/enforcement-levels.md
.claude-plugin/rules/hybrid-inspection.md
.claude-plugin/rules/failure-taxonomy.md
.claude-plugin/rules/diagnostic-reasoning.md
.claude-plugin/rules/type-safety.md
.claude-plugin/skills/integration-test/references/parallel-execution.md
.claude-plugin/skills/spec-impl-test-write/SKILL.md
.claude-plugin/skills/spec-tasks/SKILL.md
.claude-plugin/skills/cargo-mutants/SKILL.md
.claude-plugin/skills/integration-test-dotnet/references/parallel-execution.md
.claude-plugin/skills/integration-test/SKILL.md
.claude-plugin/skills/resource-aware-parallelism/SKILL.md
.claude-plugin/skills/doc-freshness/SKILL.md
.claude-plugin/skills/api-validation/SKILL.md
.claude-plugin/skills/setup-ci/SKILL.md
.claude-plugin/skills/phase-review-team/SKILL.md
.claude-plugin/skills/spec-e2e-implement/SKILL.md
.claude-plugin/skills/spec-implement/SKILL.md
.claude-plugin/skills/feedback-loop/SKILL.md
.claude-plugin/skills/create-pr/SKILL.md
.claude-plugin/skills/integration-test-dotnet/SKILL.md
.claude-plugin/skills/rust-build-cache/SKILL.md
.claude-plugin/skills/handle-pr-comments/SKILL.md
.claude-plugin/skills/dotnet-build-cache/SKILL.md
```

合計 38 ファイル。本数は再開時の `grep -lr "<旧 agent 名>" .claude-plugin/` で再カウントすること。

## Appendix B: spec-implement SKILL.md の subagent_type 呼び出し位置

```
L8   parallel-worker / review-worker（フロー説明）
L201 parallel-worker（Step 4）
L225 parallel-worker / review-worker（multi-task wave）
L412 review-worker（PhaseReview Step 3.5.3）
L431 spec-workflow-mcp:review-worker（subagent_type）
L488 parallel-worker（_TDDSkip フロー）
L489 review-worker（5.5 / 6 飛ばし方）
L513-532 parallel-worker（Step 4 本体）
L621-644 frontend-test-engineer / unit-test-engineer（Step 5）
L676-685 code-simplifier（Step 5.5）← α で削除対象
L709-720 review-worker（Step 6）
L783-789 parallel-worker（rework 差し戻し）
```

行番号は 2026-04-25 時点。各 sub 着手時に再 grep して確認。
