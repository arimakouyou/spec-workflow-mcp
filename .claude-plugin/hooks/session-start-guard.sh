#!/usr/bin/env bash
# spec-implement セッションが前回中断したまま (lockfile 残存) の状態で
# 新セッションが開始された場合、LLM に資源状況を提示するための
# SessionStart フック。
# - 非ブロッキング: 常に exit 0
# - lockfile が無ければ何もしない
# - lockfile があり git tree が dirty なら警告 + 修復コマンド提示
# - lockfile が古い (7 日超) なら放置フラグと cleanup 指示を提示
#
# 参照: .claude/_docs/plans/step-resume-mechanism.md §4.7, §8.4

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

SPEC_NAME=$(jq -r '.specName // ""' < "$SESSION_FILE" 2>/dev/null || true)
TASK_ID=$(jq -r '.taskId // ""' < "$SESSION_FILE" 2>/dev/null || true)
STARTED_AT=$(jq -r '.startedAt // ""' < "$SESSION_FILE" 2>/dev/null || true)

{
  echo "🔁 [spec-implement] 前回セッションの lockfile が残っています:"
  echo "   spec=${SPEC_NAME:-<unknown>} task=${TASK_ID:-<unknown>} startedAt=${STARTED_AT:-<unknown>}"
  echo ""
}

# 古さ判定 (best-effort)
if [ -n "$STARTED_AT" ]; then
  STARTED_EPOCH=$(date -u -d "$STARTED_AT" +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date -u +%s)
  if [ "$STARTED_EPOCH" -gt 0 ]; then
    AGE_SEC=$((NOW_EPOCH - STARTED_EPOCH))
    if [ "$AGE_SEC" -gt 604800 ]; then
      {
        echo "⚠️  lockfile が 7 日以上古いため、放置された可能性があります。"
        echo "   整理するには: rm -f $SESSION_FILE"
        echo ""
      }
    fi
  fi
fi

# dirty tree チェック
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    {
      echo "⚠️  git working tree が dirty です。"
      echo "   再開前に以下のいずれかで状態を整えてください:"
      echo "     - git stash"
      echo "     - git commit -am \"wip\""
      echo "     - 前回 checkpoint へ reset: scripts/reset-to-checkpoint.ts (spec=${SPEC_NAME} task=${TASK_ID})"
      echo ""
    }
  fi
fi

{
  echo "📖 再開手順は /spec-resume skill または"
  echo "   .spec-workflow/specs/${SPEC_NAME}/Implementation Logs/ 配下の progress.md を確認してください。"
}

exit 0
