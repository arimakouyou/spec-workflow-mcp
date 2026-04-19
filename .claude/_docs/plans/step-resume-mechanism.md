# spec-implement セッション中断時 step 粒度レジューム機構 実装計画

## 1. 目的と完了条件

### 1.1 目的

`/spec-workflow-mcp:spec-implement` の長時間実行中（API レートリミット、ネットワーク切断、ユーザー強制中断、マシン再起動など）にセッションが中断された場合、**step 粒度で安全に再開**できる機構を導入する。「VERIFIED まで完了した step はスキップし、未完または途中で止まった step は安全に redo する」を機械判定可能にし、手戻り作業を最小化する。

### 1.2 完了条件

以下すべてが満たされた時点で完了とする。

1. `src/prompts/implement-task.ts` の 12+ ステップが全て subagent 委任に書き換えられ、各 Task 呼び出しに `<spec-step>` メタタグが必須として明文化されている
2. `.spec-workflow/specs/{specName}/Implementation Logs/task-{taskId}_progress.md` に PreToolUse/PostToolUse/SubagentStop の各 hook が BEGIN/END イベントを durable に append する
3. 再開プロトコル skill (`.claude-plugin/skills/spec-resume/SKILL.md` 新設予定) が、progress.md の末尾エントリから次実行 step を決定する手順を規定している
4. validation hook が、spec-implement セッション中の `<spec-step>` 欠落 Task 呼び出しをブロックする
5. git checkpoint 自動化（step 開始時 tag、再開時 reset）が動作し、dirty tree 時はセッション開始をブロックする
6. tasks.md が progress.md のイベントから自動更新される（BEGIN→`[-]`、COMPLETE→`[x]`）
7. `_DependsOn` を持つタスク再開時、ユーザーに影響範囲確認フローが表示される
8. unit test（再開判定関数）と integration test（中断→再開シナリオ）が green

### 1.3 完了の非対象

- MCP tool の新規追加（skill + hook のみで実装）
- 既存 Implementation Logs フォーマット（完成ログ）の変更
- ダッシュボード UI への progress.md 可視化（別 issue）

---

## 2. アーキテクチャ概要

### 2.1 登場人物と責務

| コンポーネント | 配置 | 責務 | 新規/既存 |
|----------|------|------|-----------|
| `implement-task.ts` プロンプト | `src/prompts/implement-task.ts` | 12+ ステップ TDD プロンプトを生成。各 step を subagent 委任に書き換え、メタタグ必須化 | 既存・改修 |
| `spec-implement` skill | `.claude-plugin/skills/spec-implement/SKILL.md` | wave 計算、parallel-worker 等へのオーケストレーション。Task 呼び出しに `<spec-step>` 付与を厳格化 | 既存・改修 |
| `spec-resume` skill | `.claude-plugin/skills/spec-resume/SKILL.md` | セッション開始時の再開判定プロトコル、`_DependsOn` 影響確認、checkpoint reset 手順 | 新規 |
| progress hook (PreTool) | `.claude-plugin/hooks/progress-begin.sh` | Task 呼び出しの prompt から `<spec-step>` を抽出し `BEGIN` を append。tag 欠落時は block | 新規 |
| progress hook (PostTool) | `.claude-plugin/hooks/progress-end.sh` | Task 完了／エラー時に `END` を append | 新規 |
| progress hook (SubagentStop) | `.claude-plugin/hooks/progress-subagent-stop.sh` | subagent 強制停止時の保険 `END` を append | 新規 |
| progress hook (SessionStart) | `.claude-plugin/hooks/session-start-guard.sh` | spec-implement セッション検出、dirty tree 拒否、未 clean な前回 checkpoint の案内 | 新規 |
| progress.md | `.spec-workflow/specs/{specName}/Implementation Logs/task-{taskId}_progress.md` | append-only の真実ログ | 新規ファイル種別 |
| Review Logs | `.spec-workflow/specs/{specName}/Review Logs/task-{taskId}_reviews.md` | pre-push-review / handle-pr-comments / codex:review 結果の append。完成後 `reviewProcess` JSON に集計転記 | 新規ファイル種別 |
| progress parser | `src/core/progress-log-parser.ts` | progress.md の行パース、末尾 N エントリから再開判定を算出 | 新規 |
| tasks.md auto-updater | `src/core/tasks-auto-update.ts` | progress.md のイベント遷移から tasks.md の `[ ] / [-] / [x]` を同期 | 新規 |
| session lockfile | `.spec-workflow/.implement-session.json` | spec-implement 実行中であることを hook へ伝達。skill 入口で作成、完了／中断検知で削除 | 新規 |

