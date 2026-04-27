# Test Taxonomy + ST 層導入 + Regression 統合 (J)

> マスター: `dapper-hardening-orchestrator.md` の根本原因 J
> Branch: `refactor/plugin-redesign-phase-a`
> Status: IN PROGRESS（J-3 完了済 e0d3279。残り J-1/J-2/J-4/J-5/J-6/J-7/J-8/J-9/J-10）
> 起票日: 2026-04-28

## 目的

`quality-checks.md` の Test Taxonomy（J-3 で確定）を spec-workflow 全体に適用し、ST 層を新設し、Regression を cross-cutting type として統合する。

## 修正対象（マスタープラン J-1〜J-10 から転記）

### J-1: IT 仕様を「backend HTTP API only」に厳格化

- [x] `spec-test-design/SKILL.md` Subagent B prompt 改訂（責務範囲明示、UI 検証 / DOM 操作禁止）
- [x] test-design-template.md `## Integration Test Specifications` セクション冒頭に責務範囲注記

### J-2: E2E 仕様を「user journey only」に厳格化

- [x] `spec-test-design/SKILL.md` Subagent C prompt 改訂（複数機能連鎖必須、単一機能テスト禁止）
- [x] test-design-template.md `## E2E Test Specifications` セクション冒頭に責務範囲注記

### J-3: `quality-checks.md` 新規「Test Taxonomy」セクション

- [x] `quality-checks.md` に Test Taxonomy セクション挿入済（commit e0d3279）

### J-4: spec-test-design Step B test layer boundary check

- [x] `spec-test-design/SKILL.md` Step B 新規 Check 15: TEST_LAYER_BOUNDARY（当初計画 Check 19 → 既存 Check が 14 までだったため Check 15 に番号調整）

### J-5: spec-tasks の IT/ST/E2E task 配置ルール改訂

- [x] `spec-tasks/SKILL.md` 3.6 を `### 3.6 IT / ST / E2E Test Tasks` に拡張
- [x] IT task: backend Phase 完了直後に配置（責務範囲: backend HTTP API only）
- [x] ST task: 対象機能 Phase 末尾（CT/IT 完了後、E2E より前。責務範囲: 単一機能 full-stack）
- [x] E2E task: 全 Phase 完了後の最終 Phase（責務範囲: user journey only）
- [x] 配置ルールの優先順序を明示

### J-6: spec-test-design に ST 仕様セクション追加

- [x] `spec-test-design/SKILL.md` 新規 Subagent E (ST spec deriver)
- [x] Section 5 (Integrate) で ST 出力も統合
- [x] test-design-template.md に `## System Test Specifications` セクション追加（ST-1 / ST-2 例）

### J-7: spec-tasks に ST task 配置ルール追加

- [x] `spec-tasks/SKILL.md` 3.6 で ST task の特例規約を記載（J-5 と統合実施）
- [x] `spec-tasks/SKILL.md` Step 7 新規 Check 20: ST_PLACEMENT
- [ ] 既存 task テンプレ 4.x に ST task 例示（必要時に追加、現状 _BugFix 例で代替）

### J-8: regression-test-policy を新 taxonomy に整合させる改訂

- [ ] `regression-test-policy/SKILL.md` 全面改訂
- [ ] 「Regression は層ではなく cross-cutting type」を明示
- [ ] RT1/RT2/RT3 を UT/CT/IT/ST/E2E すべての層に適用可能と再定義
- [ ] 命名規則の統一（各層で `regression_issue_NNN_*` 規格）

### J-9: `quality-checks.md` 新規 QC16: Regression Gate

- [ ] `quality-checks.md` に QC16 セクション追加
- [ ] PR / merge 時に全層 + regression marked テスト必須実行を CI gate 化
- [ ] `setup-ci/SKILL.md` 改訂で `regression_issue_*` 自動収集 step を追加

### J-10: spec-tasks に `_RegressionBugId` メタデータ強制

- [x] `spec-tasks/SKILL.md` Step 4 _Prompt template にバグ修正系 task の `_RegressionBugId:` フィールド追加 + 例示
- [x] `spec-tasks/SKILL.md` Step 7 新規 Check 21: REGRESSION_BUG_ID
- [ ] `parallel-worker/agent.md` バグ修正 mode に RT1 フロー実装（後続作業で対応、本 commit には含めない）

