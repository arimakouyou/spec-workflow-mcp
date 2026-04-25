#!/usr/bin/env bash
# arch-test-regen-hint.sh
#
# PostToolUse (Edit|Write on design.md):
# `## Module Boundaries` セクションを含む design.md が編集された時、
# `tests/architecture.rs` の存在と鮮度を確認し、再生成を促す warning を出す。
#
# 動作:
#   - 編集対象が `.spec-workflow/specs/*/design.md` かを判定
#   - design.md に `## Module Boundaries` セクションが無ければ silent exit
#   - tests/architecture.rs の状態を確認:
#     - 存在しない → 初回生成を促す warning
#     - design.md より古い (mtime 比較) → 再生成を促す warning
#   - warning のみ、block しない
#
# 関連:
#   - /generate-arch-tests Skill (テスト生成)
#   - .claude-plugin/rules/enforcement-levels.md (依存方向 / 循環依存の L4 構造テスト)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')
[ -z "$FILE_PATH" ] && exit 0

# 対象: .spec-workflow/specs/*/design.md のみ
case "$FILE_PATH" in
  */.spec-workflow/specs/*/design.md) ;;
  *) exit 0 ;;
esac

# Module Boundaries セクションが design.md に含まれるか確認
# (含まれない場合は arch test 不要のプロジェクトと判断して silent exit)
if ! grep -qE "^## Module Boundaries" "$FILE_PATH" 2>/dev/null; then
  exit 0
fi

ARCH_TEST="tests/architecture.rs"
WARNINGS=""

if [ ! -f "$ARCH_TEST" ]; then
  WARNINGS="- \`${ARCH_TEST}\` が未生成です。design.md の Module Boundaries に基づく arch test を生成するため \`/generate-arch-tests\` を実行してください"
elif [ "$FILE_PATH" -nt "$ARCH_TEST" ]; then
  # design.md が arch test より新しい (Module Boundaries が変更された可能性)
  WARNINGS="- \`${ARCH_TEST}\` が古い可能性があります (design.md の mtime が新しい)。\`/generate-arch-tests\` で再生成を検討してください"
fi

[ -z "$WARNINGS" ] && exit 0

cat <<EOF
<arch_test_regen_hint>
design.md (Module Boundaries 含む) が変更されました:

${WARNINGS}

依存方向違反 / 循環依存を検出する arch test (L4 構造テスト) を最新状態に保つため、
設計変更時の再生成を推奨します。本 hook は warning のみ、ブロックはしません。
</arch_test_regen_hint>
EOF

exit 0
