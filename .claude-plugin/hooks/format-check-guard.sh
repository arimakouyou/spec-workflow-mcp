#!/usr/bin/env bash
# フォーマットチェック・コミットガード — git commit 時にプロジェクト全体のフォーマット整合性を検証
# ブロッキング: フォーマット違反検出時は exit 2 でコミットを阻止
# 参照 QC: QC1 (cargo fmt), QC6 (prettier), QC12 (dotnet format)
#
# post-edit-check.sh（自動修正）の安全網として機能。
# Bash 経由の編集や hook スキップ時にフォーマット整合性を保証する。
# 参考パターン: arch-lint-guard.sh (wingrs-paas-front-api)

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# git commit 以外は素通し
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  exit 0
fi

FAIL=false

# --- Rust: cargo fmt --check ---
if [ -f Cargo.toml ]; then
  if command -v cargo >/dev/null 2>&1; then
    if ! cargo fmt --all -- --check >/dev/null 2>&1; then
      echo "⛔ [format-check] cargo fmt: フォーマット違反が検出されました"
      echo "   自動修正: cargo fmt --all"
      FAIL=true
    fi
  fi
fi

# --- Node.js: prettier --check ---
if [ -f package.json ] && command -v npx >/dev/null 2>&1; then
  # prettier 設定ファイルの存在を確認
  HAS_PRETTIER=false
  if [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || [ -f ".prettierrc.yml" ] || \
     [ -f ".prettierrc.yaml" ] || [ -f ".prettierrc.js" ] || [ -f ".prettierrc.cjs" ] || \
     [ -f ".prettierrc.mjs" ] || [ -f "prettier.config.js" ] || [ -f "prettier.config.cjs" ] || \
     [ -f "prettier.config.mjs" ] || \
     grep -q '"prettier"' package.json 2>/dev/null; then
    HAS_PRETTIER=true
  fi

  if [ "$HAS_PRETTIER" = true ]; then
    if ! npx prettier --check . >/dev/null 2>&1; then
      echo "⛔ [format-check] prettier: フォーマット違反が検出されました"
      echo "   自動修正: npx prettier --write ."
      FAIL=true
    fi
  fi
fi

# --- .NET: dotnet format --verify-no-changes ---
if ls *.sln >/dev/null 2>&1 || find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  if command -v dotnet >/dev/null 2>&1; then
    if ! dotnet format --verify-no-changes --no-restore >/dev/null 2>&1; then
      echo "⛔ [format-check] dotnet format: フォーマット違反が検出されました"
      echo "   自動修正: dotnet format"
      FAIL=true
    fi
  fi
fi

if [ "$FAIL" = true ]; then
  exit 2
fi

exit 0
