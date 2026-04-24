#!/usr/bin/env bash
# verify-tests-run.sh
#
# Stop hook: 実装セッション中の完了宣言前に、直近でテストランナーが走ったかを
# 確認する。「テスト空 / テスト飛ばし」への構造防御。
#
# 動作:
#   - 実装セッション中（.implement-session.json 存在）のみ動作
#   - transcript からテストランナー実行履歴を検査
#   - 見つからなければ exit 1 でブロック（Claude に続行を促す）
#   - 実行があっても末尾に FAILED signal があれば exit 1
#
# 注意:
#   - Stop hook の exit 1 は非実装セッションで誤発火すると UX を大きく損なう
#   - 実装セッション外では即 exit 0 する（dormant 前提）

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
  exit 1
fi

# テスト実行履歴はあるが、末尾に失敗シグナルがないか確認
LAST_500_LINES=$(tail -n 500 "$TRANSCRIPT_PATH" 2>/dev/null || echo '')
if echo "$LAST_500_LINES" | grep -qE "FAILED|FAIL:|test result: FAILED|test .* failed|Tests failed"; then
  cat >&2 <<'EOF'
<stop_hook_blocked>
直近のテスト実行に失敗があるようです。失敗を修正してから完了してください。
</stop_hook_blocked>
EOF
  exit 1
fi

exit 0
