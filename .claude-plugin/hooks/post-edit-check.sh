#!/usr/bin/env bash
# Post-Edit/Write チェック — 編集後にフォーマット・Lint の状態を通知する
# P2-12: ファイル編集時の自動チェック
#
# このフックはブロッキングではなく、警告のみを出力する。
# 実際の自動修正は review-worker が担当する。

set -euo pipefail

# stdin から PostToolUse ペイロードを読み取り、編集対象ファイルパスを取得
FILE_PATH=$(jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# .rs ファイルのみ対象（Rust プロジェクト）
if [[ "$FILE_PATH" != *.rs ]]; then
  exit 0
fi

# Cargo.toml が存在しない場合はスキップ（Rust プロジェクトではない）
if [ ! -f "Cargo.toml" ]; then
  exit 0
fi

# rustfmt チェック（フォーマット違反があれば警告）
if command -v rustfmt >/dev/null 2>&1; then
  if ! rustfmt --check "$FILE_PATH" >/dev/null 2>&1; then
    echo "⚠️ [post-edit] rustfmt: フォーマット違反を検出 — $FILE_PATH"
    echo "   自動修正: rustfmt $FILE_PATH"
  fi
fi
