#!/usr/bin/env bash
# detect-new-files.sh
#
# PostToolUse (Write): 新規作成ファイルを spec.md と照合し、言及されていない
# ファイルの作成時に warning を返す。「余計な機能を足す（スコープ逸脱）」への
# 構造防御。
#
# 動作:
#   - Write ツール実行後、対象ファイルが新規作成かを git ls-files で判定
#   - 新規なら spec.md 内に該当パスの言及があるかを検査
#   - 無ければ warning を context に返す（ブロックはしない）
#
# トリガ: 実装セッションがアクティブな間（.implement-session.lock が存在する間）のみ動作。
# セッション未開始、および `session-manage.sh end` 後は dormant 状態で no-op。

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_FILE="${PROJECT_DIR}/.implement-session.json"
LOCKFILE="${PROJECT_DIR}/.implement-session.lock"

# 実装セッションがアクティブな間のみ動作（未開始 / end 済みなら dormant）。
# `session-manage.sh end` は lockfile のみ削除しセッション本体を参考情報として残すため、
# アクティブ判定には lockfile を使う（issue #79）
if [ ! -f "$LOCKFILE" ] || [ ! -f "$SESSION_FILE" ]; then
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

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo '')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')

if [ "$TOOL_NAME" != "Write" ] || [ -z "$FILE_PATH" ]; then
  exit 0
fi

cd "$PROJECT_DIR"
REL_PATH=$(realpath --relative-to="$PROJECT_DIR" "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# 除外: test ファイル、自動生成物、lock、snapshot
case "$REL_PATH" in
  */tests/*|*_test.rs|*.test.ts|*.spec.ts|*Tests.cs) exit 0 ;;
  target/*|node_modules/*|dist/*|build/*|obj/*|bin/*) exit 0 ;;
  *.lock|*.snap) exit 0 ;;
esac

# git が既知のファイル（既存編集）ならスキップ
if git ls-files --error-unmatch "$REL_PATH" >/dev/null 2>&1; then
  exit 0
fi

BASENAME=$(basename "$REL_PATH")
DIRNAME=$(dirname "$REL_PATH")

MENTIONED=0
for SPEC_FILE in "${SPEC_DIR}"/*.md; do
  [ -f "$SPEC_FILE" ] || continue
  if grep -qF "$REL_PATH" "$SPEC_FILE" 2>/dev/null || \
     grep -qF "$BASENAME" "$SPEC_FILE" 2>/dev/null || \
     grep -qF "$DIRNAME" "$SPEC_FILE" 2>/dev/null; then
    MENTIONED=1
    break
  fi
done

if [ "$MENTIONED" -eq 0 ]; then
  cat <<EOF
<new_file_warning>
新規ファイルを作成しました: \`${REL_PATH}\`

このパス（またはそのディレクトリ）は実装中の spec（${SPEC_ID}）に明示的な言及がありません。
スコープ逸脱の可能性があります。以下を検討してください:

1. このファイルは本当に必要か? → 必要なら design.md / tasks.md に追記
2. 既存ファイルで代替できないか?
3. 別タスクで扱うべきか?

意図的な追加であれば spec を更新してから続行してください。
</new_file_warning>
EOF
fi

exit 0
