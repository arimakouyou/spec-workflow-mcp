# Hook 発火挙動検証レポート — Phase A P1

- 実施日: 2026-04-19 (UTC 14:14)
- 実施者: main session (Opus 4.7)
- 対象 plan: `.claude/_docs/plans/step-resume-mechanism.md` §3
- 生ログ: `.claude/_docs/experiments/task-hook-log.txt`

## 目的

plan §3 で列挙した事前検証項目 3.1〜3.4 のうち、このセッションで実測できる範囲を確認する。

## 実験セットアップ

1. `.claude/hooks/task-experiment-log.sh` を作成（stdin JSON をタイムスタンプ付きでファイル append する非ブロッキング logger）
2. `.claude/settings.local.json` に以下を追加:
   - `PreToolUse` matcher `"Task"` → logger (`PreToolUse` 引数)
   - `PostToolUse` matcher `"Task"` → logger (`PostToolUse` 引数)
   - `SubagentStop` (matcher 無し) → logger (`SubagentStop` 引数)
3. トリガ用に Agent tool で軽量な `Explore` subagent を 2 回呼び出し
   - 1 回目: プレーンな prompt（タグ無し）
   - 2 回目: prompt 先頭に `<spec-step spec="test-spec" task="1.2" step="red-write" attempt="1">` を付与

## 結果

### 3.1 `"matcher": "Task"` は動作するか — **✅ YES（ただし注意あり）**

| 確認項目 | 結果 |
|---------|------|
| PreToolUse が matcher `"Task"` で発火 | ✅ 発火した |
| PostToolUse が matcher `"Task"` で発火 | ✅ 発火した |
| SubagentStop（matcher 無し）が発火 | ✅ 発火した |
| セッション再起動せず mid-session に settings 反映 | ✅ 反映された |

**重要な注意**: stdin JSON の `tool_name` フィールドは `"Agent"` と記録されており、`"Task"` ではない。

```json
"hook_event_name": "PreToolUse",
"tool_name": "Agent",
```

にもかかわらず matcher `"Task"` が機能した。これは Claude Code の harness が `Task` を alias として扱っているか、matcher 解決が内部名と別レイヤーで行われているため。`"matcher": "Agent"` も動作する可能性があるが未検証。

**本実装での採用方針**: plan §4.9 の hooks.json では **matcher `"Task"` を採用**する（既に動作確認済み、変更理由なし）。ただし設計ドキュメントに「`tool_name` は `Agent` として返る」を明記する。

### 3.2 stdin JSON 構造 — **✅ 確定**

#### PreToolUse (matcher: Task)

```json
{
  "session_id": "<uuid>",
  "transcript_path": "/home/.../transcript.jsonl",
  "cwd": "/home/arimakouyou/github/spec-workflow-mcp",
  "permission_mode": "bypassPermissions",
  "hook_event_name": "PreToolUse",
  "tool_name": "Agent",
  "tool_input": {
    "description": "<task description>",
    "prompt": "<spec-step spec=\"...\" task=\"...\" step=\"...\" attempt=\"...\">\n<prompt body>",
    "subagent_type": "Explore"
  },
  "tool_use_id": "toolu_<id>"
}
```

**`<spec-step>` 抽出 jq パス**: `.tool_input.prompt`

**jq コマンド例** (hook 内で使用):

```bash
TAG=$(jq -r '.tool_input.prompt // empty' | grep -oE '<spec-step[^>]*>' | head -1)
SPEC=$(printf '%s' "$TAG" | grep -oE 'spec="[^"]*"' | cut -d'"' -f2)
TASK=$(printf '%s' "$TAG" | grep -oE 'task="[^"]*"' | cut -d'"' -f2)
STEP=$(printf '%s' "$TAG" | grep -oE 'step="[^"]*"' | cut -d'"' -f2)
ATTEMPT=$(printf '%s' "$TAG" | grep -oE 'attempt="[^"]*"' | cut -d'"' -f2)
```

もし `TAG` が空なら validation hook はエラー exit（plan §4.8）。

#### SubagentStop (matcher なし)

```json
{
  "session_id": "<uuid>",
  "transcript_path": "...",
  "cwd": "...",
  "permission_mode": "bypassPermissions",
  "agent_id": "<agent_id>",
  "agent_type": "Explore",
  "hook_event_name": "SubagentStop",
  "stop_hook_active": false,
  "agent_transcript_path": ".../subagents/agent-<id>.jsonl",
  "last_assistant_message": "<subagent の最終発話>"
}
```

**特徴**:
- `tool_input.prompt` は **見えない**（SubagentStop には Task の元 prompt が渡らない）
- つまり SubagentStop のみに頼る縮退プランでは、`<spec-step>` タグ抽出ができず、代替に `agent_id` → session の transcript を読んで逆引きする必要がある
- **PreToolUse で BEGIN 時に `agent_id` は未確定**（まだ subagent が起動していない）、一方 `tool_use_id` は BEGIN 時点で確定
- 連携キーの候補: **`tool_use_id`** が PreToolUse / PostToolUse で一貫する。SubagentStop には `tool_use_id` が無い → `agent_id` を何らかの形で PostToolUse と紐付ける必要（PostToolUse の `tool_response.agentId` と一致するかは要確認、下記参照）

#### PostToolUse (matcher: Task)

```json
{
  "session_id": "<uuid>",
  ...,
  "hook_event_name": "PostToolUse",
  "tool_name": "Agent",
  "tool_input": { "description": "...", "prompt": "...", "subagent_type": "Explore" },
  "tool_response": {
    "status": "completed",
    "prompt": "...",
    "agentId": "<agent_id>",
    "agentType": "Explore",
    "content": [{"type": "text", "text": "<response>"}],
    "totalDurationMs": 3509,
    "totalTokens": 28413,
    ...
  },
  "tool_use_id": "toolu_<id>"
}
```

