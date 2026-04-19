---
name: spec-resume
description: "中断された /spec-implement セッションを step 粒度で安全に再開するための判定プロトコル。lockfile または progress.md が残っている場合の再開位置特定、checkpoint reset、_DependsOn 影響確認を扱う。Triggers on: 'resume spec', 'resume implementation', 'spec-implement 再開', '/spec-resume'."
---

# Spec Resume — 中断セッション再開プロトコル

`/spec-implement` が API レートリミット、ネットワーク切断、強制中断、マシン再起動等で中断された後、**次セッションで安全に再開する**ための判定手順を提供する。この skill は spec-implement skill からも埋め込み参照される。

## 適用条件

次のいずれかに該当する場合に本プロトコルを適用する:

- `.spec-workflow/.implement-session.json` (session lockfile) が既に存在している状態で `/spec-implement` を起動した
- 対象 task の `.spec-workflow/specs/<spec>/Implementation Logs/task-<sanitizedId>_progress.md` が既に存在している
- ユーザが明示的に `/spec-resume` を叩いた

## 用語

- **progress.md**: 1 task = 1 ファイルの append-only ログ。パス: `.spec-workflow/specs/<spec>/Implementation Logs/task-<sanitizedTaskId>_progress.md`
- **sanitizedTaskId**: `.` と `/` を `-` に置換したもの (例: task 2.1 → `task-2-1`)
- **checkpoint tag**: 各 step の BEGIN 時に PreToolUse hook が作る git tag。形式: `spec-impl/<spec>/task-<sanitizedId>/step-<stepId>/attempt-<N>`
- **session lockfile**: `.spec-workflow/.implement-session.json`。存在する間 PreToolUse(Task) hook は `<spec-step>` タグ必須化を発動する

## Step 0: 前提読み込み

1. `.spec-workflow/.implement-session.json` を Read で読み、 `specName` / `taskId` / `startedAt` を取得
2. 対象 task の progress.md を Read で読む。存在しない → Step 1 の "ファイル無し" へ
3. git working tree の状態確認:
   ```bash
   git status --porcelain
   ```
   出力が非空 (= dirty) なら **Step 4 の dirty tree 手順を先に適用**

## Step 1: 末尾イベントによる再開判定

progress.md の末尾行 (ヘッダ `#` 行は除く) を確認し、以下の分岐で進む。行フォーマットは `<ISO8601>\t<EVENT>\t<STEP_ID>\t<META_JSON>`。

| 末尾 EVENT | 意味 | アクション |
|-----------|------|-----------|
| **ファイル無し** or **空** | 未開始 | `discover` step から新規開始。attempt=1 |
| `COMPLETE` | task 完了済 | **その task はスキップ**し、次の pending task に進む |
| `VERIFIED <step>` | step 検証済 | 次 step (下記 "正準順序") から再開、attempt=1 |
| `FAILED <step>` | 回復不能失敗 | **ユーザにエスカレート**。meta.reason を提示し指示を仰ぐ |
| `END <step>` で対応 `VERIFIED`/`FAILED` 無し | subagent は戻ったが検証前に中断 | その step を **redo**。新しい attempt 番号で再延起動 |
| `BEGIN <step>` で対応 `END` 無し | subagent 自体が中断 (レートリミット等) | その step を **redo**。新しい attempt 番号で再延起動 |
| 同 step の `BEGIN` が **3 回以上** | 試行上限到達 | **task 先頭に戻すかユーザに確認**。自動 reset 禁止 |
| フォーマット破損行のみ | 信頼不能 | `discover` step から新規開始、破損を warn 表示 |

### 正準順序 (step 進行)

通常 task:

```
discover → red-write → red-verify → green-code → green-verify
        → refactor → refactor-verify → log
```

`_PhaseReview: true` task:

```
discover → log
```

未知の step ID は warning 扱い。勝手に拡張しない。

## Step 2: attempt 番号の算出

redo 対象 step の新しい attempt 番号:

```
attempt = (progress.md 内で当該 step の BEGIN 行数) + 1
```

`attempt >= 4` (= 既に 3 回 BEGIN がある) なら Step 1 の試行上限ケースへ。

## Step 3: `_DependsOn` 影響確認 (再開時に必須)

