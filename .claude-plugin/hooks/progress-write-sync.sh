#!/usr/bin/env bash
# progress.md への Edit/Write を検出し、該当 spec の tasks.md を
# auto-updater で同期する PostToolUse フック。
# - Edit|Write matcher 前提、他 tool は素通し
# - 編集対象が .spec-workflow/specs/<spec>/Implementation Logs/task-*_progress.md
#   でない場合は素通し
# - 非ブロッキング (sync に失敗しても exit 0)
#
# 参照: .claude/_docs/plans/step-resume-mechanism.md §4.3 (tasks auto-updater)

set -uo pipefail

INPUT=$(cat)

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD"
fi

# Edit / Write のファイルパスを取得
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# progress.md パスか判定: .spec-workflow/specs/<spec>/Implementation Logs/task-*_progress.md
if ! printf '%s' "$FILE_PATH" | grep -qE '\.spec-workflow/specs/[^/]+/Implementation Logs/task-[^/]+_progress\.md$'; then
  exit 0
fi

SPEC_NAME=$(printf '%s' "$FILE_PATH" | sed -nE 's|.*\.spec-workflow/specs/([^/]+)/Implementation Logs/.*|\1|p')
if [ -z "$SPEC_NAME" ]; then
  exit 0
fi

# tsx ドライバが存在しなければ素通し (ビルド前の環境)
DRIVER="scripts/sync-spec-tasks.ts"
if [ ! -f "$DRIVER" ]; then
  exit 0
fi

# 非ブロッキングで実行
if command -v npx >/dev/null 2>&1; then
  npx tsx "$DRIVER" "$SPEC_NAME" >/dev/null 2>&1 || true
fi

exit 0