### 2.2 データフロー概観

```
ユーザー: /spec-implement → spec-implement skill 起動
  ↓
SessionStart hook: dirty tree チェック、lockfile 作成、既存 progress.md 読み込み
  ↓
再開判定（spec-resume skill の手順を適用）
  ↓
各 step ごとに:
  Orchestrator → Task(<spec-step spec=… task=… step=…>…) を呼ぶ
    PreToolUse hook: tag 抽出 → progress.md に BEGIN append、git tag 付与
    subagent 実行
    PostToolUse hook: progress.md に END append
  Orchestrator: subagent 完了報告を読んで VERIFIED または FAILED を progress.md に append
  ↓
task 完了: COMPLETE 追記、Review Logs を集計して /log-implementation に reviewProcess 渡す
  ↓
tasks.md auto-updater: [-] → [x]
  ↓
lockfile 削除
```

### 2.3 真実 / 表示の分離

- **真実**: `progress.md`（append-only、hook が機械的に書き込む、LLM も VERIFIED/FAILED/COMPLETE を追記）
- **表示**: `tasks.md`（チェックボックス、ユーザーがひと目で進捗を把握するため）
- tasks.md の手動編集も許容するが、競合時は progress.md が優先。auto-updater は「progress が COMPLETE なのに tasks が `[-]`」のような不整合を検出し自動修正。

---

## 3. 事前検証タスク（約 1〜2 時間、実装前に必ず実施）

以下 4 項目を**実装着手前に検証**し、結果を `.claude/_docs/experiments/hook-behavior-{date}.md` 等にメモする（別セッションで要実施）。

### 3.1 `"matcher": "Task"` が hooks.json で動作するか

既存の hooks.json は `Bash | Read | Edit|Write` しか matcher に指定していない。Task 呼び出しに対し PreToolUse / PostToolUse が発火するか、ダミー hook（`echo received`）を登録して確認。

### 3.2 Task tool の hook 入力 JSON 構造

hook に渡される stdin JSON を `jq .` でダンプし、subagent の prompt がどのフィールドに入るか確認（想定: `.tool_input.prompt` または `.tool_input.description` 等）。`<spec-step>` タグ抽出の jq パスを確定する。

### 3.3 エラー時の PostToolUse 発火有無

Task tool がエラーを返す（subagent が throw、timeout、invalid input）ケースで PostToolUse が発火するか、しないか。**発火しない場合は SubagentStop hook が代替として必要**。

### 3.4 レートリミット kill 時の SubagentStop 発火有無

主プロセス（Claude Code）が API レートリミットで強制終了された場合、SubagentStop は発火しない可能性が高い。この場合は「次セッション開始時に BEGIN 有り・END 無しを検出して redo」が唯一のリカバリ経路となる。仕様書にその旨を明記する。

### 3.5 検証タスクの Plan 出力

検証結果が以下のいずれかなら、実装方針を調整：

- 3.1 が NG → Task matcher が使えないため、代替として `SubagentStop` のみで END を記録する方式に縮退
- 3.2 で prompt が取れない → `description` フィールドにもタグを多重記載するルールに変更
- 3.3 で PostToolUse が発火しない → FAILED の記録は LLM 側の責務にする（hook に頼らない）

---

