#!/usr/bin/env bash
# confirm-phase-progression.sh
#
# Stop hook: spec-workflow Phase / Wave 進行宣言が、直前のユーザー発話に
# 明示同意がない場合に block する。LLM 幻覚（"Auto Mode" 発明等）の構造防御。
#
# 動作:
#   - Stop hook 入力の last_assistant_message（＝今ターンの最終 assistant 発言）から
#     「Phase/Wave 進行宣言」パターンを検出
#   - パターン検出時、直近の user 発言から「明示同意」パターンを検索
#   - 同意なしで進行宣言 → exit 2 で block（stderr が Claude へのフィードバック）
#   - spec-workflow 関連が見えない場合は dormant（exit 0）
#
# 出典: dapper-hardening-orchestrator.md 根本原因 A（A）
# 関連事例: dojin-viewer Phase 1 完了後の「Auto Mode のため Wave 2 へ進みます」幻覚
#
# 実装上の注意 1（検出対象の範囲 — 過剰ブロックの原因）:
#   検出対象は **今ターンの最終 assistant 発言のみ**。transcript の tail を丸ごと
#   grep すると tool_result・過去の発言・ユーザー発話まで一致し、無関係な文脈で
#   ブロックする（実測: 手元 12 transcript 中 4 件が誤 block。本ファイルを cat した
#   tool_result の "Auto Mode" に一致した例を含む）。
#   加えて transcript は非同期書き込みで今ターンの最終メッセージをまだ含まないことが
#   あるため、公式ドキュメントは Stop hook で last_assistant_message を使うよう指示している。
#   transcript からの抽出はフィールド欠落時のフォールバックに留めること。
#
# 実装上の注意 2（無限ループ）:
#   ブロック直後の再 Stop では stop_hook_active=true が渡る。これを見ないと、
#   ブロック後の assistant 発言が再び進行宣言に一致してループする
#   （本フックの stderr 文言自体が "Auto Mode" 等を含み transcript に残る）。
#
# 実装上の注意 3（issue #79 と同種の SIGPIPE 対策）:
#   変数の検査に `echo "$VAR" | grep -q` を使うと、grep が最初のマッチで即終了した際に
#   echo が SIGPIPE(141) で落ち、pipefail によりパイプライン全体が偽になる。
#   検査は here-string で行うこと。

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)

