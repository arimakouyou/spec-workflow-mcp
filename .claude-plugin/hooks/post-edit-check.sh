#!/usr/bin/env bash
# Post-Edit/Write 統合自動フォーマット — 編集後にファイル種別に応じたフォーマッタを実行
# 対応言語: Rust (.rs), Node.js (.js/.ts/.tsx/.jsx/.css), .NET (.cs)
#
# ruff-format.sh パターン: 非ブロッキング（常に exit 0）、失敗時もサイレント
# 参照 QC: QC1 (rustfmt), QC6 (prettier), QC12 (dotnet format)

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

# ファイルが存在しない場合はスキップ
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Rust (.rs) ---
if [[ "$FILE_PATH" == *.rs ]]; then
  # Cargo.toml が存在しない場合はスキップ（Rust プロジェクトではない）
  if [ -f "Cargo.toml" ] && command -v rustfmt >/dev/null 2>&1; then
    rustfmt "$FILE_PATH" >/dev/null 2>&1 || true
  fi
  exit 0
fi

# --- Node.js (.js/.ts/.tsx/.jsx/.css — prettier 対象) ---
if [[ "$FILE_PATH" =~ \.(js|ts|tsx|jsx|css)$ ]]; then
  # package.json が存在し、prettier が利用可能な場合のみ実行
  if [ -f "package.json" ] && command -v npx >/dev/null 2>&1; then
    # prettier 設定ファイルの存在を確認（設定なしでは実行しない）
    if [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || [ -f ".prettierrc.yml" ] || \
       [ -f ".prettierrc.yaml" ] || [ -f ".prettierrc.js" ] || [ -f ".prettierrc.cjs" ] || \
       [ -f ".prettierrc.mjs" ] || [ -f "prettier.config.js" ] || [ -f "prettier.config.cjs" ] || \
       [ -f "prettier.config.mjs" ] || \
       grep -q '"prettier"' package.json 2>/dev/null; then
      npx prettier --write "$FILE_PATH" >/dev/null 2>&1 || true
    fi
  fi
  exit 0
fi

# --- .NET (.cs) ---
if [[ "$FILE_PATH" == *.cs ]]; then
  # .sln または .csproj が存在する場合に実行
  if { ls *.sln >/dev/null 2>&1 || find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; } && command -v dotnet >/dev/null 2>&1; then
    dotnet format --include "$FILE_PATH" --no-restore >/dev/null 2>&1 || true
  fi
  exit 0
fi

exit 0
