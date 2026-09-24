#!/usr/bin/env bash
# SubagentStop: 実装系 agent の最終メッセージ末尾の JSON を runs/<task>/<role>.json に記録し、直列ロックを解除する。
# JSON が無い・壊れているときは exit 2 で agent に出し直させる(stop_hook_active のときは二重にブロックしない)。
set -uo pipefail

input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
active="$root/.spec-workflow/.active"
lock="$root/.spec-workflow/.agent-lock"
[[ -f "$active" ]] || exit 0

name="$(jq -r '.agent_type // empty' <<<"$input")"; name="${name##*:}"
case "$name" in
  impl-worker|integ-test-worker) role=impl ;;
  unit-test-engineer|frontend-test-engineer|integ-test-auditor) role=verify ;;
  review-worker) role=review ;;
  *) exit 0 ;;
esac

msg="$(jq -r '.last_assistant_message // empty' <<<"$input")"
json="$(awk '/^```json[[:space:]]*$/ { buf = ""; inb = 1; next } inb && /^```[[:space:]]*$/ { last = buf; inb = 0; next } inb { buf = buf $0 "\n" } END { printf "%s", last }' <<<"$msg")"
active_stop="$(jq -r '.stop_hook_active // false' <<<"$input")"

if ! jq -e '.task | type == "string"' <<<"$json" >/dev/null 2>&1; then
  if [[ "$active_stop" != true ]]; then
    echo "record-subagent: 最終メッセージの末尾に、task を含む JSON ブロック(\`\`\`json … \`\`\`)を書いて終える" >&2
    exit 2
  fi
  rm -f "$lock"
  exit 0
fi

spec="$(tr -d '[:space:]' < "$active")"
task="$(jq -r .task <<<"$json")"
dir="$root/.spec-workflow/specs/$spec/runs/$task"
mkdir -p "$dir"
jq . <<<"$json" > "$dir/$role.json"
jq -c --arg role "$role" --arg agent "$name" --arg at "$(date -u +%FT%TZ)" '. + {role: $role, agent: $agent, at: $at}' <<<"$json" >> "$dir/history.jsonl"
rm -f "$lock"
exit 0
