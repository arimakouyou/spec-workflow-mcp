# spec-implement 中断・再開プロトコル

`/spec-workflow-mcp:spec-implement` が API レートリミット、ネットワーク切断、強制中断、マシン再起動等で中断された場合に、**step 粒度で安全に再開**する仕組みのリファレンス。

- 関連 skill: [`/spec-resume`](../.claude-plugin/skills/spec-resume/SKILL.md)
- 関連 skill: [`/spec-implement`](../.claude-plugin/skills/spec-implement/SKILL.md)
- 実装計画: [`.claude/_docs/plans/step-resume-mechanism.md`](../.claude/_docs/plans/step-resume-mechanism.md)

## 概要

中断・再開を支える 2 種類の append-only ログと、hook による自動記録で成立している。

| 真実の源泉 | 役割 |
|----------|------|
| `.spec-workflow/specs/<spec>/Implementation Logs/task-<sanitizedTaskId>_progress.md` | step 粒度の進行ログ |
| `.spec-workflow/specs/<spec>/Review Logs/task-<sanitizedTaskId>_reviews.md` | レビュー指摘の履歴 |
| `tasks.md` のチェックボックス | **表示** (progress.md から自動同期される) |
| git tag `spec-impl/<spec>/task-<id>/step-<step>/attempt-<N>` | step 開始時点の checkpoint |

### 責務分離

- **PreToolUse(Task) hook**: `<spec-step>` タグを検出し `BEGIN` イベントを progress.md に記録。git tag 作成。タグ欠落は exit 2 で block
- **PostToolUse(Task) hook**: `END` イベントを progress.md に記録
- **SubagentStop hook**: PostToolUse が漏れた場合の保険
- **SessionStart hook**: lockfile 残存検出、dirty tree 警告
- **PostToolUse(Edit|Write) hook**: progress.md 編集検出 → `scripts/sync-spec-tasks.ts` 起動 → tasks.md 自動同期
- **orchestrator (LLM)**: `VERIFIED` / `FAILED` / `COMPLETE` を `scripts/append-progress-event.ts` 経由で append

## イベント種別

progress.md の行フォーマット:

```
<ISO8601_UTC>\t<EVENT>\t<STEP_ID>\t<META_JSON>
```

| EVENT | 書き込む主体 | 意味 |
|-------|------------|------|
| `BEGIN` | PreToolUse hook | step 開始 (subagent 起動直前) |
| `END` | PostToolUse / SubagentStop hook | step 呼び出し終了 (subagent return) |
| `VERIFIED` | orchestrator (LLM) | step 成果物を検証し合格 |
| `FAILED` | orchestrator (LLM) | step 回復不能失敗 |
| `COMPLETE` | orchestrator (LLM) | task 全 step 完了 |

## 有効な step ID

`[a-z0-9-]+` の形式。正準順序 (通常 task):

```
discover → red-write → red-verify → green-code → green-verify → refactor → refactor-verify → log
```

`_PhaseReview: true` task:

```
discover → log
```

Phase 境界 step (Phase 全体完了時):

```
phase-integration → phase-cve → phase-experts → phase-commit
```

その他: `ut-quality` (UT 品質検証), `simplify` (code-simplifier), `review-commit` (review-worker の commit)

## 再開判定アルゴリズム

progress.md の末尾イベントから次アクションを決定する。実装は `src/core/progress-log-parser.ts` の `decideResumeAction` 関数。

| 末尾 EVENT | 次アクション |
|-----------|------------|
| (ファイル無) or (空) | `start-fresh` (先頭 step `discover` から) |
| `COMPLETE` | `already-done` (task スキップ) |
| `VERIFIED <step>` | `resume-next` (次 step、attempt=1) |
| `FAILED <step>` | `escalate` (ユーザに問う、meta.reason 提示) |
| `END <step>` で `VERIFIED`/`FAILED` 無し | `redo-step` (その step やり直し、attempt +1) |
| `BEGIN <step>` で `END` 無し | `redo-step` (subagent 中断、attempt +1) |
| 同 step の `BEGIN` が MAX 回以上 (default 3) | `reset-to-task-start` (ユーザ確認推奨) |