## 4. 実装項目（優先度、ファイルパス、依存関係）

優先度: **P0=必須**, **P1=重要**, **P2=あれば良い**

| # | 優先度 | 項目 | ファイル | 依存先 |
|---|:-----:|------|---------|---------|
| 4.1 | P0 | progress parser | `src/core/progress-log-parser.ts`（新規） | - |
| 4.2 | P0 | resume judge 関数 | `src/core/progress-log-parser.ts` 内（`decideResumeAction`） | 4.1 |
| 4.3 | P0 | tasks auto-updater | `src/core/tasks-auto-update.ts`（新規） | 4.1 |
| 4.4 | P0 | progress-begin hook | `.claude-plugin/hooks/progress-begin.sh`（新規） | 3.1, 3.2 |
| 4.5 | P0 | progress-end hook | `.claude-plugin/hooks/progress-end.sh`（新規） | 3.3 |
| 4.6 | P0 | subagent-stop hook | `.claude-plugin/hooks/progress-subagent-stop.sh`（新規） | 3.4 |
| 4.7 | P0 | session-start hook | `.claude-plugin/hooks/session-start-guard.sh`（新規） | - |
| 4.8 | P0 | validation hook（tag 欠落 block） | 4.4 と統合（progress-begin.sh 内で判定） | 4.4 |
| 4.9 | P0 | hooks.json 更新 | `.claude-plugin/hooks/hooks.json`（改修） | 4.4-4.7 |
| 4.10 | P0 | session lockfile 仕様 | `.spec-workflow/.implement-session.json`（形式ドキュメント） | - |
| 4.11 | P0 | `spec-resume` skill 新規 | `.claude-plugin/skills/spec-resume/SKILL.md`（新規） | 4.2 |
| 4.12 | P0 | implement-task.ts 全 step 委任化 | `src/prompts/implement-task.ts`（改修） | - |
| 4.13 | P0 | implement-task.ts にメタタグ必須化 | `src/prompts/implement-task.ts`（改修） | 4.12 |
| 4.14 | P0 | spec-implement skill にメタタグ必須化 | `.claude-plugin/skills/spec-implement/SKILL.md`（改修） | - |
| 4.15 | P1 | git checkpoint 自動化 | `.claude-plugin/hooks/progress-begin.sh` + `spec-resume` skill | 4.4, 4.11 |
| 4.16 | P1 | `_DependsOn` 再開確認プロトコル | `spec-resume` SKILL.md に記述 | 4.11 |
| 4.17 | P1 | Review Logs append プロトコル | `spec-implement` SKILL.md の step 6 付近を改修 | - |
| 4.18 | P1 | reviewProcess 集計ロジック | `log-implementation` skill を改修（既存 SKILL.md に step 追加） | 4.17 |
| 4.19 | P2 | dashboard に progress.md 表示 | 別 issue（本計画外） | - |

### 4.12 inline 実行箇所の委任化（implement-task.ts）

現状 inline で書かれている箇所（要改修）を列挙：

| 現状ステップ | 現状の実装形態 | 改修方針 |
|-----------|--------------|---------|
| 2. Start the Task (tasks.md を `[ ]`→`[-]`) | Edit tool 直接呼出 | auto-updater が progress.md の BEGIN 受けて自動処理するため、プロンプトからは削除（LLM は触らない） |
| 5. Discover Existing Implementations (grep/ripgrep) | Bash/Read inline | subagent（新設 `discover-worker` 不要。parallel-worker 冒頭で実施させれば足りる）に委任 |
| 6-11. RED/GREEN/REFACTOR/Verify | 既に subagent 化済み | 各 Task 呼び出しに `<spec-step>` タグ必須化 |
| 12. Log Implementation | `/log-implementation` skill 呼び出し | skill 呼び出しも Task で包む形式に統一。`<spec-step step="log">` を付与 |
| 13. Complete the Task (tasks.md を `[-]`→`[x]`) | Edit tool 直接呼出 | auto-updater が COMPLETE event 受けて自動処理するため、プロンプトからは削除 |

