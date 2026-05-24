#!/usr/bin/env bash
# inject-spec.sh
#
# UserPromptSubmit hook: 実装セッション中の spec.md を context 先頭に強制注入する。
# 「仕様を読まないで進める」問題への構造防御。
#
# 動作:
#   - .implement-session.json から current spec_id / current_task / current_phase を取得
#   - .spec-workflow/specs/{spec_id}/*.md を全て stdout に出力
#   - Claude Code は UserPromptSubmit hook の stdout を context 先頭に配置する
#
# トリガ: .implement-session.json が存在する場合のみ動作（実装セッション中のみ）。
# Orchestrator が同ファイルを書き出すまでは dormant 状態で no-op。
#
# 注意:
#   - 毎ターン注入するので AutoCompact の影響を受けない（常に先頭に来る）
#   - spec 本体は短期正本なので、重複注入のコストより読み忘れ防止の価値が大きい

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_FILE="${PROJECT_DIR}/.implement-session.json"

# 実装セッション中でなければ何もしない（現状 Orchestrator 未実装のため dormant）
if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

SPEC_ID=$(jq -r '.spec_id // empty' "$SESSION_FILE" 2>/dev/null || echo '')
if [ -z "$SPEC_ID" ]; then
  exit 0
fi

SPEC_DIR="${PROJECT_DIR}/.spec-workflow/specs/${SPEC_ID}"
if [ ! -d "$SPEC_DIR" ]; then
  exit 0
fi

CURRENT_TASK=$(jq -r '.current_task // empty' "$SESSION_FILE" 2>/dev/null || echo '')
CURRENT_PHASE=$(jq -r '.current_phase // empty' "$SESSION_FILE" 2>/dev/null || echo '')

cat <<EOF
<spec_context>
以下は現在実装中の spec の内容です。実装判断時は必ず参照してください。

Spec ID: ${SPEC_ID}
Current Task: ${CURRENT_TASK}
Current Phase: ${CURRENT_PHASE}

--- requirements.md ---
$(cat "${SPEC_DIR}/requirements.md" 2>/dev/null || echo "(not found)")

--- design.md ---
$(cat "${SPEC_DIR}/design.md" 2>/dev/null || echo "(not found)")

--- test-design.md ---
$(cat "${SPEC_DIR}/test-design.md" 2>/dev/null || echo "(not found)")

--- tasks.md ---
$(cat "${SPEC_DIR}/tasks.md" 2>/dev/null || echo "(not found)")
</spec_context>
EOF

exit 0
