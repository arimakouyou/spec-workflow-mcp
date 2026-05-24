#!/usr/bin/env bash
# inject-skill-hint.sh
#
# PreToolUse (Edit|Write): 編集対象ファイルの拡張子と import/use 文から、
# 関連する技術別 skill のパスと要約をヒントとして context に注入する。
#
# 参照渡し方式: skill 本体は注入せず、ファイルパスと 1-2 行の要約のみ（数十
# トークン）を出力。必要なら Claude が Read ツールで本体を参照する。
#
# 非ブロッキング（常に exit 0）。jq が無い、skill が存在しない、マッチしない
# 等の場合は黙って素通し。

set -euo pipefail

# jq が無ければ何もしない（安全側）
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  exit 0
fi
SKILLS_DIR="${PLUGIN_ROOT}/skills"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

FILE_EXISTS=0
if [ -f "$FILE_PATH" ]; then
  FILE_EXISTS=1
fi

HINTS=""

# 形式: "skill_name|detection_regex|extensions|summary"
# extensions が空なら拡張子マッチを行わず regex のみで判定
declare -a SKILL_TABLE=(
  "axum|use axum::|rs|Router 分割、State 注入、Extractor 順序（body 消費は最後）、AppError + IntoResponse"
  "diesel|use diesel::|rs|モデル定義、クエリビルダ、Connection Pool、トランザクション、migration"
  "leptos|use leptos::|rs|view! 構文、signal/memo、server_fn、SSR/CSR 分岐、Axum 統合"
  "valkv-cache|use redis::|rs|キャッシュ戦略、接続プール、TTL 設計、pub/sub"
  "aspnet-core|using Microsoft.AspNetCore|cs|Minimal APIs、DI、ミドルウェア、WebApplicationFactory テスト"
  "entity-framework-core|using Microsoft.EntityFrameworkCore|cs|DbContext、エンティティ定義、Fluent API、migration"
  "blazor|@page |razor|コンポーネント、状態管理、フォームバインディング、bUnit テスト"
  "cargo-toml||toml|セクション順、キー並序、依存ルール（workspace, features）"
  "csproj||csproj|SDK 形式、PropertyGroup、PackageReference、分析設定"
)

for ENTRY in "${SKILL_TABLE[@]}"; do
  IFS='|' read -r SKILL_NAME REGEX EXT SUMMARY <<< "$ENTRY"
  SKILL_PATH="${SKILLS_DIR}/${SKILL_NAME}/SKILL.md"

  [ -f "$SKILL_PATH" ] || continue

  MATCH=0

  if [ -n "$EXT" ]; then
    case "$FILE_PATH" in
      *.${EXT}|*.${EXT}.in) MATCH=1 ;;
    esac
  fi

  if [ "$MATCH" -eq 0 ] && [ "$FILE_EXISTS" -eq 1 ] && [ -n "$REGEX" ]; then
    if grep -qE "$REGEX" "$FILE_PATH" 2>/dev/null; then
      MATCH=1
    fi
  fi

  if [ "$MATCH" -eq 1 ]; then
    # bash が展開するので LLM は実パスで Read できる
    HINTS+="- **${SKILL_NAME}** (\`${SKILL_PATH}\`): ${SUMMARY}\n"
  fi
done

if [ -z "$HINTS" ]; then
  exit 0
fi

cat <<EOF
<skill_hints>
編集対象ファイルに関連する skill があります。詳細が必要なら該当パスを Read してください。

$(printf "%b" "$HINTS")
</skill_hints>
EOF

exit 0