### 4.13 / 4.14 メタタグ必須化の文言案

implement-task.ts と spec-implement SKILL.md の冒頭に以下を挿入：

> ⛔ **メタタグ必須**: このセッション中で Task tool を呼ぶ際は、プロンプトの先頭行に必ず `<spec-step spec="{specName}" task="{taskId}" step="{stepId}">` を含めること。欠落した呼び出しは PreToolUse hook によりブロックされ、セッション中断時の再開が不能になる。

---

## 5. progress.md / Review Logs ファイルフォーマット

### 5.1 progress.md の行形式

```
<ISO8601_UTC>\t<EVENT>\t<STEP_ID>\t<META_JSON>
```

- タブ区切り。`META_JSON` は単一行 JSON（改行不可）
- append のみ。編集や末尾切り詰めは禁止
- ファイル先頭にヘッダ（`# Progress Log: Task {taskId}` + spec/task メタ）

#### イベント種別

| EVENT | 記録元 | 意味 | META_JSON 例 |
|-------|-------|------|-------------|
| `BEGIN` | PreToolUse hook | step 開始。`<spec-step>` タグ検出時 | `{"prompt_hash":"sha1…","checkpoint":"spec-impl/feat-x/task-1/step-red/attempt-1"}` |
| `END` | PostToolUse hook | Task 呼び出し終了（成功/失敗問わず） | `{"status":"ok"/"error","tool_result_hash":"sha1…"}` |
| `VERIFIED` | LLM（orchestrator） | step の成果物を検証し合格 | `{"evidence":"tests_passed","next_step":"green"}` |
| `FAILED` | LLM（orchestrator） | step が回復不能に失敗、上位判断必要 | `{"reason":"…","action":"escalate"}` |
| `COMPLETE` | LLM（orchestrator） | task 全体完了 | `{"log_id":"uuid…"}` |

### 5.2 Review Logs の行形式

```
<ISO8601_UTC>\t<REVIEW_SOURCE>\t<ATTEMPT>\t<ACTION>\t<CATEGORIES_JSON>\t<SUMMARY>
```

- `REVIEW_SOURCE` ∈ `{pre-push-review, handle-pr-comments, codex-review, phase-review-team}`
- `ATTEMPT`: 1, 2, 3…（同 task での通算）
- `ACTION` ∈ `{commit, rework, escalate}`
- `CATEGORIES_JSON`: `["naming", "security"]` 等
- `SUMMARY`: 自由記述（タブ禁止、改行は `\n` エスケープ）

### 5.3 タイムスタンプ規約

- 全て `date -u +%Y-%m-%dT%H:%M:%S.%3NZ` 形式
- hook スクリプト内では `date -u +%Y-%m-%dT%H:%M:%S.000Z`（ms 不要な環境）
- LLM は ISO8601 UTC を明示指示

---

## 6. メタタグ規約

### 6.1 `<spec-step>` 属性仕様

```
<spec-step spec="{kebab-case}" task="{taskId}" step="{stepId}" attempt="{N}">
```

| 属性 | 必須 | 値域 | 説明 |
|-----|:---:|------|------|
| `spec` | Yes | kebab-case | スペック名。`[a-z0-9-]+` |
| `task` | Yes | taskId | `[0-9.]+`（例: `1`, `2.1`, `3.1.4`） |
| `step` | Yes | step ID | 下記 6.2 参照 |
| `attempt` | No | 正の整数 | 同 step の再試行番号（省略時 1） |

### 6.2 step ID の命名表（implement-task.ts の 12+ 段階に対応）

