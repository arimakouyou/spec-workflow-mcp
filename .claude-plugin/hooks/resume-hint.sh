#!/usr/bin/env bash
# resume-hint.sh
#
# SessionStart hook: セッションファイル（.implement-session.json）と lockfile を
# 読んで再開状況を context 先頭に注入する。Orchestrator が即座に状況把握できる
# ようにする。
#
# トリガ: .implement-session.json が存在する場合のみ動作。
# Orchestrator が同ファイルを書き出すまでは dormant 状態で no-op。
#
# 注意:
#   - セッションファイルの phase を信用しすぎない（レートリミット等で書き換え前に
#     落ちた可能性がある）
#   - 真の状態は git の実状態。セッションファイルは「当たりを付けるヒント」

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_FILE="${PROJECT_DIR}/.implement-session.json"
LOCKFILE="${PROJECT_DIR}/.implement-session.lock"

# 実装セッション無しならスキップ（通常起動）
if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

IS_ACTIVE="no"
[ -f "$LOCKFILE" ] && IS_ACTIVE="yes"

SPEC_ID=$(jq -r '.spec_id // "unknown"' "$SESSION_FILE" 2>/dev/null)
CURRENT_TASK=$(jq -r '.current_task // "unknown"' "$SESSION_FILE" 2>/dev/null)
CURRENT_PHASE=$(jq -r '.current_phase // "unknown"' "$SESSION_FILE" 2>/dev/null)
PHASE_STARTED=$(jq -r '.phase_started_at // "unknown"' "$SESSION_FILE" 2>/dev/null)
LAST_FAILURE=$(jq -r '.last_failure_category // "none"' "$SESSION_FILE" 2>/dev/null)
RETRY_COUNT=$(jq -r '.retry_count // 0' "$SESSION_FILE" 2>/dev/null)
RATE_LIMIT_HIT=$(jq -r '.rate_limit_state.hit_at // "never"' "$SESSION_FILE" 2>/dev/null)

cd "$PROJECT_DIR"
GIT_STATUS=$(git status --short 2>/dev/null | head -20 || echo "(git status unavailable)")
GIT_LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "(no commits)")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(no branch)")

TOUCHED_FILES=$(jq -r '.phase_checkpoint.green_files_touched[]? // empty' "$SESSION_FILE" 2>/dev/null | head -10)

cat <<EOF
<session_resume_context>
前回の実装セッションが存在します。以下の状況から再開してください。

## セッション状態
- Spec ID: ${SPEC_ID}
- Active: ${IS_ACTIVE}  (no なら前回は完了 or クラッシュ)
- Current Task: ${CURRENT_TASK}
- Current Phase: ${CURRENT_PHASE}  (phase started: ${PHASE_STARTED})
- Last Failure: ${LAST_FAILURE}  (retry_count: ${RETRY_COUNT})
- Rate Limit Hit: ${RATE_LIMIT_HIT}

## Git 実状態（真のソース）
- Branch: ${GIT_BRANCH}
- Last Commit: ${GIT_LAST_COMMIT}
- Uncommitted Changes:
\`\`\`
${GIT_STATUS}
\`\`\`

## 直近 Touched Files (checkpoint より)
$(echo "$TOUCHED_FILES" | sed 's/^/- /')

## 再開プロトコル

1. lockfile が生きていれば再開モード、無ければ通常起動
2. 上記 Current Task / Phase を参考にしつつ、**git 実状態を真のソース**として扱う
3. セッションファイルの phase と git 状態が不一致なら git 側を信用
4. 該当 phase の Implementer / Reviewer を起動
5. Rate Limit で中断していた場合は retry_count を加算せずそのまま続行
</session_resume_context>
EOF

exit 0