## 完了記録

| 日付 | sub-task | commit | 備考 |
|------|---------|--------|------|
| 2026-04-28 | J-3: Test Taxonomy セクション | e0d3279 | quality-checks.md に挿入。K-1/K-2/K-4 が参照する taxonomy 正規定義 |
| 2026-04-28 | J-1: IT 仕様 backend HTTP only 厳格化 | （これから commit）| spec-test-design Subagent B + test-design template 更新 |
| 2026-04-28 | J-2: E2E 仕様 user journey only 厳格化 | （これから commit）| spec-test-design Subagent C + test-design template 更新 |
| 2026-04-28 | J-4: Step B Check 15 (TEST_LAYER_BOUNDARY) | （これから commit）| 当初計画 Check 19 → 15 に番号調整（既存 14 まで） |
| 2026-04-28 | J-6: ST 仕様 + Subagent E 新設 | 717a641 | spec-test-design Subagent E + Section 5 Integrate + test-design template 追加 |
| 2026-04-28 | J-1: IT 仕様 backend HTTP only 厳格化 | 717a641 | spec-test-design Subagent B + test-design template 更新 |
| 2026-04-28 | J-2: E2E 仕様 user journey only 厳格化 | 717a641 | spec-test-design Subagent C + test-design template 更新 |
| 2026-04-28 | J-4: Step B Check 15 (TEST_LAYER_BOUNDARY) | 717a641 | 当初計画 Check 19 → 15 に番号調整（既存 14 まで） |
| 2026-04-28 | J-5: spec-tasks 3.6 IT/ST/E2E 配置ルール改訂 | （これから commit）| spec-tasks 3.6 を IT/ST/E2E Test Tasks に拡張、配置ルール優先順序明示 |
| 2026-04-28 | J-7: spec-tasks Step 7 Check 20 (ST_PLACEMENT) | （これから commit）| ST 仕様の task 化を強制 |
| 2026-04-28 | J-10: spec-tasks _BugFix + _RegressionBugId | （これから commit）| Step 4 metadata 説明 + Step 7 Check 21 + bugfix task 例示。parallel-worker 改訂は後続 |

## Check / Subagent 番号付け（実装で確定したもの）

**spec-tasks Step 7 Check** (既存 1-13 + 追加):
- 14: COMPOSITION_TASK (D, 未実装)
- 15: UI_OBSERVABILITY (D, 未実装)
- 16: FIXTURE_REALIZATION (D, 未実装)
- 17: PHASE_SMOKEABLE (E-2, 未実装)
- 18: SUCCESS_BEHAVIORAL_VERIFICATION (H-4, 未実装)
- 19: TESTFOCUS_NEGATIVE (I-1, 未実装)
- **20: ST_PLACEMENT (J-7, 本 commit)**
- **21: REGRESSION_BUG_ID (J-10, 本 commit)**

**spec-test-design Step B Check** (既存 1-14 + 追加):
- **15: TEST_LAYER_BOUNDARY (J-4, 717a641)** ← 当初 19 計画 → 15 に調整
- F (snapshot path / aria snapshot / complex state) は未実装、今後 16/17/18 を予定
- H-2 (UT/CT existence / CT integration verify) は未実装、今後 19/20 を予定
- C-2 (signature match) は未実装、今後 21 を予定

**spec-test-design Subagent**:
- A: UT (既存)
- B: IT (J-1 で改訂、backend HTTP only)
- C: E2E (J-2 で改訂、user journey only)
- D: CT spec deriver (H-2 で予約、H 実装後に有効化)
- E: ST spec deriver (J-6 で新設、717a641 で実装)

## 影響範囲

- `spec-test-design/SKILL.md` (Subagent B/C 改訂 + Subagent E 新設 + Section 5 + Step B Check 15)
- `test-design-template.md` (IT/E2E 注記 + ST セクション追加)
- 既存 spec の retrofit: 既存 IT 仕様で「server fn 経由」を含むものは CT/ST に再分類が必要（spec-verify legacy-tolerant）

## 関連

- マスタープラン: `dapper-hardening-orchestrator.md` 根本原因 J
- 関連 sub-plan: `upstream-spec-content-expansion.md` (K)
- 前提: J-3 で確定した Test Taxonomy セクション（quality-checks.md）