| step ID | 対応する大ステップ | 備考 |
|---------|---------------|------|
| `discover` | 5. 既存実装探索 | subagent 委任 |
| `red-write` | 6. RED テスト作成 | |
| `red-verify` | 7. RED 検証 | |
| `green-code` | 8. GREEN 実装 | |
| `green-verify` | 9. GREEN 検証 | |
| `refactor` | 10. REFACTOR | |
| `refactor-verify` | 11. 再テスト | |
| `ut-quality` | 5 (SKILL.md) | UT 品質検証 |
| `simplify` | 5.5 (SKILL.md) | code-simplifier |
| `review-commit` | 6 (SKILL.md) | review-worker |
| `log` | 12. /log-implementation | |
| `phase-integration` | 3.5.1.5 | PhaseReview 統合検証 |
| `phase-cve` | 3.5.1.6 | CVE 監査 |
| `phase-experts` | 3.5.2 | Expert Team Review |
| `phase-commit` | 3.5.3 | Phase 最終 commit |

step ID は `[a-z0-9-]+` に統一し、ドキュメントに一覧化する。LLM が勝手な step ID を作ると再開判定が狂うため、**spec-resume skill で有効 ID リストを enumerate し、未知 ID は warning に落とす**。

### 6.3 LLM が守るルール

1. Task tool 呼び出しの prompt 先頭行に必ず `<spec-step>` タグを置く
2. `VERIFIED` / `FAILED` / `COMPLETE` は subagent ではなく orchestrator（spec-implement skill 本体）が progress.md に書く
3. attempt は `BEGIN` 数と一致させる（3 回目の BEGIN なら attempt=3）
4. 1 つの Task 呼び出しに複数 step をまとめない（細粒度を維持）

---

## 7. 再開判定アルゴリズム（擬似コード）

```text
function decideResumeAction(progressLogPath, taskId) -> ResumeAction:
  if not exists(progressLogPath):
    return { kind: "start-fresh", step: FIRST_STEP, attempt: 1 }

  events = parseProgressLog(progressLogPath)  // [{ ts, event, step, meta }]
  if events is empty or last event is broken:
    return { kind: "start-fresh", step: FIRST_STEP, attempt: 1 }

  last = events[-1]

  if last.event == "COMPLETE":
    return { kind: "already-done" }   // skip this task

  if last.event == "VERIFIED":
    nextStep = successorStep(last.step)
    if nextStep is None:
      return { kind: "needs-complete", step: last.step }  // log が終わって COMPLETE 未記録
    return { kind: "resume-next", step: nextStep, attempt: 1 }

  if last.event == "FAILED":
    return { kind: "escalate", step: last.step, reason: last.meta.reason }

  if last.event == "END":
    // BEGIN と END はあるが VERIFIED/FAILED が無い = 検証前に中断
    attemptCount = countEventsInStep(events, last.step, "BEGIN")
    if attemptCount >= MAX_ATTEMPTS_PER_STEP:  // default 3, skill で調整可
      return { kind: "reset-to-task-start", reason: "too-many-attempts" }
    return { kind: "redo-step", step: last.step, attempt: attemptCount + 1 }

  if last.event == "BEGIN":
    // BEGIN はあるが END 無し = subagent 中断（レートリミット等）
    attemptCount = countEventsInStep(events, last.step, "BEGIN")
    if attemptCount >= MAX_ATTEMPTS_PER_STEP:
      return { kind: "reset-to-task-start", reason: "too-many-attempts" }
    return { kind: "redo-step", step: last.step, attempt: attemptCount + 1 }

  return { kind: "start-fresh", step: FIRST_STEP, attempt: 1 }


function successorStep(step) -> Step | None:
  // 6.2 の順序表を参照、最後の step なら None を返す

function countEventsInStep(events, step, eventKind) -> int
```

### 7.1 MAX_ATTEMPTS_PER_STEP

- default 3
- 「タスク先頭に戻す」をユーザー確認にするオプションは skill 側で扱う（checkpoint reset を伴うため破壊的）
- 再試行 2 回連続失敗かつ failure_category が同一の場合、diagnostic-reasoning DR6 DIVERGENT を適用（既存の parallel-worker 仕様と整合）

### 7.2 破損検出

