#!/usr/bin/env bash
# auto-verify-spec.sh
#
# PostToolUse (Edit|Write on spec files): spec ファイルが編集されたとき、
# 整合性の軽量チェックを自動実行し、必要なら /spec-verify の明示呼出を促す。
#
# 動作:
#   - 編集対象が .spec-workflow/specs/{spec_id}/*.md かを判定
#   - frontmatter の spec_id 不整合、上流/下流 ID 参照の dangling、下流波及を検出
#   - warning のみ（ブロックはしない）
#
# 本格的な整合性検査は /spec-verify スキルに委譲。この hook は「呼び忘れ防止」の
# 軽量な補助役。

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

case "$FILE_PATH" in
  */.spec-workflow/specs/*/requirements.md| \
  */.spec-workflow/specs/*/design.md| \
  */.spec-workflow/specs/*/test-design.md| \
  */.spec-workflow/specs/*/tasks.md) ;;
  *) exit 0 ;;
esac

SPEC_DIR=$(dirname "$FILE_PATH")
SPEC_ID=$(basename "$SPEC_DIR")
CHANGED_FILE=$(basename "$FILE_PATH")

WARNINGS=""

# 1. frontmatter の spec_id 整合性
ACTUAL_SPEC_ID=$(awk '/^---$/{c++} c==1 && /^spec_id:/{sub(/^spec_id: */, ""); print; exit}' "$FILE_PATH" 2>/dev/null || echo '')
if [ -n "$ACTUAL_SPEC_ID" ] && [ "$ACTUAL_SPEC_ID" != "$SPEC_ID" ]; then
  WARNINGS+="- frontmatter の spec_id (\`${ACTUAL_SPEC_ID}\`) がディレクトリ名 (\`${SPEC_ID}\`) と不一致\n"
fi

# 2. requirements.md の REQ-N が test-design.md で未参照
if [ "$CHANGED_FILE" = "requirements.md" ] && [ -f "${SPEC_DIR}/test-design.md" ]; then
  REQS=$(grep -oE "REQ-[0-9]+" "$FILE_PATH" 2>/dev/null | sort -u || echo '')
  for REQ in $REQS; do
    if ! grep -qF "$REQ" "${SPEC_DIR}/test-design.md"; then
      WARNINGS+="- requirements.md の ${REQ} が test-design.md に未登場\n"
    fi
  done
fi

# 3. 下流ファイルへの波及提示
DOWNSTREAM=""
case "$CHANGED_FILE" in
  requirements.md) DOWNSTREAM="design.md, test-design.md, tasks.md" ;;
  design.md)       DOWNSTREAM="test-design.md, tasks.md" ;;
  test-design.md)  DOWNSTREAM="tasks.md" ;;
esac

if [ -n "$DOWNSTREAM" ]; then
  WARNINGS+="- ${CHANGED_FILE} の変更は下流（${DOWNSTREAM}）への波及確認が必要\n"
fi

if [ -z "$WARNINGS" ]; then
  exit 0
fi

cat <<EOF
<spec_verify_warnings>
${CHANGED_FILE} の編集により、以下の整合性確認が必要です:

$(printf "%b" "$WARNINGS")
詳細な検査が必要なら /spec-verify ${SPEC_ID} を実行してください。
</spec_verify_warnings>
EOF

exit 0
