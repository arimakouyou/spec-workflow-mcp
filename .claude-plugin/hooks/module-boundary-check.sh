#!/usr/bin/env bash
# module-boundary-check.sh
#
# PostToolUse (Edit|Write on code files): 編集ファイルが design.md の
# `## Module Boundaries` セクションが定義する Layer の Directory 配下に
# 適合しているか、および facade 注記 (Re-exports X from Y / re-exported from /
# facade) を持つセルの両ファイル構成かを軽量チェックする。
#
# 主目的:
#   - 「Layer Directory 配下に正しく配置されているのに reviewer が違反と誤判定する」
#     型の FP を抑制するため、適合状況を design.md と紐付けて hint 出力
#   - facade ペア構成 (例: src/config.rs + src/infra/config.rs) は両ファイル
#     存在が期待されることを明示
#
# 動作:
#   - 編集対象がコードファイル (design-conformance-check.sh と同じ拡張子) のみ処理
#   - .implement-session.json から spec_id を取得 (無ければ silent exit)
#   - design.md の ## Module Boundaries を抽出し Layer/Directory を辞書化
#   - 編集ファイルが Layer Directory 配下なら "適合" を hint 出力
#   - facade セルに該当する編集なら両ファイル必須を hint 出力
#
# 最終判定は review-worker (DC4) で。本 hook は補助役。
# 参照: .claude-plugin/rules/design-conformance.md DC4

set -euo pipefail
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')
[ -z "$FILE_PATH" ] && exit 0

# 対象ファイル: コードファイルのみ (design-conformance-check.sh と同じ拡張子セット)
case "$FILE_PATH" in
  *.rs|*.cs|*.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.java|*.kt|*.scala|*.rb|*.swift|*.cpp|*.cc|*.c|*.h|*.hpp) ;;
  *) exit 0 ;;
esac

SESSION_FILE=".implement-session.json"
[ -f "$SESSION_FILE" ] || exit 0
SPEC_ID=$(jq -r '.spec_id // empty' "$SESSION_FILE" 2>/dev/null || echo '')
[ -z "$SPEC_ID" ] && exit 0

DESIGN_MD=".spec-workflow/specs/${SPEC_ID}/design.md"
[ -f "$DESIGN_MD" ] || exit 0
grep -qE '^## Module Boundaries' "$DESIGN_MD" || exit 0

# `## Module Boundaries` セクション抽出 (次の `## ` 見出しまたは EOF まで)
MB=$(awk '/^## Module Boundaries/{flag=1; next} /^## /{flag=0} flag' "$DESIGN_MD")

# table 行から Layer/Directory ペアを抽出 (区切り行・ヘッダ行は除外)
LAYER_DIRS=$(echo "$MB" | awk -F'|' '
  /^[[:space:]]*\|/ && NF>=4 {
    if ($2 ~ /^[[:space:]]*[-:]+[[:space:]]*$/) next
    layer=$2; dir=$3
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", layer)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", dir)
    gsub(/`/, "", layer); gsub(/`/, "", dir)
    if (tolower(layer) ~ /^(layer|レイヤ)$/) next
    if (dir == "" || dir !~ /\//) next
    print layer "\t" dir
  }')

INFO=""

# === Layer Directory 適合チェック (FP 抑制の本丸) ===
MATCHED_LAYER=""
MATCHED_DIR=""
while IFS=$'\t' read -r LAYER DIR; do
  [ -z "$DIR" ] && continue
  DIR_NO_TRAIL=$(echo "$DIR" | sed -E 's|/+$||')
  # 編集ファイルパスが Directory を prefix として含むか (workspace crate 配置にも対応)
  if echo "$FILE_PATH" | grep -qE "(^|/)${DIR_NO_TRAIL}/"; then
    MATCHED_LAYER="$LAYER"
    MATCHED_DIR="$DIR"
    break
  fi
done <<EOF
$LAYER_DIRS
EOF

if [ -n "$MATCHED_LAYER" ]; then
  INFO+="- 編集ファイル \`${FILE_PATH##*/}\` は design.md Module Boundaries の **\`${MATCHED_LAYER}\`** 層 (\`${MATCHED_DIR}\`) に適合 — Layer prefix 一致のため individual セルとのパス文字列ずれは違反ではない\n"
fi

# === Facade ペア注記チェック ===
FACADES=$(echo "$MB" | awk -F'|' '
  /^[[:space:]]*\|/ && NF>=4 {
    line=$0
    if (line ~ /[Rr]e-?exports?[[:space:]]/ || line ~ /re-exported from/ || line ~ /[Ff]acade/) {
      path=$3; layer="?"
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", path)
      gsub(/`/, "", path)
      if (match(line, /from[[:space:]]+([a-zA-Z0-9_]+)/, m)) layer=m[1]
      print path "\t" layer
    }
  }')

while IFS=$'\t' read -r FPATH FLAYER; do
  [ -z "$FPATH" ] && continue
  if echo "$FILE_PATH" | grep -qE "(^|/)${FPATH//\//\\/}$"; then
    INFO+="- facade \`${FPATH}\` の編集を検出。design.md は \`${FLAYER}\` 層配下の impl ペアの存在を前提としているため両ファイル必須 (片方のみは不整合)\n"
  fi
done <<EOF
$FACADES
EOF

[ -z "$INFO" ] && exit 0

cat <<EOF
<module_boundary_hints>
design.md (\`${DESIGN_MD}\`) \`## Module Boundaries\` 照合結果:

$(printf "%b" "$INFO")
判定方針 (design-conformance.md DC4 参照):
1. **Layer Directory 配下** に配置されているファイルは適合。design.md 内の個別セルとのパス文字列完全一致は不要
2. **"Re-exports X from Y" / "re-exported from" / "facade"** 注記セルは facade + impl の両ファイル存在が前提
3. 真の violation は (a) どの Layer にもマップされない Directory への配置、または (b) Dependency direction rules 違反のみ
4. 機械検出 (\`tests/architecture.rs\` 等の arch-test) があればそれを一次ソースに
</module_boundary_hints>
EOF

exit 0
