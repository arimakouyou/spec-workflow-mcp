#!/usr/bin/env bash
# verify-tests-run.sh
#
# Stop hook: 実装セッション中の完了宣言前に、直近でテストランナーが走ったかを
# 確認する。「テスト空 / テスト飛ばし」への構造防御。
#
# 動作:
#   - 実装セッション中（.implement-session.json 存在）のみ動作
#   - transcript からテストランナー実行履歴を検査
#   - 見つからなければ exit 2 でブロック（stderr が Claude へのフィードバック）
#   - 直近のテスト実行以降のログに FAILED signal があれば exit 2
#
# 注意:
#   - Stop hook のブロックは exit 2 のみ有効（exit 1 は非ブロッキングエラー扱い）
#   - 非実装セッションで誤発火すると UX を大きく損なうため、
#     実装セッション外では即 exit 0 する（dormant 前提）

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_FILE="${PROJECT_DIR}/.implement-session.json"

# 実装セッション中でなければチェックしない（現状 Orchestrator 未実装のため dormant）
if [ ! -f "$SESSION_FILE" ]; then
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

FOUND=0
for PATTERN in "${TEST_PATTERNS[@]}"; do
  if grep -qF "$PATTERN" "$TRANSCRIPT_PATH" 2>/dev/null; then
    FOUND=1
    break
  fi
done

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
# 誤ブロックし続ける。これを避けるため「最後にテストコマンドが現れた行以降」だけを検査する。
TEST_CMD_RE=$(IFS='|'; printf '%s' "${TEST_PATTERNS[*]}")
LAST_TEST_LINE=$(grep -nE "$TEST_CMD_RE" "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1 | cut -d: -f1)
if [ -n "$LAST_TEST_LINE" ]; then
  RECENT_LOG=$(tail -n +"$LAST_TEST_LINE" "$TRANSCRIPT_PATH" 2>/dev/null || echo '')
else
  RECENT_LOG=$(tail -n 500 "$TRANSCRIPT_PATH" 2>/dev/null || echo '')
fi

# 失敗シグナル（主要フレームワーク）:
#   - Rust      : "test result: FAILED"
#   - Go        : "--- FAIL"
#   - Python    : "FAILED (" (unittest: failures=/errors=), "= N failed" (pytest)
#   - Jest/汎用 : "FAIL:", "Tests failed", "N failed/failures/errors"
# 注意: 件数は非ゼロに限定し "0 failed" を含む成功サマリを除外する
FAIL_RE='test result: FAILED|FAIL:|--- FAIL|FAILED \(|Tests failed|[1-9][0-9]* (failed|failures|errors)'
if printf '%s\n' "$RECENT_LOG" | grep -qE "$FAIL_RE"; then
  cat >&2 <<'EOF'
<stop_hook_blocked>
直近のテスト実行に失敗があるようです。失敗を修正してから完了してください。
</stop_hook_blocked>
EOF
  exit 2
fi

exit 0
