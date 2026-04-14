#!/usr/bin/env bash
# Post-Edit/Write Markdownlint 自動修正 — .md ファイル編集後にフォーマットを自動修正
# 非ブロッキング（常に exit 0）
# 参照 QC: QC10 (Documentation Lint)

set -euo pipefail

# jq が利用できない場合はスキップ
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# stdin から PostToolUse ペイロードを読み取り、編集対象ファイルパスを取得
FILE_PATH=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null || echo '')
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# .md ファイルのみ対象
if [[ "$FILE_PATH" != *.md ]]; then
  exit 0
fi

# ファイルが存在しない場合はスキップ
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# npx が利用できない場合はスキップ
if ! command -v npx >/dev/null 2>&1; then
  exit 0
fi

# markdownlint-cli2 で自動修正（失敗してもサイレント）
npx markdownlint-cli2 --fix "$FILE_PATH" >/dev/null 2>&1 || true

exit 0
