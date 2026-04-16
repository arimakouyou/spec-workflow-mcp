# 診断推論パターン（Diagnostic Reasoning）のワークフロー統合

## Context

Zenn 記事「CoDD活用ガイド #5」の知見を本プラグインに統合する。記事の要点:
- SWE-bench 73問で100%成功率を達成
- AI呼び出しの59%が無駄なリトライだった → 「まず診断しろ」の1行追加で排除
- 核心は3つ: **(1) 修正前の必須診断** / **(2) 試行履歴の引継（Session State）** / **(3) 同じ手の明示的禁止**

現在のワークフローではリトライ機構（parallel-worker: GREEN 3回等）は存在するが、各リトライがステートレスで、診断→記録→差別化のサイクルが欠けている。

## 設計方針

### 2つのリトライ種類に応じた機構

| 種類 | 例 | Session State の保持方法 |
|------|-----|------------------------|
| **エージェント内リトライ** | GREEN phase 3回、clippy 3回 | エージェントがワークツリー内の `diagnosis.md` に各試行を追記。会話コンパクション耐性＋知見の保存を兼ねる |
| **エージェント間リトライ** | rework cycle 3回、wave-harness retry | オーケストレーターが `diagnostic_history` テキストブロック（DR2 形式の markdown 文字列）を蓄積し、次回プロンプトに注入。加えて `diagnosis.md` にも記録 |

### diagnosis.md ファイル

各タスクのワークツリーに `diagnosis.md` を作成し、全リトライの診断情報を永続化する。

**配置**: `{worktree_path}/diagnosis.md`（state.md と同じディレクトリ）
**目的**: (1) コンパクション耐性 (2) 知見の蓄積・後続分析 (3) rework cycle で orchestrator が参照可能
**ライフサイクル**: タスク開始時に作成 → 各リトライ試行で追記 → タスク完了後もワークツリーに残存

```markdown
# Diagnostic Session: {task-id}

## GREEN Phase

### Attempt 1/3
- **Root cause**: handler returns raw String error instead of AppError
- **Responsible**: src/handlers/users.rs:42
- **Expected behavior**: All handlers return Result<Json<T>, AppError> per design.md §3.2
- **Approach**: Implement From<String> for AppError
- **Result**: FAIL — cargo test: AppError::from() not invoked because handler uses .unwrap()

### Attempt 2/3
- **Root cause**: handler uses .unwrap() which panics instead of propagating error via ?
- **Responsible**: src/handlers/users.rs:45 (.unwrap() call)
- **Expected behavior**: Use ? operator to propagate errors through AppError
- **Approach**: Replace .unwrap() with ? and ensure return type is Result
- **Result**: PASS

## Quality Checks

### clippy Attempt 1/3
- **Root cause**: unused import after refactoring
- **Responsible**: src/handlers/users.rs:3
- **Approach**: Remove unused import
- **Result**: PASS

## Rework Cycle

### Rework 1/3
- **Findings**: B:design — missing input validation on email field
- **Root cause**: create_user handler accepts raw string without validation
- **Responsible**: src/handlers/users.rs:38
- **Approach**: Add email validation with validator crate
- **Result**: PASS (review_action: commit)
```

### ルール vs スキル → ルール（`always_apply: true`）

- ルールは自動読込されスキップ不可。全リトライシナリオに一貫適用できる
- 各エージェントファイルにルールの適用方法を短くコンテキスト化

## 変更ファイル一覧

### 1. 新規: `.claude-plugin/rules/diagnostic-reasoning.md`（DR1〜DR5）

**目的**: 全エージェント共通の診断推論プロトコル

```
always_apply: true
```

