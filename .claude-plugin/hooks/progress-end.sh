#!/usr/bin/env bash
# spec-implement セッション中の Task 呼び出し完了時に END イベントを記録する PostToolUse フック。
# - セッションファイルが無い場合は素通し
# - <spec-step> タグが取れない場合は警告のみ (BEGIN 側で既にブロック済の想定)
# - .tool_response.status を END の meta に載せる
#
# 参照: .claude/_docs/plans/step-resume-mechanism.md §4.5, §5.1

set -uo pipefail

INPUT=$(cat)

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD"
fi

SESSION_FILE=".spec-workflow/.implement-session.json"
if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
if [ "$TOOL_NAME" != "Agent" ] && [ "$TOOL_NAME" != "Task" ]; then
  exit 0
fi

PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // ""' 2>/dev/null || true)

TAG=$(printf '%s' "$PROMPT" | grep -oE '<spec-step[^>]*>' | head -n 1 || true)
if [ -z "$TAG" ]; then
  # BEGIN 側で既にブロック済のはずだが、防御的に素通し
  exit 0
fi

extract_attr() {
  local name="$1"
  printf '%s' "$TAG" | grep -oE "${name}=\"[^\"]*\"" | head -n 1 | sed -E 's/^[^"]*"([^"]*)".*$/\1/' || true
}

SPEC=$(extract_attr spec)
TASK=$(extract_attr task)
STEP=$(extract_attr step)

if [ -z "$SPEC" ] || [ -z "$TASK" ] || [ -z "$STEP" ]; then
  exit 0
fi

SANITIZED_TASK=$(printf '%s' "$TASK" | tr './' '--')
PROGRESS_FILE=".spec-workflow/specs/${SPEC}/Implementation Logs/task-${SANITIZED_TASK}_progress.md"

if [ ! -f "$PROGRESS_FILE" ]; then
  # BEGIN が書かれていない → 不整合だが後続で問題にせず素通し
  exit 0
fi

STATUS=$(printf '%s' "$INPUT" | jq -r '.tool_response.status // "unknown"' 2>/dev/null || printf 'unknown')
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.tool_response.agentId // ""' 2>/dev/null || true)
DURATION_MS=$(printf '%s' "$INPUT" | jq -r '.tool_response.totalDurationMs // 0' 2>/dev/null || printf '0')

META=$(jq -cn \
  --arg status "$STATUS" \
  --arg agent_id "$AGENT_ID" \
  --argjson duration_ms "${DURATION_MS:-0}" \
  '{status: $status, agent_id: $agent_id, duration_ms: $duration_ms}' 2>/dev/null || printf '{}')

TS=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
printf '%s\tEND\t%s\t%s\n' "$TS" "$STEP" "$META" >> "$PROGRESS_FILE"

exit 0
