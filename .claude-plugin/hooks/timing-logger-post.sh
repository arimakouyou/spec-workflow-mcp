#!/usr/bin/env bash
# timing-logger-post.sh
#
# PostToolUse: timing-logger-pre.sh が記録した開始時刻と組み合わせて
# Tool 所要時間を metrics.jsonl に記録する。
# 加えて、Read 対象が `.claude-plugin/rules/*.md` の場合は rule_read イベント
# も記録 (Rule 計測の Layer A)。
#
# 副作用への配慮:
#   - 計測失敗時は silent exit (副作用ゼロ)
#   - .implement-session/ が無い環境でも壊れない
#
# 関連: .claude/_docs/plans/measurement-framework.md

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo '')
TOOL_USE_ID=$(printf '%s' "$INPUT" | jq -r '.tool_use_id // empty' 2>/dev/null || echo '')

if [ -z "$TOOL_USE_ID" ]; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo 'unknown')
  TOOL_USE_ID="${SESSION_ID}-${TOOL}-$$"
fi

[ -z "$TOOL" ] && exit 0

TIMING_DIR="/tmp/claude-timing"
START_FILE="$TIMING_DIR/${TOOL_USE_ID}.start"

DURATION_MS=0
if [ -f "$START_FILE" ]; then
  T1=$(cat "$START_FILE" 2>/dev/null || echo 0)
  T2=$(date +%s%N 2>/dev/null || echo 0)
  if [ "$T1" != "0" ] && [ "$T2" != "0" ]; then
    DURATION_MS=$(( (T2 - T1) / 1000000 ))
  fi
  rm -f "$START_FILE" 2>/dev/null || true
fi

# === metrics 記録 (失敗してもメインフローに影響しないよう全て || true) ===
{
  METRICS_DIR=".implement-session"
  if [ ! -d "$METRICS_DIR" ]; then
    mkdir -p "$METRICS_DIR" 2>/dev/null || exit 0
  fi

  # tool_input から cmd_summary を抽出 (先頭 100 文字)
  CMD=$(printf '%s' "$INPUT" \
    | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.path // empty' 2>/dev/null \
    | head -c 100)

  jq -nc \
    --arg event "tool" \
    --arg tool "$TOOL" \
    --arg cmd "$CMD" \
    --argjson duration "$DURATION_MS" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{event:$event, tool:$tool, cmd_summary:$cmd, duration_ms:$duration, ts:$ts}' \
    >> "$METRICS_DIR/metrics.jsonl" 2>/dev/null

  # === Rule 読み込み検出 (Read tool で .claude-plugin/rules/*.md が読まれた場合) ===
  if [ "$TOOL" = "Read" ]; then
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')
    case "$FILE_PATH" in
      *.claude-plugin/rules/*.md)
        RULE_NAME=$(basename "$FILE_PATH" .md)
        jq -nc \
          --arg event "rule_read" \
          --arg rule "$RULE_NAME" \
          --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '{event:$event, rule:$rule, ts:$ts}' \
          >> "$METRICS_DIR/metrics.jsonl" 2>/dev/null
        ;;
    esac
  fi
} 2>/dev/null || true

exit 0
