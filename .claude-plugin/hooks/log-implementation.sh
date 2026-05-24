#!/usr/bin/env bash
# log-implementation.sh
#
# Stop hook: 実装セッション中にタスクが [x] にマークされた直後、該当タスクの
# task log に Completion sections (## Summary / ## Statistics / ## Files Modified /
# ## Files Created / ## Artifacts / ## Review Process) が未追記なら、
# **スケルトンの completion sections を append** する。
#
# 目的: /log-implementation skill の呼び忘れ防止（安全網）。
#   - Skill: 主機能。artifact / integration 等の構造化情報を LLM が記録する
#   - Hook: 安全網。最低限のスケルトン（summary=(auto-logged)、artifact 空）のみ
#
# 動作:
#   - 実装セッション中（.implement-session.json 存在）のみ動作
#   - tasks.md から [x] にマークされた current task を検出
#   - .spec-workflow/specs/{spec_id}/task-logs/{taskId}.log.md (task-log-format.md TL2 準拠) を対象に append
#   - 既に ## Summary section があれば idempotent (no-op)
#
# 注意:
#   - 既存 completion sections を上書きしない（idempotent）
#   - 非ブロッキング（常に exit 0）。失敗しても完了を妨げない

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_FILE="${PROJECT_DIR}/.implement-session.json"

# 実装セッション中でなければ何もしない（dormant）
if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

SPEC_ID=$(jq -r '.spec_id // empty' "$SESSION_FILE" 2>/dev/null || echo '')
CURRENT_TASK=$(jq -r '.current_task // empty' "$SESSION_FILE" 2>/dev/null || echo '')

if [ -z "$SPEC_ID" ] || [ -z "$CURRENT_TASK" ]; then
  exit 0
fi

SPEC_DIR="${PROJECT_DIR}/.spec-workflow/specs/${SPEC_ID}"
TASKS_FILE="${SPEC_DIR}/tasks.md"
TASK_LOGS_DIR="${SPEC_DIR}/task-logs"

if [ ! -f "$TASKS_FILE" ]; then
  exit 0
fi

# 現在のタスクが [x] になっているか確認
# 許容フォーマット: `- [x] 1.2` / `- [x] **1.2**` / `- [x] 1.2.3 タイトル`
if ! grep -qE "^\s*-\s*\[x\]\s*\**${CURRENT_TASK}(\b|\**)" "$TASKS_FILE" 2>/dev/null; then
  exit 0
fi

# task log file path (taskId を verbatim で使用、サニタイズなし)
TASK_LOG_FILE="${TASK_LOGS_DIR}/${CURRENT_TASK}.log.md"

mkdir -p "$TASK_LOGS_DIR"

TIMESTAMP_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Log ID (UUID) の生成 (task log が無い場合の Metadata 用)
if command -v uuidgen >/dev/null 2>&1; then
  LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')
elif [ -r /proc/sys/kernel/random/uuid ]; then
  LOG_ID=$(cat /proc/sys/kernel/random/uuid)
else
  LOG_ID=$(printf "%08x-%04x-%04x-%04x-%012x" "$RANDOM$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM$RANDOM")
fi

# task log が存在しない場合: header + ## Metadata + 空 ## Events を作成
if [ ! -f "$TASK_LOG_FILE" ]; then
  cat > "$TASK_LOG_FILE" <<EOF
# Task Log: ${CURRENT_TASK}

## Metadata
- spec: ${SPEC_ID}
- task-id: ${CURRENT_TASK}
- created: ${TIMESTAMP_ISO}
- log-id: ${LOG_ID}

## Events

EOF
fi

# 既に ## Summary section があれば skill が既に動いている → idempotent (no-op)
if grep -qE "^## Summary\b" "$TASK_LOG_FILE" 2>/dev/null; then
  exit 0
fi

# git 情報の取得
cd "$PROJECT_DIR"
LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo '(no commit)')
STAT_LINES=$(git diff HEAD~1 HEAD --shortstat 2>/dev/null | head -1 || echo '')
LINES_ADDED=$(echo "$STAT_LINES" | grep -oE '[0-9]+ insertions?' | grep -oE '[0-9]+' || echo 0)
LINES_REMOVED=$(echo "$STAT_LINES" | grep -oE '[0-9]+ deletions?' | grep -oE '[0-9]+' || echo 0)
FILES_CHANGED=$(git diff HEAD~1 HEAD --name-only 2>/dev/null | wc -l || echo 0)
FILES_MODIFIED=$(git diff HEAD~1 HEAD --name-only --diff-filter=M 2>/dev/null | sed 's/^/- /' || true)
FILES_CREATED=$(git diff HEAD~1 HEAD --name-only --diff-filter=A 2>/dev/null | sed 's/^/- /' || true)

if [ -z "$FILES_MODIFIED" ]; then FILES_MODIFIED='_No files modified_'; fi
if [ -z "$FILES_CREATED" ]; then FILES_CREATED='_No files created_'; fi

# Append completion sections to the task log
cat >> "$TASK_LOG_FILE" <<EOF

## Summary

(auto-logged by hook — please enrich via /log-implementation)

## Statistics

- Lines Added: +${LINES_ADDED}
- Lines Removed: -${LINES_REMOVED}
- Files Changed: ${FILES_CHANGED}
- Net Change: $((LINES_ADDED - LINES_REMOVED))

## Files Modified
${FILES_MODIFIED}

## Files Created
${FILES_CREATED}

## Artifacts

_No artifacts recorded (auto-logged skeleton — enrich via /log-implementation)_

## Review Process

\`\`\`json
{"reworkCount": 0, "reviewOutcome": "commit", "findings": []}
\`\`\`

---

_Reference commit: ${LAST_COMMIT}_
EOF

echo "auto-appended completion sections: ${TASK_LOG_FILE}"
exit 0