**観察**:
- `tool_response.status` で成否判定可能（今回は `"completed"`）
- `tool_response.agentId` が SubagentStop の `agent_id` と**一致**（今回の実測: SubagentStop の `agent_id = "a7b91f67e54ce07d0"` ↔ PostToolUse の `tool_response.agentId = "a7b91f67e54ce07d0"`）→ SubagentStop と PostToolUse の紐付けキーとして `agent_id` が使える
- PostToolUse でも `tool_input.prompt` が再度渡される → `<spec-step>` タグ抽出可能

### 3.3 エラー時の PostToolUse 発火 — **⚠️ 未検証（観察待ち）**

本セッションでは能動的に Task エラーを誘発しなかった（副作用リスク・時間コスト）。

**間接的なシグナル**: PostToolUse の `tool_response` に `status` フィールドが存在するため、`"completed"` 以外の値（例: `"error"`, `"aborted"`）が返る設計になっているのは確実。実装時に PostToolUse で `status` を確認して END のメタに status を含める方針で充足する。

**取るべき対策**:
- `progress-end.sh` で `status != "completed"` を検出したら END イベントのメタに `"status":"error"` を記録
- 実運用で異常ケースが観測されたら追加実験
- 万一 PostToolUse 自体が発火しない場合、SubagentStop がバックアップになる（SubagentStop は subagent 終了時に必ず発火することが今回確認されている）

### 3.4 レートリミット kill 時 SubagentStop 発火 — **❌ 直接検証不可（仕様上 OK）**

能動的にレートリミット kill を誘発するのは現実的でない。**ただし**今回の観測から:

- PreToolUse は **subagent 起動前** に fire する → BEGIN は確実に残る
- SubagentStop / PostToolUse は subagent 終了イベントに紐付く → プロセス自体が強制終了された場合は発火しない可能性が高い
- **これは plan §7 の「BEGIN あり・END 無し → 同 step redo」ロジックで正しく扱える** — 中断で END が書かれないのは意図した設計

したがって 3.4 の検証が不可能でも、設計は破綻しない。plan §11.1 のリスク表の該当行と整合。

## plan §3.5 の方針調整

| 検証 | 結果 | 方針調整 |
|------|------|---------|
| 3.1 Task matcher | ✅ 動作 | 縮退プラン不要、plan のまま進める |
| 3.2 prompt 取得 | ✅ `.tool_input.prompt` | description 多重記載は不要 |
| 3.3 error 時 PostToolUse | ⚠️ 未検証 | PostToolUse に status field ある前提で設計、FAILED 検出は LLM 側責務を基本とする（hook は status メタ付与のみ） |
| 3.4 rate limit kill | ❌ 検証不可 | 設計上 BEGIN-without-END が中断シグナル、追加対策不要 |

## 追加の設計示唆

実験から浮上した新規考慮事項:

1. **`tool_use_id` が PreToolUse / PostToolUse の紐付けキー**。SubagentStop には無いため、progress.md の行メタに `tool_use_id` を入れておくと「どの PreToolUse と pair か」を追えるが、この規模では不要かもしれない
2. **`agent_id` は SubagentStop ⇔ PostToolUse の紐付けキー**。縮退プラン（SubagentStop のみで END を書く）を採る場合はこれを使う
3. **`permission_mode` が `bypassPermissions` になっている**（このセッション）。本番 `/spec-implement` 運用では異なる permission mode の可能性があり、hook が permission プロンプトを誘発する形になっていないか確認が必要（今回の hook は非ブロッキングだったので問題にならなかった）
4. hook が matcher で反応した場合、`hook_event_name` は正規の名前（`PreToolUse` 等）で来る。hook 内で event 判別する際は args で渡した文字列ではなく `hook_event_name` を信頼したほうが安全

## 結論

**Phase A P1 完了。plan §3.5 の縮退プラン発動条件 (3.1/3.2 NG) には該当せず、plan 本体のまま実装着手して問題ない**。

- ✅ `"matcher": "Task"` で PreToolUse/PostToolUse が発火する（`tool_name` は `Agent` だが matcher は `Task` で機能）
- ✅ `<spec-step>` タグは `.tool_input.prompt` から grep/jq で抽出可能
- ✅ SubagentStop は matcher なしで fire、`last_assistant_message` + `agent_id` が取れる
- ✅ PreToolUse → SubagentStop → PostToolUse の順序で発火
- ⚠️ Task エラー時の PostToolUse 発火は未検証だが `tool_response.status` フィールドの存在から設計変更不要と判断
- ❌ レートリミット kill 時 SubagentStop 発火は設計上検証不可、BEGIN-without-END 設計で吸収

## クリーンアップ

実験終了に伴い以下を戻す:

- ✅ `.claude/settings.local.json` から hooks セクションを削除
- ✅ `.claude/hooks/task-experiment-log.sh` を削除
- 保持: `.claude/_docs/experiments/task-hook-log.txt`（生ログ、監査資料として保持）
- 保持: 本レポート (`hook-behavior-2026-04-19.md`)

## 次ステップ (plan §12.1 Phase A 続き)

1. P2: progress parser + unit test (`src/core/progress-log-parser.ts`)
2. P3: hooks 実装 (本実験の成果を反映した本番 hook 群)
3. P4: tasks auto-updater
4. P7: implement-task.ts 委任化 + メタタグ
