#!/usr/bin/env bash
# design-conformance-check.sh
#
# PostToolUse (Edit|Write on code/migration files): コード変更が
# design.md の DB Schema (DC1) / API (DC2) / Data Model (DC3) と
# 整合しているかを軽量チェックする。
#
# 動作:
#   - 編集対象がコード or migration ファイルかを判定
#   - .implement-session.json から spec_id を取得 (存在しなければ silent exit)
#   - design.md と grep ベースで簡易比較
#   - 未記載の TABLE / route / endpoint を warning 出力（block はしない）
#
# 本格的な照合は review-worker のカテゴリ F (Design Conformance) に
# 委譲。本 hook は「乖離発生の早期気づき」を提供する補助役。
#
# 参照: .claude-plugin/rules/design-conformance.md DC1-DC3

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')
[ -z "$FILE_PATH" ] && exit 0

# 対象ファイル: コード or migration のみ
case "$FILE_PATH" in
  *.rs|*.cs|*.ts|*.tsx|*.js|*.jsx|*.py| \
  */migrations/*.sql|*/Migrations/*.cs|*/migrations/*.up.sql|*/migrations/*.down.sql) ;;
  *) exit 0 ;;
esac

# spec_id を session ファイルから取得 (無ければ silent exit)
SESSION_FILE=".implement-session.json"
[ -f "$SESSION_FILE" ] || exit 0
SPEC_ID=$(jq -r '.spec_id // empty' "$SESSION_FILE" 2>/dev/null || echo '')
[ -z "$SPEC_ID" ] && exit 0

DESIGN_MD=".spec-workflow/specs/${SPEC_ID}/design.md"
[ -f "$DESIGN_MD" ] || exit 0

WARNINGS=""

# === DC1: DB Schema ===
# migration ファイルの場合のみ TABLE 名を検出
if echo "$FILE_PATH" | grep -qE 'migrations?/.*\.sql$|/Migrations/.*\.cs$'; then
  # CREATE TABLE 検出 (大文字小文字無視)
  TABLES=$(grep -oiE 'CREATE TABLE[[:space:]]+(IF NOT EXISTS[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*' "$FILE_PATH" 2>/dev/null \
    | awk '{print $NF}' | sort -u || echo '')
  for TABLE in $TABLES; do
    # design.md に table 名が出現するか (case-insensitive)
    if ! grep -qiF "$TABLE" "$DESIGN_MD"; then
      WARNINGS+="- DC1: migration の TABLE \`${TABLE}\` が design.md に未記載\n"
    fi
  done

  # ALTER TABLE 検出 (型変更や制約追加)
  ALTER_TABLES=$(grep -oiE 'ALTER TABLE[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*' "$FILE_PATH" 2>/dev/null \
    | awk '{print $NF}' | sort -u || echo '')
  for TABLE in $ALTER_TABLES; do
    if ! grep -qiF "$TABLE" "$DESIGN_MD"; then
      WARNINGS+="- DC1: ALTER TABLE 対象 \`${TABLE}\` が design.md に未記載 (未認可の構造変更の可能性)\n"
    fi
  done
fi

# === DC2: API endpoints ===
case "$FILE_PATH" in
  *.rs)
    # axum: .route("/path", ...)
    ROUTES=$(grep -oE '\.route\("/[^"]+' "$FILE_PATH" 2>/dev/null \
      | sed -E 's|^\.route\("||' | sort -u || echo '')
    for ROUTE in $ROUTES; do
      if ! grep -qF "$ROUTE" "$DESIGN_MD"; then
        WARNINGS+="- DC2: axum route \`${ROUTE}\` が design.md に未記載\n"
      fi
    done
    ;;
  *.cs)
    # ASP.NET Core: app.MapGet("/path", ...), [HttpGet("/path")]
    ROUTES=$(grep -oE '(MapGet|MapPost|MapPut|MapDelete|MapPatch)\("/[^"]+' "$FILE_PATH" 2>/dev/null \
      | sed -E 's|^Map[A-Za-z]+\("||' | sort -u || echo '')
    HTTP_ATTRS=$(grep -oE '\[Http[A-Z]+\("/[^"]+' "$FILE_PATH" 2>/dev/null \
      | sed -E 's|^\[Http[A-Za-z]+\("||' | sort -u || echo '')
    for ROUTE in $ROUTES $HTTP_ATTRS; do
      if ! grep -qF "$ROUTE" "$DESIGN_MD"; then
        WARNINGS+="- DC2: ASP.NET route \`${ROUTE}\` が design.md に未記載\n"
      fi
    done
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    # Express: app.get("/path", ...), router.post("/path", ...)
    ROUTES=$(grep -oE '\.(get|post|put|delete|patch)\(["'"'"']/[^"'"'"']+' "$FILE_PATH" 2>/dev/null \
      | sed -E 's|^\.(get\|post\|put\|delete\|patch)\(["'"'"']||' | sort -u || echo '')
    for ROUTE in $ROUTES; do
      if ! grep -qF "$ROUTE" "$DESIGN_MD"; then
        WARNINGS+="- DC2: Express route \`${ROUTE}\` が design.md に未記載\n"
      fi
    done
    ;;
esac

# warning が無ければ silent exit (false positive 対策のため過剰検出はしない)
[ -z "$WARNINGS" ] && exit 0

cat <<EOF
<design_conformance_warnings>
\`${FILE_PATH##*/}\` の変更で design.md (\`${DESIGN_MD}\`) との乖離が検出されました:

$(printf "%b" "$WARNINGS")
処理方針 (design-conformance.md DC1-DC3 参照):
1. design.md に既存の定義から代替できないか確認
2. 代替不可なら **design.md の改訂を伴う Phase Reset** または review-worker の \`review_action: escalate\` を検討
3. 仕様逸脱を伴わない単なる検出漏れ (table 別名・route prefix 違い等) なら無視可

本 hook は grep ベースのため false positive あり。最終判断はコードと design.md の照合で。
</design_conformance_warnings>
EOF

exit 0