- 行フォーマット違反（タブ数不正、timestamp パース失敗）を検出したら、その行はスキップし warn ログに出す
- ファイル末尾が途中で切れている（改行無し）場合、最後の行は不完全とみなし無視
- 複数行にまたがる META_JSON は禁止（パーサが前提とする）

---

## 8. git checkpoint 戦略

### 8.1 タグ命名規則

```
spec-impl/{specName}/task-{sanitizedTaskId}/step-{stepId}/attempt-{N}
```

- `sanitizedTaskId`: `.` と `/` を `-` に置換（既存 `implementation-log-migrator.ts` の慣習に合わせる）
- 例: `spec-impl/user-auth/task-2-1/step-green-code/attempt-1`

### 8.2 作成

- PreToolUse hook（progress-begin.sh）内で `git tag -f {tagname}` を実行
- `-f` で同 step 再試行時は上書き（attempt-N が異なるので衝突はしないが、中断で同 attempt を redo する場合は上書きを意図）
- tag はワーキングツリーが clean でない場合も作成可能（参照だけ）

### 8.3 reset（再開時）

- spec-resume skill がユーザーに提示し、承認を得てから：
  ```
  git reset --hard {tag-before-step}
  ```
- 破壊的操作のため、**必ずユーザー確認を挟む**（advisor 指摘の事故防止）
- worktree を使っている場合（spec-implement の step 3.7）は該当 worktree で reset

### 8.4 セッション開始時の dirty tree 検出

SessionStart hook（`session-start-guard.sh`）で：

```bash
# spec-implement セッション起動の兆候検出（lockfile 等）
if [ -f .spec-workflow/.implement-session.json ]; then
  if ! git diff --quiet HEAD || ! git diff --cached --quiet; then
    echo "⛔ [spec-resume] ワーキングツリーが dirty です。"
    echo "spec-implement を再開するには、未コミットの変更を commit または stash してください。"
    exit 2  # block
  fi
fi
```

### 8.5 自動 cleanup

- タスク COMPLETE 時、その task の checkpoint tag 群を一括削除（orchestrator の責務）
- セッション開始時に前回 session の未 clean な tag が残っていれば検出し、ユーザーに cleanup or 再開を選ばせる
- `spec-impl/*` という prefix を使っているので他 tag と衝突しない

### 8.6 事故防止チェックリスト

- [ ] dirty tree 時のセッション開始を block
- [ ] reset は必ずユーザー確認
- [ ] tag 命名に spec/task/step/attempt 全部含める（衝突回避）
- [ ] tag は `-f` で上書き可
- [ ] checkpoint 作成失敗時は session 継続（tag は best-effort、本体は progress.md）
- [ ] `git reset --hard` の前に現在 HEAD を `spec-impl-backup/{timestamp}` に退避

---

## 9. テスト計画

### 9.1 unit test（`src/core/__tests__/progress-log-parser.test.ts`）

| ケース | 入力（progress.md 末尾） | 期待 decideResumeAction |
|-------|----------------------|----------------------|
| ファイル無し | - | `start-fresh` |
| 空ファイル | `""` | `start-fresh` |
| 最後が VERIFIED discover | BEGIN/END/VERIFIED | `resume-next` → `red-write` |
| 最後が END red-write、VERIFIED 無し | BEGIN/END | `redo-step red-write attempt=2` |
| 最後が BEGIN green-code、END 無し | BEGIN のみ | `redo-step green-code attempt=1` |
| 同 step BEGIN 3 回 | 3×BEGIN | `reset-to-task-start` |
| 最後が COMPLETE | …/COMPLETE | `already-done` |
| 壊れた行を含む | `garbage\n…BEGIN\tred-write\t…` | 壊れ行スキップ、通常判定 |
| 最後の行が改行なし不完全 | | 最後行無視 |
| FAILED で終わる | …/FAILED | `escalate` |

### 9.2 integration test（`src/core/__tests__/resume-integration.test.ts`）

