#!/usr/bin/env bash
# timing-logger-pre.sh
#
# PreToolUse: Tool 開始時刻を一時ファイルに保存。timing-logger-post.sh で
# 終了時刻と組み合わせて duration を計算し、metrics.jsonl に記録する。
#
# 副作用への配慮:
#   - 一時ファイルは tool_use_id 単位でユニーク化 (並列起動安全)
#   - 失敗時も silent exit (副作用ゼロ)
#
# 関連: .claude/_docs/plans/measurement-framework.md

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)

# tool_name と tool_use_id を取得
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo '')
TOOL_USE_ID=$(printf '%s' "$INPUT" | jq -r '.tool_use_id // empty' 2>/dev/null || echo '')

# tool_use_id がない場合は session_id + tool 名で代替
if [ -z "$TOOL_USE_ID" ]; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo 'unknown')
  TOOL_USE_ID="${SESSION_ID}-${TOOL}-$$"
fi

[ -z "$TOOL" ] && exit 0

# 開始時刻を保存
TIMING_DIR="/tmp/claude-timing"
mkdir -p "$TIMING_DIR" 2>/dev/null || exit 0
date +%s%N > "$TIMING_DIR/${TOOL_USE_ID}.start" 2>/dev/null || true

exit 0
