#!/usr/bin/env bash
# _wrap.sh
#
# 全 Hook を呼び出すラッパー。所要時間 / exit code / stdout preview を
# .implement-session/metrics.jsonl に記録する。
#
# 副作用への配慮:
#   - stdout のみ capture (Claude に注入される対象)
#   - stderr はそのまま流す (log)
#   - exit code は元 Hook を尊重
#   - 計測失敗が Hook 動作を壊さないよう || true で fail-safe
#   - .implement-session/ が無い環境では silent skip (spec 外でも壊れない)
#
# 使い方 (hooks.json から):
#   "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/_wrap.sh\" \"${CLAUDE_PLUGIN_ROOT}/hooks/<original>.sh\""
#
# 関連: .claude/_docs/plans/measurement-framework.md

set -uo pipefail

HOOK_PATH="${1:-}"
if [ -z "$HOOK_PATH" ] || [ ! -f "$HOOK_PATH" ]; then
  echo "_wrap.sh: hook path missing or not found: $HOOK_PATH" >&2
  exit 0
fi

HOOK_NAME=$(basename "$HOOK_PATH" .sh)

# stdin を保存 (元 Hook にも渡す必要がある)
INPUT=$(cat)
START=$(date +%s%N 2>/dev/null || echo 0)

# stderr を保持しつつ stdout のみ capture
# 3>&2 で fd 3 を stderr に向け、元 Hook の 2>&3 で stderr が元の stderr に流れるようにする
exec 3>&2
set +e
OUTPUT=$(printf '%s' "$INPUT" | bash "$HOOK_PATH" 2>&3)
EXIT_CODE=$?
set -e
exec 3>&-

END=$(date +%s%N 2>/dev/null || echo 0)
if [ "$START" != "0" ] && [ "$END" != "0" ]; then
  DURATION_MS=$(( (END - START) / 1000000 ))
else
  DURATION_MS=0
fi

# stdout を Claude に返す (元 Hook の出力をそのまま)
printf '%s' "$OUTPUT"

# === 計測記録 (失敗してもメインフローに影響しないよう全て || true) ===
{
  if command -v jq >/dev/null 2>&1; then
    METRICS_DIR=".implement-session"
    if [ -d "$METRICS_DIR" ] || mkdir -p "$METRICS_DIR" 2>/dev/null; then
      PREVIEW=$(printf '%s' "$OUTPUT" | head -c 200)
      jq -nc \
        --arg event "hook" \
        --arg hook "$HOOK_NAME" \
        --argjson duration "$DURATION_MS" \
        --argjson exit_code "$EXIT_CODE" \
        --arg preview "$PREVIEW" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{event:$event, hook:$hook, duration_ms:$duration, exit_code:$exit_code, preview:$preview, ts:$ts}' \
        >> "$METRICS_DIR/metrics.jsonl" 2>/dev/null
    fi
  fi
} 2>/dev/null || true

exit $EXIT_CODE
