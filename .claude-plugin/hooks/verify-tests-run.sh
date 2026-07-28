#!/usr/bin/env bash
# verify-tests-run.sh
#
# Stop hook: 実装セッション中の完了宣言前に、直近でテストランナーが走ったかを
# 確認する。「テスト空 / テスト飛ばし」への構造防御。
#
# 動作:
#   - 実装セッションが「アクティブ」な間（.implement-session.lock 存在）のみ動作
#   - transcript からテストランナー実行履歴を検査
#   - 見つからなければ exit 2 でブロック（stderr が Claude へのフィードバック）
#   - 直近のテスト実行以降のログに FAILED signal があれば exit 2
#
# 注意:
#   - Stop hook のブロックは exit 2 のみ有効（exit 1 は非ブロッキングエラー扱い）
#   - 非実装セッションで誤発火すると UX を大きく損なうため、
#     実装セッション外では即 exit 0 する（dormant 前提）
#   - dormancy 判定に lockfile を使うのは、`session-manage.sh end` が lockfile のみ削除し
#     `.implement-session.json` を参考情報として残す仕様のため。セッションファイルで
#     判定すると end 後もブロックし続ける（issue #79）

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOCKFILE="${PROJECT_DIR}/.implement-session.lock"

# 実装セッションがアクティブでなければチェックしない（未開始 / end 済みなら dormant）
if [ ! -f "$LOCKFILE" ]; then
  exit 0
fi

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo '')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  # transcript が追跡できないなら安全側（通す）
  exit 0
fi

# テストランナー検出パターン（主要言語・ランタイム）
TEST_PATTERNS=(
  "cargo test"
  "cargo nextest"
  "dotnet test"
  "npm test"
  "npm run test"
  "pnpm test"
  "pnpm run test"
  "yarn test"
  "bun test"
  "bun run test"
  "vitest"
  "jest"
  "pytest"
  "go test"
  "mix test"
)

TEST_CMD_RE=$(IFS='|'; printf '%s' "${TEST_PATTERNS[*]}")