| ID | 名称 | 内容 |
|----|------|------|
| DR1 | Mandatory Diagnosis Before Fix | 修正コード記述前に `diagnosis.md` に DR2 形式の Attempt エントリ（根本原因・責任箇所・期待動作・アプローチ）を追記 |
| DR2 | Session State Persistence | 各試行を `diagnosis.md` ファイルに構造化エントリとして永続化（attempt / root_cause / responsible / expected / approach / result）。エージェント内・間の両方で参照可能 |
| DR3 | Prior Attempts Review | attempt > 1 の場合、過去の全エントリをレビューし、異なる診断を特定 |
| DR4 | Non-Repetition Constraint | 失敗したアプローチと同じ手法の禁止。同じ根本原因に到達した場合は深掘り or エスカレーション |
| DR5 | Diagnosis Quality Gate | 不十分な診断の定義（エラー再述のみ / 同一根本原因 / ファイル名なし）。最終試行前に advisor() で検証 |

推定サイズ: 約50行

### 2. 修正: `.claude-plugin/agents/parallel-worker.md`

**変更箇所**: Advisor Usage セクション（L22-29）の後、Leptos Frontend Task Detection セクション（L33）の前に新セクション追加

**追加内容**: "Diagnostic Reasoning Protocol" セクション
- `diagnosis.md` ファイルの作成・管理手順
  - タスク開始時（Step 2 / 2.5）に `{worktree_path}/diagnosis.md` を作成
  - 各リトライ試行の前に `diagnosis.md` を Read して過去の試行を確認
  - 診断を記述し、`diagnosis.md` に Edit で追記してから修正に着手
- エージェント内リトライ時の診断フォーマット（各 attempt ごとに5項目: Root cause / Responsible / Expected behavior / Approach / Result）
- rework cycle 時は orchestrator が渡す `diagnostic_history` に加え、自身も `diagnosis.md` の "Rework Cycle" セクションに追記
- advisor 連携（DR5: 最終試行前の診断検証）

**追加変更**: state.md Update Patterns テーブル（L303-308）に1行追加
```
| After diagnosis.md created | State: note diagnosis.md path for compaction recovery |
```

### 3. 修正: `.claude-plugin/skills/spec-implement/SKILL.md`

**変更箇所**: rework プロンプトテンプレート（L720-744）

**変更内容**:
- プロンプトに `diagnostic_history` パラメータを追加
- "DO NOT repeat failed approaches" の明示的指示を追加
- "Apply diagnostic-reasoning.md DR1-DR5" の指示を追加
- 最終試行（3/3）で advisor() 呼び出しの指示を追加

**追加変更**: L747 付近にオーケストレーターが従うべき具体的な手順を追加（LLM が SKILL.md を読んで実行するため、抽象的な説明ではなく step-by-step で記述）:

```markdown
**Diagnostic history accumulation (orchestrator responsibility)**:

The orchestrator maintains a text block called `diagnostic_history` for each task's rework cycle. Follow these steps:

1. **Before the first rework**: Initialize `diagnostic_history` as empty string
2. **After each rework attempt**: Extract from parallel-worker's completion report:
   - The `diagnosis` summary field (root cause, responsible location, approach) — or the latest `### Attempt {N}/3` entry under `## Rework Cycle` in `diagnosis.md` if the summary is absent
   - The quality check results (pass/fail)
