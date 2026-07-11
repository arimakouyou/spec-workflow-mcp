#!/usr/bin/env bash
# confirm-phase-progression.sh
#
# Stop hook: spec-workflow Phase / Wave 進行宣言が、直前のユーザー発話に
# 明示同意がない場合に block する。LLM 幻覚（"Auto Mode" 発明等）の構造防御。
#
# 動作:
#   - transcript の最後の assistant 発言から「Phase/Wave 進行宣言」パターンを検出
#   - パターン検出時、その直前の user 発言から「明示同意」パターンを検索
#   - 同意なしで進行宣言 → exit 2 で block（stderr が Claude へのフィードバック）
#   - spec-workflow 関連が見えない場合は dormant（exit 0）
#
# 出典: dapper-hardening-orchestrator.md 根本原因 A（A）
# 関連事例: dojin-viewer Phase 1 完了後の「Auto Mode のため Wave 2 へ進みます」幻覚

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo '')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# spec-workflow 関連の transcript かどうか確認（dormant 判定）
if ! grep -qE "spec-workflow|spec-implement|spec-design|/spec-|Wave [0-9]|Phase [0-9]|tasks\.md" "$TRANSCRIPT_PATH" 2>/dev/null; then
  exit 0
fi

# 直近 200 行で assistant の最終発言テキストを抽出
RECENT_LINES=$(tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null || echo '')

# 進行宣言パターン（Japanese + English mix）
PROGRESSION_PATTERNS=(
  "Auto Mode"
  "自動モード"
  "継続モード"
  "ユーザー確認を省略"
  "省略して.*Wave"
  "省略して.*Phase"
  "Wave 1.*完了.*Wave 2"
  "Wave 2.*完了.*Wave 3"
  "Phase [0-9]+.*完了.*次"
  "次の Phase へ進"
  "次の wave へ進"
  "次の Wave へ進"
  "Phase [0-9]+ へ進みます"
  "Wave [0-9]+ へ進みます"
  "並列起動を開始"
  "続行します"
  "auto-resume"
)

DETECTED=""
for PATTERN in "${PROGRESSION_PATTERNS[@]}"; do
  if echo "$RECENT_LINES" | grep -qE "$PATTERN"; then
    DETECTED="$PATTERN"
    break
  fi
done

# 進行宣言が検出されなければ dormant
if [ -z "$DETECTED" ]; then
  exit 0
fi

# 直近の user 発言（最後から逆方向に検索）から同意パターンを検出
# transcript は JSONL 形式の想定。type=="user" エントリには tool_result も含まれ、
# content はブロック配列のことが多いため、text ブロックのみを抽出する
LAST_USER_MSG=$(jq -rs '
  [.[] | select(.type == "user" or .role == "user")
       | .message.content? // .content? // ""
       | if type == "string" then .
         elif type == "array" then ([.[] | select(type == "object" and .type == "text") | .text] | join("\n"))
         else "" end
       | select(length > 0)]
  | last // ""
' "$TRANSCRIPT_PATH" 2>/dev/null || echo '')

# 同意パターン（日本語は部分一致、英単語は単語境界付きで誤爆を防ぐ）
CONSENT_PATTERNS=(
  "進めて"
  "進める"
  "進行"
  "次へ"
  "次に進"
  "そのまま"
  "それで"
  "進んで"
  "自動"
  "オート"
)

CONSENT_FOUND=0
for PATTERN in "${CONSENT_PATTERNS[@]}"; do
  if echo "$LAST_USER_MSG" | grep -qE "$PATTERN"; then
    CONSENT_FOUND=1
    break
  fi
done

# 英単語系は単語境界 + 大文字小文字無視で判定（"look" の "ok" 等への誤爆防止）
if [ "$CONSENT_FOUND" -eq 0 ] && echo "$LAST_USER_MSG" | grep -qiE '\b(continue|ok(ay)?|yes|auto)\b'; then
  CONSENT_FOUND=1
fi

# 単一文字選択（option choose）: メッセージ全体が選択肢 1〜2 文字のときのみ同意扱い
# （旧実装の文字クラス一致は「A〜E や数字を1文字でも含む」あらゆる文章を同意と誤認していた）
TRIMMED_MSG=$(printf '%s' "$LAST_USER_MSG" | tr -d '[:space:]')
if [ "$CONSENT_FOUND" -eq 0 ] && printf '%s' "$TRIMMED_MSG" | grep -qE '^[αβγδεA-E0-9]{1,2}$'; then
  CONSENT_FOUND=1
fi

# 進行宣言あり + 同意なし → block
if [ "$CONSENT_FOUND" -eq 0 ]; then
  cat >&2 <<EOF
<stop_hook_blocked>
spec-workflow Phase/Wave 進行宣言を検出しました（パターン: "$DETECTED"）が、
直近のユーザー発話に明示同意（continue / yes / 進めて / OK / 1〜N 選択 等）が
見当たりません。

仕様（dapper-hardening A）:
- "Auto Mode" / "継続モード" / "自動進行" などの **本仕様に存在しない概念**
  を発明してユーザー確認をスキップしてはならない
- Wave/Phase 進行・大規模並列起動の前は user confirmation 必須
- auto-resume.sh はレートリミット復旧専用、ユーザー意思確認の代替ではない

過去事例: dojin-viewer Phase 1 完了後に Claude が「Auto Mode のため Wave 2 へ
進みます」と発言し、ユーザーから「指示を出したつもりはない」と指摘された。

対応:
- 現在の進行宣言を取り下げ、ユーザーに明示確認を求めること（オプション提示等）
- ユーザー応答を待ってから次の Phase/Wave に進むこと
</stop_hook_blocked>
EOF
  exit 2
fi

# 同意あり → pass
exit 0