- ダミー spec を `.spec-workflow/specs/test-spec/` 配下に作成
- 各シナリオで progress.md と tasks.md 状態を検証：
  1. **途中 SIGKILL**: green-code BEGIN 後に kill → 再起動 → `redo-step green-code attempt=2`
  2. **subagent rate limit**: BEGIN/END/（VERIFIED 無し）→ 再起動 → `redo-step` 同 step
  3. **MAX_ATTEMPTS 到達**: 3 回 BEGIN → `reset-to-task-start`（ユーザー確認プロンプトをモック）
  4. **COMPLETE 後再実行**: `already-done` で次タスクへ
  5. **tasks.md drift**: progress COMPLETE なのに tasks `[-]` → auto-updater が `[x]` に修正

### 9.3 hook スクリプト test（shellcheck + bats）

- `progress-begin.sh`: stdin JSON を与えて stdout / exit code を検証
  - tag 有り session → BEGIN 記録、exit 0
  - tag 無し session → exit 2、stderr にエラー
  - lockfile 無し → pass through（何もしない）
- `progress-end.sh`: 同様
- `session-start-guard.sh`: dirty tree → exit 2

### 9.4 手動シナリオ（READMEに記載）

1. `/spec-implement my-feat` 実行
2. green-code 中に Ctrl+C
3. 再度 `/spec-implement my-feat` 実行 → 同 step から redo されることを目視確認
4. progress.md を `cat` して BEGIN/END 行が期待通り append されているか確認
5. `git tag -l 'spec-impl/*'` で checkpoint tag が作られていること確認
6. 完了後 `git tag -l 'spec-impl/my-feat/*'` が消えていること確認

---

## 10. ドキュメント更新

| ファイル | 追加内容 |
|---------|---------|
| `docs/PROMPTING-GUIDE.ja.md` | `:678` 周辺の「中断・再開仕様（バックログ）」を本機構の実装解説に差し替え |
| `docs/PROMPTING-GUIDE.md` | 同上（英訳） |
| `docs/RESUME-PROTOCOL.ja.md`（新規） | progress.md フォーマット、step ID 一覧、再開アルゴリズム、checkpoint 戦略 |
| `docs/RESUME-PROTOCOL.md`（新規） | 英訳 |
| `README.ja.md` | `spec-implement` セクションに「中断しても安全に再開可能」の一文追加 |
| `README.md` | 同上 |
| `.claude-plugin/skills/spec-implement/SKILL.md` | 冒頭に「中断・再開について」の節追加、メタタグ規約を明記 |
| `docs/TROUBLESHOOTING.ja.md` | 「spec-implement が再開できない時」節を追加 |

---

## 11. リスクと未解決事項

### 11.1 高リスク

| リスク | 影響 | 緩和策 |
|-------|------|--------|
| `"matcher": "Task"` が hooks.json でサポートされない | BEGIN/END が記録されず機構全体が成立しない | 事前検証 3.1 で確認。NG なら SubagentStop hook のみで代用する縮退プランを採用 |
| hook 入力 JSON から `<spec-step>` を抽出できない | 同上 | 検証 3.2 で jq パス確定。prompt が複数フィールドに散る場合、description にも多重記載を義務化 |
| LLM が `<spec-step>` タグを忘れる | silent failure（次 VERIFIED を誤って前進判定） | validation hook（4.8）で tag 欠落 Task を exit 2 でブロック |
| レートリミット kill 時 SubagentStop 未発火 | END が記録されず BEGIN のみ → 再開時に redo-step（期待通り）。ただし PreTool だけ書かれ END 未書込の状態 | 仕様上これで問題ない。END 無しを「中断」として扱う設計 |
| `git reset --hard` で未ログ作業を消失 | 作業消失 | ユーザー確認必須化、`spec-impl-backup/{timestamp}` に退避 |

### 11.2 中リスク

- progress.md がファイルロック無しで並列書き込みされると破損する可能性
  - 対策: 同一 task の hook は並列にならない想定（wave 内の並列は task 単位、task 内 step は逐次）
  - flock を導入するかは後続 issue