# ブロック起因の再入ならループ防止のため素通し
STOP_HOOK_ACTIVE=$(jq -r 'if .stop_hook_active == true then "true" else "false" end' <<< "$INPUT" 2>/dev/null || echo 'false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

TRANSCRIPT_PATH=$(jq -r '.transcript_path // empty' <<< "$INPUT" 2>/dev/null || echo '')

# 今ターンの最終 assistant 発言（Stop hook 入力の正規のフィールド）
LAST_ASSISTANT_MSG=$(jq -r '
  (.last_assistant_message // "")
  | if type == "string" then .
    elif type == "array" then ([.[] | select(type == "object" and .type == "text") | .text] | join("\n"))
    else "" end
' <<< "$INPUT" 2>/dev/null || echo '')

# フォールバック: 旧バージョン等でフィールドが無い場合のみ transcript から抽出
if [ -z "$LAST_ASSISTANT_MSG" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  LAST_ASSISTANT_MSG=$(jq -rs '
    [.[] | select(.type == "assistant")
         | (.message.content? // .content? // "")
         | if type == "string" then .
           elif type == "array" then ([.[] | select(type == "object" and .type == "text") | .text] | join("\n"))
           else "" end
         | select(length > 0)]
    | last // ""
  ' "$TRANSCRIPT_PATH" 2>/dev/null || echo '')
fi

# 判定材料が無ければ何もしない
if [ -z "$LAST_ASSISTANT_MSG" ]; then
  exit 0
fi

# spec-workflow 関連の transcript かどうか確認（dormant 判定）
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  if ! grep -qE "spec-workflow|spec-implement|spec-design|/spec-|Wave [0-9]|Phase [0-9]|tasks\.md" "$TRANSCRIPT_PATH" 2>/dev/null; then
    exit 0
  fi
fi

# フック自身の仕組みを話題にしている発言（ブロック文言の引用、パターンの
# 自己分析、修正提案など）は宣言ではない。specrail の履歴で、フックの誤検知を
# 説明する発言がそれ自体で再ブロックされる事例を確認したため除外する。
if grep -qE 'stop_hook_blocked|confirm-phase-progression|PROGRESSION_PATTERNS|RECENT_LINES|LAST_USER_MSG' <<< "$LAST_ASSISTANT_MSG"; then
  exit 0
fi

# 進行宣言パターンと、その一致行が「宣言」ではないと判断するパターン。
#
# ロケール非依存にするため、否定文字クラス（[^…]）と回数指定（.{0,N}）は使わない。
# LC_ALL=C では `.` も `[^あ]` もバイト単位になり、マルチバイト文字で破綻するため。
PROGRESSION_PATTERNS=(
  "(Auto Mode|自動モード|継続モード|auto-resume).*(のため|につき|なので|により).*(進み|進め|続行|開始|起動)"
  "(ユーザー|ユーザ)(の|への)?(確認|承認).*(省略|スキップ|飛ば)"
  "省略して.*(Wave|Phase)"
  "Wave 1.*完了.*Wave 2"
  "Wave 2.*完了.*Wave 3"
  "Phase [0-9]+.*完了.*(次の|続けて).*(Phase|Wave|着手|進)"
  "次の (Phase|Wave|wave) ?(へ|に).*進"
  "(Phase|Wave) ?[0-9]+ ?(へ|に) ?進みます"
  "(Phase|Wave) [0-9]+.*並列起動を開始"
)

# 一致行がこれらを含むなら、進行の「宣言」ではなく規範の説明・引用・ユーザーへの
# 問い返しである（例:「ユーザー確認を省略してはならない」「Phase 3 に進みますか？」）。
# 本フック自身の仕様説明や設計文書のレビュー会話でブロックしないための除外。
# 注意: 除外語は広げすぎないこと。判定範囲を一致箇所の文に限っていても、「ください」
#   「？」のような通常の敬語・疑問表現を入れると、「Phase 2 に着手します。問題が
#   あれば知らせてください」のような真の宣言まで無効化される（実測で確認）。
NON_DECLARATION_RE='ならない|なりません|しない|しません|禁止|してはいけ|べきではない|不可|ますか|でしょうか|取り下げ|撤回|一致しました|にマッチ'

DETECTED=""
for PATTERN in "${PROGRESSION_PATTERNS[@]}"; do
  # grep が読み手なので SIGPIPE の心配はない（issue #79 は書き手が echo の場合）。
  # -o で一致文字列そのものを取り、以降を文末（。/ 改行）まで足した範囲だけを
  # 除外判定に使う。行全体で判定すると、後続の別の文（「〜ますか？」等）に
  # 引きずられて検出が無効化される。
  MATCHES=$(grep -m1 -oE "$PATTERN" <<< "$LAST_ASSISTANT_MSG" || true)
  [ -n "$MATCHES" ] || continue
  MATCH=${MATCHES%%$'\n'*}
  REST=${LAST_ASSISTANT_MSG#*"$MATCH"}
  REST=${REST%%$'\n'*}
  REST=${REST%%。*}
  if ! grep -qE "$NON_DECLARATION_RE" <<< "${MATCH}${REST}"; then
    DETECTED="$PATTERN"
    break
  fi
done

# 進行宣言が検出されなければ dormant
if [ -z "$DETECTED" ]; then
  exit 0
fi

# 直近の user 発言（最後から逆方向に検索）から同意パターンを検出。
# transcript の type=="user" には tool_result・スラッシュコマンドの入出力・
# system-reminder・割り込み通知も含まれるため、実際の人間の発話だけを残す
# 実測で確認した誤採用:
#   - "<local-command-stdout>See ya!</local-command-stdout>"（/exit の出力）
#   - "<task-notification>...</task-notification>"（サブエージェント完了通知）
#     これはユーザーの「進めて」を毎回上書きするため、1 タスク 3 エージェントの
#     並列実装では停止のたびにブロックされる。全 transcript で 409 件と最多の混入源。
LAST_USER_MSG=''
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  LAST_USER_MSG=$(jq -rs '
    def keep:
      select(test("^[[:space:]]*<(task-notification|local-command-stdout|local-command-caveat|command-name|command-message|command-args|system-reminder|user-prompt-submit-hook|bash-input|bash-stdout)") | not)
      | select(test("^[[:space:]]*\\[Request interrupted by user") | not);
    [ .[]
      | select((.type == "user" or .role == "user") and (.isMeta != true))
      | (.message.content? // .content? // "")
      | if type == "string" then [.]
        elif type == "array" then [.[] | select(type == "object" and .type == "text") | .text]
        else [] end
      | [ .[] | keep ]
      | join("\n")
      | select(length > 0) ]
    | last // ""
  ' "$TRANSCRIPT_PATH" 2>/dev/null || echo '')
fi

# ユーザー発話が特定できないなら同意の有無を判断できない。ブロックせず通す
# （誤ブロックの害のほうが大きいため fail-open）
if [ -z "$LAST_USER_MSG" ]; then
  exit 0
fi

# 同意パターン（明示的な同意表現のみ。曖昧語は誤同意を招くため除外）
# 除外した語と理由:
#   - "進行": 否定/質問にも一致（"進行しないで" / "進行状況は？"）
#   - "自動" / "オート": 本フックが防ぐ "Auto Mode" 概念そのものを同意扱いするのは自己矛盾
#   - "それで" / "そのまま": 曖昧（"それで？" / "そのままにして"=触るな）
# ダッシュボード承認はフェーズ遷移の正規のゲート（spec-design/SKILL.md:572、
# spec-requirements/SKILL.md:203 — approved になれば check-approval が次フェーズを自動起動）。
# 「承認した」と伝えられた直後の Phase 遷移をブロックするのは仕様と矛盾する。
# 受動形（承認され）は「承認されていない」と一致するため除外。
CONSENT_PATTERNS=(
  "承認した"
  "承認しました"
  "承認済"
  "承認完了"
  "進めて"
  "進める"
  "進んで"
  "次へ"
  "次に進"
)

CONSENT_FOUND=0
for PATTERN in "${CONSENT_PATTERNS[@]}"; do
  if grep -qE "$PATTERN" <<< "$LAST_USER_MSG"; then
    CONSENT_FOUND=1
    break
  fi
done

# 英単語系は単語単位マッチ（-w）+ 大文字小文字無視で判定（"look" の "ok" 等への誤爆防止）
# 注意: grep -E の \b は POSIX ERE で保証されない（GNU 拡張）。移植性のため -w を使う
if [ "$CONSENT_FOUND" -eq 0 ] && grep -qiwE 'continue|ok|okay|yes|auto|approved' <<< "$LAST_USER_MSG"; then
  CONSENT_FOUND=1
fi

# 単一文字選択（option choose）: メッセージ全体が選択肢 1〜2 文字のときのみ同意扱い
# （旧実装の文字クラス一致は「A〜E や数字を1文字でも含む」あらゆる文章を同意と誤認していた）
TRIMMED_MSG=$(printf '%s' "$LAST_USER_MSG" | tr -d '[:space:]')
if [ "$CONSENT_FOUND" -eq 0 ] && grep -qE '^[αβγδεA-E0-9]{1,2}$' <<< "$TRIMMED_MSG"; then
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
- 本仕様に存在しない「自動進行」概念を発明してユーザー確認をスキップしてはならない
- Wave/Phase 進行・大規模並列起動の前は user confirmation 必須
- auto-resume.sh はレートリミット復旧専用、ユーザー意思確認の代替ではない

過去事例: dojin-viewer Phase 1 完了後に Claude が自動進行を理由に次 Wave へ進むと
発言し、ユーザーから「指示を出したつもりはない」と指摘された。

対応:
- 現在の進行宣言を取り下げ、ユーザーに明示確認を求めること（オプション提示等）
- ユーザー応答を待ってから次の Phase/Wave に進むこと
</stop_hook_blocked>
EOF
  exit 2
fi

# 同意あり → pass
exit 0