# 実際に「実行された」テストコマンドだけを対象にする。
# transcript の生 grep では narration（"cargo test を実行して" 等）まで実行と誤認するため、
# assistant の tool_use[name=Bash] の .input.command のみを検査する（ガードの目的に一致）。
BASH_COMMANDS=$(jq -r '
  select(.type == "assistant")
  | (.message.content // [])[]?
  | select(.type == "tool_use" and (.name == "Bash" or .name == "bash"))
  | .input.command // empty
' "$TRANSCRIPT_PATH" 2>/dev/null || echo '')

# 既知スキーマか判定する（assistant エントリが .message.content 配列を持つか）。
# これにより「ツール未使用で narration に cargo test と書いただけ」も既知スキーマとして
# 正しく「実行なし」と判定でき、生 grep による narration 誤検出を防ぐ。
# `|| true`: head が 1 行で終了すると jq が SIGPIPE で 141 終了し、pipefail + errexit で
# スクリプト自体が中断されるため（assistant エントリが多い長いセッションで発生しうる）。
SCHEMA_OK=$(jq -r '
  select(.type == "assistant")
  | if (.message.content | type) == "array" then "yes" else empty end
' "$TRANSCRIPT_PATH" 2>/dev/null | head -n 1 || true)

FOUND=0
if [ "$SCHEMA_OK" = "yes" ]; then
  # スキーマ認識 OK: 実行済み Bash コマンドだけで判定（narration は対象外）
  # 注意: パイプ（`printf ... | grep -q`）は使わない。`grep -q` が最初のマッチで
  # 即終了すると書き手が SIGPIPE で 141 終了し、pipefail によりパイプライン全体が
  # 141（= 偽）になる。$BASH_COMMANDS がパイプバッファ（Linux 64KB）を超える
  # 長いセッションで必ず踏むため、here-string で入力を渡す（issue #79）。
  if grep -qE "$TEST_CMD_RE" <<< "$BASH_COMMANDS"; then
    FOUND=1
  fi
else
  # スキーマ不明（将来の transcript 形式差異等）: 従来の raw grep にフォールバック
  for PATTERN in "${TEST_PATTERNS[@]}"; do
    if grep -qF "$PATTERN" "$TRANSCRIPT_PATH" 2>/dev/null; then
      FOUND=1
      break
    fi
  done
fi

if [ "$FOUND" -eq 0 ]; then
  cat >&2 <<'EOF'
<stop_hook_blocked>
実装セッション中の完了宣言を検出しましたが、テストランナーの実行履歴が transcript に
見つかりません。以下のいずれかを実行して、テストが実際に pass することを確認してください:

  - cargo test / cargo nextest
  - dotnet test
  - npm test / pnpm test / yarn test / bun test
  - vitest / jest / pytest / go test / mix test

テスト空・テスト飛ばしは構造的に禁止しています。
</stop_hook_blocked>
EOF
  exit 2
fi

# テスト実行履歴はあるが、直近の実行に失敗シグナルがないか確認する。
# transcript は追記型のため、過去の失敗ログが末尾窓に残ると、修正後の再実行が成功しても
# 誤ブロックし続ける。これを避けるため「直近に実行されたテストコマンドの出力」だけを検査する。
# 具体的には最後のテスト tool_use の id を取り、それに対応する tool_result 出力を対象にする。
LAST_TEST_ID=$(jq -r --arg re "$TEST_CMD_RE" '
  select(.type == "assistant")
  | (.message.content // [])[]?
  | select(.type == "tool_use" and (.name == "Bash" or .name == "bash"))
  | select((.input.command // "") | test($re))
  | .id
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1)

RECENT_LOG=''
if [ -n "$LAST_TEST_ID" ]; then
  RECENT_LOG=$(jq -r --arg id "$LAST_TEST_ID" '
    select(.type == "user")
    | (.message.content // [])[]?
    | select(.type == "tool_result" and (.tool_use_id == $id))
    | (.content // "")
    | if type == "array" then (map(.text? // "") | join("\n")) else tostring end
  ' "$TRANSCRIPT_PATH" 2>/dev/null || echo '')
fi

# jq で直近テスト出力を取得できない場合（スキーマ差異 / 出力未取得等）は、
# 「最後にテストコマンドが現れた行以降」の raw ログにフォールバックする。
if [ -z "$RECENT_LOG" ]; then
  # `|| true`: grep が非マッチ（exit 1）だと pipefail + errexit でスクリプトが中断される
  LAST_TEST_LINE=$(grep -nE "$TEST_CMD_RE" "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1 | cut -d: -f1 || true)
  if [ -n "$LAST_TEST_LINE" ]; then
    RECENT_LOG=$(tail -n +"$LAST_TEST_LINE" "$TRANSCRIPT_PATH" 2>/dev/null || echo '')
  else
    RECENT_LOG=$(tail -n 500 "$TRANSCRIPT_PATH" 2>/dev/null || echo '')
  fi
fi

# 失敗シグナル（主要フレームワーク）:
#   - Rust      : "test result: FAILED"
#   - Go        : "--- FAIL"
#   - Python    : "FAILED (" (unittest: failures=/errors=), "= N failed" (pytest)
#   - Jest/汎用 : "FAIL:", "Tests failed", "N failed/failures/errors"
# 注意: 件数は非ゼロに限定し "0 failed" を含む成功サマリを除外する
FAIL_RE='test result: FAILED|FAIL:|--- FAIL|FAILED \(|Tests failed|[1-9][0-9]* (failed|failures|errors)'
if grep -qE "$FAIL_RE" <<< "$RECENT_LOG"; then
  cat >&2 <<'EOF'
<stop_hook_blocked>
直近のテスト実行に失敗があるようです。失敗を修正してから完了してください。
</stop_hook_blocked>
EOF
  exit 2
fi

exit 0