- tasks.md auto-updater が外部編集（ユーザー手動）と競合
  - 対策: auto-updater は progress 優先、ただし手動編集をログに warn
- step ID を LLM が勝手に拡張して再開判定が混乱
  - 対策: spec-resume skill で有効 ID を enumerate、未知 ID は warning 扱い

### 11.3 未解決事項（plan レビュー時にユーザーに確認）

1. MAX_ATTEMPTS_PER_STEP のデフォルト（3 で良いか、spec ごとに調整可能にするか）
2. ユーザー確認プロンプトのインタフェース（skill 内の出力メッセージ方式で良いか、MCP tool 経由にする必要はないか）
3. Review Logs の保持期間（完成後 reviewProcess へ集計後、元ファイルは残す？削除？）
4. 並列 wave 実行中の progress.md 競合を真面目に flock で解くか、taskごとファイル分割で十分か
5. codex:review 等の外部 plugin 由来レビューの output 形式 → Review Logs 行形式へのマッピング仕様

---

## 12. 実装順序と推定工数

| # | フェーズ | 工数（人日） | 実装項目 |
|---|--------|:---------:|---------|
| P1 | 事前検証 | 0.5 | 3.1〜3.5 の挙動確認 |
| P2 | progress parser + unit test | 1.0 | 4.1, 4.2, 9.1 |
| P3 | hooks 実装 + shell test | 1.0 | 4.4〜4.7, 4.9, 9.3 |
| P4 | tasks auto-updater | 0.5 | 4.3 |
| P5 | session lockfile + SessionStart guard | 0.5 | 4.7, 4.10 |
| P6 | spec-resume skill | 1.0 | 4.11, 4.16 |
| P7 | implement-task.ts 委任化 + メタタグ | 0.5 | 4.12, 4.13 |
| P8 | spec-implement skill メタタグ必須化 | 0.5 | 4.14 |
| P9 | Review Logs + reviewProcess 集計 | 1.0 | 4.17, 4.18 |
| P10 | git checkpoint 自動化 | 0.5 | 4.15 |
| P11 | integration test | 1.0 | 9.2, 9.4 |
| P12 | ドキュメント整備 | 1.0 | 10 |
| **合計** | | **9.0** | |

### 12.1 Phase 分割（recommend）

- **Phase A（MVP、3 人日）**: P1, P2, P3, P4, P7 → hook で記録できて再開判定できる最小構成
- **Phase B（堅牢化、3 人日）**: P5, P6, P8, P10 → skill での再開プロトコルと checkpoint
- **Phase C（集計・仕上げ、3 人日）**: P9, P11, P12 → Review Logs 集計と docs

---

## 付録 A. 参照済み既存資産

- `src/prompts/implement-task.ts`: 12 段階 TDD プロンプト
- `src/core/implementation-log-migrator.ts`: sanitizeTaskId / timestamp 規約（継承）
- `src/core/task-parser.ts`: tasks.md 3 状態パーサ（auto-updater の土台）
- `.claude-plugin/skills/spec-implement/SKILL.md:143-` Task Cycle（parallel-worker / review-worker 等の既存委任）
- `.claude-plugin/skills/log-implementation/SKILL.md:65-75`: reviewProcess JSON スキーマ
- `.claude-plugin/hooks/hooks.json`: 既存 hook 登録パターン

## 付録 B. session lockfile スキーマ案

`.spec-workflow/.implement-session.json`:

```json
{
  "specName": "user-auth",
  "taskId": "2.1",
  "sessionId": "uuid-…",
  "startedAt": "2026-04-19T…Z",
  "pid": 12345,
  "currentStep": "green-code",
  "attempt": 1
}
```

- skill 入口で作成、COMPLETE 時削除
- hook はこのファイルの存在で「spec-implement セッション中」を判定
- sessionId は checkpoint tag prefix にも使用可能（衝突回避）