対象 task が `tasks.md` 上で `_DependsOn: X.Y, A.B` を持つ場合:

1. 依存先 task の progress.md を全て確認
2. 依存先に `FAILED` / `BEGIN without END` (= 中断中) が残っていれば、**依存先を先に解決するようユーザに提示**
3. 依存先が `[x]` (COMPLETE 済) であっても、依存先の実装がその後書き換えられた可能性がある場合はユーザに告知
4. **自動で依存先を巻き戻さない** — 候補提示のみ。ユーザ承認を待って進める

## Step 4: redo 前の dirty tree 対処

`git status --porcelain` が非空 (dirty) な場合、redo を始める前に以下のいずれかをユーザと合意して実行する:

### 選択肢

1. **commit** (変更を記録して進める):
   ```bash
   git add -A
   git commit -m "wip: spec-implement resume preserve"
   ```

2. **stash** (一時退避):
   ```bash
   git stash push -u -m "spec-implement resume-safety $(date -u +%FT%TZ)"
   ```

3. **checkpoint reset** (破棄して前回 BEGIN 時点に戻す):
   ```bash
   npx tsx scripts/reset-to-checkpoint.ts <spec> <task> <step> <前回N>
   # 内容確認後
   npx tsx scripts/reset-to-checkpoint.ts <spec> <task> <step> <前回N> --force
   ```
   reset-to-checkpoint は現在 HEAD を `spec-impl-backup/<ts>` に退避してから reset する。ロールバックは `git reset --hard spec-impl-backup/<ts>`。

4. **手動解決**: ユーザに任せて skill を終了

**必ずユーザ承認を得てから実行**。自動破棄禁止。

## Step 5: 再開 Task の起動

上記で決定した `(step, attempt)` を元に spec-implement skill の当該 Task cycle (step 4 parallel-worker 等) に戻り、対象 subagent を `<spec-step>` タグ付きで起動する:

```
<spec-step spec="<spec>" task="<taskId>" step="<stepId>" attempt="<N>">
```

PreToolUse(Task) hook が新しい `BEGIN` を progress.md に append し、新しい checkpoint tag を作成する。

## Step 6: COMPLETE 時のクリーンアップ

task が完全に完了 (= append-progress-event COMPLETE が成功) した時点で以下が**自動**実行される:

1. progress-write-sync hook が tasks.md を `[-]` → `[x]` に同期
2. append-progress-event 自体が `spec-impl/<spec>/task-<sanitizedId>/*` 配下の全 checkpoint tag を削除

手動実行する場合:

```bash
npx tsx scripts/cleanup-spec-checkpoints.ts <spec> <task>
```

spec 全体の cleanup:

```bash
npx tsx scripts/cleanup-spec-checkpoints.ts <spec>
```

## Step 7: 全 task 完了時の lockfile 削除

全 wave が完了し Final E2E Gate が PASS した後、spec-implement skill は以下で lockfile を削除する (Bash tool で):

```bash
rm -f .spec-workflow/.implement-session.json
```

lockfile が無くなった時点で PreToolUse(Task) hook は pass-through 動作に戻る。

## 参考: 各 CLI コマンド

| CLI | 用途 |
|-----|------|
| `scripts/append-progress-event.ts <spec> <task> <EVENT> <step> [meta_json]` | orchestrator が VERIFIED/FAILED/COMPLETE を追記。COMPLETE 時は自動 cleanup と tasks.md 同期も発火 |
| `scripts/sync-spec-tasks.ts <spec>` | 手動で tasks.md を progress.md 群から再同期 (緊急時) |
| `scripts/cleanup-spec-checkpoints.ts <spec> [task]` | checkpoint tag の手動削除 |
| `scripts/reset-to-checkpoint.ts <spec> <task> <step> <attempt> [--force]` | 指定 attempt の開始時点へ安全 reset (backup tag 自動作成) |

## 参考: 関連ドキュメント

- 設計計画: `.claude/_docs/plans/step-resume-mechanism.md`
- hook 挙動実験: `.claude/_docs/experiments/hook-behavior-2026-04-19.md`
- spec-implement 本体: `.claude-plugin/skills/spec-implement/SKILL.md` (Session Tracking & Resume Protocol section)
