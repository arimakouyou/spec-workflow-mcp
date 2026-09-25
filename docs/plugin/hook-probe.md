# hook 入力の実測(v2 再設計 B0)

guard-agent.sh / record-subagent.sh / guard-git.sh が前提にする hook 入力を、Claude Code 2.1.281 で実測した結果。

## 測定方法

- 全イベントの stdin JSON を記録するプローブ用プラグインを `--plugin-dir` で読み込み、`claude -p --model haiku` で実行した。
- メインセッションで `echo main-probe` を実行したあと、Agent ツールでプラグイン agent `probe:probe-agent` を起動し、その中で `echo sub-probe` を実行した。
- Bash の PreToolUse は `hookSpecificOutput.additionalContext` を返す。
- SubagentStop は初回だけ exit 2 で止め、「`echo continued-after-block` を実行して CONTINUED と答えよ」と stderr に書く。

## 結果

| 確認項目 | 結果 | v2 で使う箇所 |
|---|---|---|
| サブエージェントを起動するツールの名前 | PreToolUse の `tool_name` は `Agent`。`tool_input` のキーは `description` / `prompt` / `subagent_type` | guard-agent.sh の matcher は `Agent` |
| プラグイン agent の `subagent_type` / `agent_type` | どちらも `probe:probe-agent`(`<plugin>:<agent>` 形式) | guard-agent.sh と guard-git.sh は `spec-workflow-mcp:review-worker` などの完全名で照合する |
| hook が主体を識別できるか | サブエージェント内で発火した PreToolUse / PostToolUse には `agent_id` と `agent_type` が入る。メインセッションの hook には入らない | 「メインエージェントか / どの agent か」の判定 |
| SubagentStart / SubagentStop の入力 | `agent_id`、`agent_type`、`agent_transcript_path`、`last_assistant_message`(SubagentStop)、`stop_hook_active` | record-subagent.sh は `last_assistant_message` の末尾 JSON を runs/ に記録する |
| SubagentStop の exit 2 によるブロック | 効く。サブエージェントは作業を続け(`echo continued-after-block` を実行)、2 回目の SubagentStop では `stop_hook_active: true`、`last_assistant_message: "CONTINUED"` | 出力契約(末尾 JSON)が欠けていればブロックして出し直させる。`stop_hook_active` が true なら二重ブロックしない |
| PreToolUse の `additionalContext` | モデルに届く。メインエージェントは注入したトークン `zebra42` をそのまま答えた | 必要なら PreToolUse から文脈を注入できる(素の stdout は届かない) |
| **Agent ツールは既定で非同期** | PostToolUse(Agent) は起動直後に発火し、`tool_response` は `{"isAsync": true, "status": "async_launched", "agentId": …}`。メインの Stop はサブエージェントの実行中に一度発火している | **エージェントロックは PostToolUse(Agent) ではなく SubagentStop で解除する**。オーケストレーターは完了通知を待ってから次のステップに進む |

## 認証

`claude -p` の初期化イベントは `apiKeySource: "none"` だった。認証用の環境変数は設定されておらず、`~/.claude/.credentials.json` のログイン情報(OAuth)で動作している。
