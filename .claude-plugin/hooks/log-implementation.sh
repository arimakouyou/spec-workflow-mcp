#!/usr/bin/env bash
# log-implementation.sh
#
# Stop hook: 実装セッション中にタスクが [x] にマークされた直後、該当タスクの
# Implementation Log が未作成なら**スケルトンログ**を自動生成する。
#
# 目的: /log-implementation skill の呼び忘れ防止（安全網）。
#   - Skill: 主機能。artifact / integration 等の構造化情報を LLM が記録する
#   - Hook: 安全網。最低限のスケルトン（summary=(auto-logged)、artifact 空）のみ
#
# 動作:
#   - 実装セッション中（.implement-session.json 存在）のみ動作
#   - tasks.md から最初の [x] タスク（かつ該当ログ未作成）を検出
#   - .spec-workflow/specs/{spec_id}/Implementation Logs/ にスケルトン生成
#   - 詳細は LLM が後から /log-implementation で追記可能
#
# 注意:
#   - Skill の詳細ログを上書きしない（既存ログがあれば何もしない）
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
LOGS_DIR="${SPEC_DIR}/Implementation Logs"

if [ ! -f "$TASKS_FILE" ]; then
  exit 0
fi

# 現在のタスクが [x] になっているか確認
# 許容フォーマット: `- [x] 1.2` / `- [x] **1.2**` / `- [x] 1.2.3 タイトル`
if ! grep -qE "^\s*-\s*\[x\]\s*\**${CURRENT_TASK}(\b|\**)" "$TASKS_FILE" 2>/dev/null; then
  exit 0
fi

SANITIZED_TASK_ID=$(echo "$CURRENT_TASK" | tr './' '--')

# 既存ログがあればスキップ（Skill が詳細記録済みの可能性）
if compgen -G "${LOGS_DIR}/task-${SANITIZED_TASK_ID}_*.md" > /dev/null 2>&1; then
  exit 0
fi

mkdir -p "$LOGS_DIR"

TIMESTAMP_FS=$(date -u +%Y%m%dT%H%M%S)
TIMESTAMP_ISO=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# Log ID (UUID) の生成
if command -v uuidgen >/dev/null 2>&1; then
  LOG_ID=$(uuidgen | tr 'A-Z' 'a-z')
elif [ -r /proc/sys/kernel/random/uuid ]; then
  LOG_ID=$(cat /proc/sys/kernel/random/uuid)
else
  # fallback: 時刻ベースの疑似 UUID
  LOG_ID=$(printf "%08x-%04x-%04x-%04x-%012x" "$RANDOM$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM$RANDOM")
fi
ID_PREFIX=$(echo "$LOG_ID" | cut -c1-8)

LOG_FILE="${LOGS_DIR}/task-${SANITIZED_TASK_ID}_${TIMESTAMP_FS}_${ID_PREFIX}.md"

# git 情報の取得
cd "$PROJECT_DIR"
LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo '(no commit)')
STAT_LINES=$(git diff HEAD~1 HEAD --shortstat 2>/dev/null | head -1 || echo '')
LINES_ADDED=$(echo "$STAT_LINES" | grep -oE '[0-9]+ insertions?' | grep -oE '[0-9]+' || echo 0)
LINES_REMOVED=$(echo "$STAT_LINES" | grep -oE '[0-9]+ deletions?' | grep -oE '[0-9]+' || echo 0)
FILES_CHANGED=$(git diff HEAD~1 HEAD --name-only 2>/dev/null | wc -l || echo 0)

cat > "$LOG_FILE" <<EOF
# Implementation Log: Task ${CURRENT_TASK}

**Summary:** (auto-logged by hook — please enrich via /log-implementation)

**Timestamp:** ${TIMESTAMP_ISO}
**Log ID:** ${LOG_ID}

---

## Statistics

- **Lines Added:** +${LINES_ADDED}
- **Lines Removed:** -${LINES_REMOVED}
- **Files Changed:** ${FILES_CHANGED}
- **Net Change:** $((LINES_ADDED - LINES_REMOVED))

## Files Modified

$(git diff HEAD~1 HEAD --name-only --diff-filter=M 2>/dev/null | sed 's/^/- /' || echo '_No files modified_')

## Files Created

$(git diff HEAD~1 HEAD --name-only --diff-filter=A 2>/dev/null | sed 's/^/- /' || echo '_No files created_')

---

## Artifacts

_No artifacts recorded (auto-logged skeleton — enrich via /log-implementation)_

---

## Review Process

\`\`\`json
{"reworkCount": 0, "reviewOutcome": "commit", "findings": []}
\`\`\`

---

_Reference commit: ${LAST_COMMIT}_
EOF

echo "auto-logged: ${LOG_FILE}"
exit 0