## メタタグ `<spec-step>`

全 Task tool 呼び出しの prompt 先頭行に必須:

```
<spec-step spec="<specName>" task="<taskId>" step="<stepId>" attempt="<N>">
```

- `spec`, `task`, `step` は必須、`attempt` 省略時 1
- session lockfile 存在時、タグ欠落 Task は PreToolUse hook が exit 2 で block

## git checkpoint

step 開始時 (PreToolUse hook) に tag を自動作成:

```
spec-impl/<spec>/task-<sanitizedTaskId>/step-<stepId>/attempt-<N>
```

`sanitizedTaskId` は `.` と `/` を `-` に置換 (例: 2.1 → `2-1`)。

`COMPLETE` 時に同 task 配下の全 tag が自動削除される (`append-progress-event.ts` 内で `git tag -d` 呼び出し)。

## CLI 一覧

| CLI | 用途 |
|-----|------|
| `scripts/append-progress-event.ts <spec> <task> <EVENT> <step> [meta_json]` | orchestrator が VERIFIED/FAILED/COMPLETE を追記。COMPLETE 時は auto-cleanup + tasks.md 同期も同時発火 |
| `scripts/sync-spec-tasks.ts <spec>` | 手動 tasks.md 再同期 (緊急時) |
| `scripts/cleanup-spec-checkpoints.ts <spec> [task]` | checkpoint tag の手動削除 |
| `scripts/reset-to-checkpoint.ts <spec> <task> <step> <attempt> [--force]` | 指定 attempt の開始時点へ安全 reset (backup tag 自動作成) |
| `scripts/append-review-log.ts <spec> <task> <source> <attempt> <action> <categories_json> "<summary>"` | Review Logs に 1 エントリ追記 |
| `scripts/aggregate-review-logs.ts <spec> <task>` | Review Logs から `reviewProcess` JSON を集計出力 |

## Session lockfile

`.spec-workflow/.implement-session.json`:

```json
{
  "specName": "user-auth",
  "taskId": "2.1",
  "sessionId": "2026-04-19T14:14:00.000Z-abc",
  "startedAt": "2026-04-19T14:14:00.000Z",
  "pid": 0
}
```

spec-implement skill が wave 開始前に Write 作成、Final E2E Gate PASS 後に `rm` 削除。PreToolUse(Task) hook は lockfile 存在時のみ `<spec-step>` 必須化を発動する。

## 手動リカバリ手順

### ケース 1: 中断したまま新セッションを開始した

1. SessionStart hook が lockfile 残存を検出し、stderr に情報表示
2. `/spec-resume` skill を起動するか、同じ `/spec-implement <spec>` を再実行
3. spec-resume skill が progress.md の末尾を見て再開プロトコルを適用

### ケース 2: working tree が dirty な状態で再開したい

`/spec-resume` skill の Step 4 手順に従う:

- commit で残す
- `git stash` で退避
- `reset-to-checkpoint` で前回 BEGIN 時点へ破棄戻し (backup tag 自動作成付き)

### ケース 3: tasks.md と progress.md が不整合

```bash
npx tsx scripts/sync-spec-tasks.ts <spec>
```

で強制再同期。pending (progress 無) な task は触らない。

### ケース 4: task 先頭からやり直したい

- progress.md をバックアップ後に削除 (or `# ABORTED` コメント追記)
- 関連 checkpoint tag を削除:
  ```bash
  npx tsx scripts/cleanup-spec-checkpoints.ts <spec> <task>
  ```
- `/spec-implement <spec>` 再実行

## 関連テスト

- Unit: `src/core/__tests__/progress-log-parser.test.ts` (31 件)
- Unit: `src/core/__tests__/tasks-auto-update.test.ts` (15 件)
- Unit: `src/core/__tests__/review-log-parser.test.ts` (11 件)
- Integration: `src/core/__tests__/resume-integration.test.ts` (9 件、plan §9.2 シナリオ網羅)