3. **Append to diagnostic_history in DR2 format** (fields come from the worker's completion report):
   ```
   ### Attempt {N}
   - **Root cause**: {diagnosis.root_cause from worker's report}
   - **Responsible**: {diagnosis.responsible_files joined, or "(not reported)"}
   - **Expected behavior**: {if available, otherwise "(not reported)"}
   - **Approach**: {diagnosis.approach — what the worker changed}
   - **Result**: {review-worker's verdict — commit/rework/escalate + specific findings}
   ```
4. **Pass the accumulated diagnostic_history** in the next rework prompt (see template above)

Example after 2 failed rework attempts:
```
### Attempt 1
- **Root cause**: UserRepo.create() returns raw diesel::Error, not AppError
- **Responsible**: src/repos/user.rs:42
- **Expected behavior**: All repository methods return Result<T, AppError> per design.md §3.2
- **Approach**: Added From<diesel::Error> impl for AppError
- **Result**: rework — B:design: return type still uses String not AppError in update() and delete()

### Attempt 2
- **Root cause**: 3 repository methods (create, update, delete) all return String errors; attempt 1 only fixed create
- **Responsible**: src/repos/user.rs:42, src/repos/user.rs:58, src/repos/user.rs:73
- **Expected behavior**: All 3 methods return Result<T, AppError> consistently
- **Approach**: Converted all 3 methods to return AppError, added error mapping in handler layer
- **Result**: {pending — will be filled after review}
```
```

### 4. 修正: `.claude-plugin/agents/wave-harness-worker.md`

**変更箇所**:

**(a) Input セクション（L21-31）**
- `diagnostic_history` (optional) パラメータを追加（DR2 フォーマットの markdown テキストブロック — 文字列）
- `previous_error` は後方互換のため残す

**(b) Advisor Usage セクション（L42-46）**
- retry 時の bullet を更新: `previous_error` 分析 → DR1 診断記述 + `diagnostic_history` 参照 + advisor 検証

**(c) Procedure セクション（L77-87）**
- Step 3 と Step 4 の間に Step 3.5 を挿入:
  - `retry_mode: true` の場合、`{worktree_path}/diagnosis.md` を Read して過去の試行を確認
  - DR1 診断を記述し、`diagnosis.md` に追記
  - アプローチ差別化確認 → 最終試行時 advisor 呼び出し
- Step 1 の直後に: `attempt == 1` の場合、`{worktree_path}/diagnosis.md` を初期作成

**(d) Output schema v3（L89-109）**
- `diagnosis` フィールド（optional）を追加: root_cause / responsible_files / approach

### 5. 修正: `.claude-plugin/rules/INDEX.md`

- ID 体系テーブル（L7-22）に `diagnostic-reasoning.md | DR1〜DR5 | 5 | 診断推論プロトコル` を追加
- 合計を 99 → 104 に更新
- ワークフロー・プロセスルールテーブル（L57-66）に追加
- 早見表の Rust / C# 両テーブルに「テスト失敗修正 | DR1-DR5」行を追加

## 変更しないもの

- **リトライ上限**: 既存の上限（GREEN: 3, RED: 2, REFACTOR: 2, rework: 3）は変更しない。診断推論は既存上限内の成功率を改善する
- **フェーズ構造**: RED-GREEN-REFACTOR サイクルは不変。診断はリトライループ内に追加
- **review-worker.md**: レビュアー側は変更不要。既に構造化 findings を出力している
- **feedback-loop.md**: FL6 は reworkCount >= 2 を検知済み。diagnostic_history が自然にリッチなデータを提供
- **advisor-usage.md**: 既存の「リトライ上限接近時」トリガーが DR5 と整合

## 実装順序

1. `rules/diagnostic-reasoning.md` 作成（基盤）
2. `agents/parallel-worker.md` 修正（最も頻繁なリトライポイント）
3. `skills/spec-implement/SKILL.md` 修正（rework cycle の diagnostic_history 蓄積）
4. `agents/wave-harness-worker.md` 修正（retry_mode の強化）
5. `rules/INDEX.md` 更新（インデックス登録）

ステップ 2 と 4 は独立しているため並列実行可能。

## 検証方法

- プラグイン内変更のみのため、フロントエンドテストは省略（CLAUDE.md ルール）
- `rules/INDEX.md` の合計数と新規ルール ID の整合性を確認
- `diagnostic-reasoning.md` の frontmatter（`always_apply: true`）が正しいことを確認
- parallel-worker.md と wave-harness-worker.md の既存セクション（Retry Policy、Output schema 等）が破壊されていないことを差分で確認
- spec-implement.md の rework プロンプトテンプレートが正しい JavaScript テンプレートリテラル構文であることを確認
