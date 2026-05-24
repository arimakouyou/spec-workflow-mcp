#!/usr/bin/env bash
# inject-build-cache.sh
#
# PreToolUse (Bash): 実行コマンドに cargo / dotnet が含まれる場合、対応する
# build-cache skill のパスと要約をヒント注入する。
#
# 参照渡し方式: skill 本体は注入せず、ファイルパスと 1 行の要約のみ。必要なら
# Claude が Read ツールで本体を参照する。
#
# 非ブロッキング（常に exit 0）。

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo '')
if [ -z "$COMMAND" ]; then
  exit 0
fi

HINTS=""

add_hint() {
  local skill_name="$1"
  local summary="$2"
  local skill_path="${PLUGIN_ROOT}/skills/${skill_name}/SKILL.md"
  [ -f "$skill_path" ] || return 0
  HINTS+="- **${skill_name}** (\`${skill_path}\`): ${summary}\n"
}

# cargo / rustc / rustup を検出
if echo "$COMMAND" | grep -qE '(^|[[:space:]])cargo([[:space:]]|$)'; then
  add_hint "rust-build-cache" "sccache / target 共有、incremental 設定、CI キャッシュ戦略、ビルド時間短縮"
fi

# dotnet を検出
if echo "$COMMAND" | grep -qE '(^|[[:space:]])dotnet([[:space:]]|$)'; then
  add_hint "dotnet-build-cache" "dotnet build キャッシュ、NuGet キャッシュ、CI 共有、ビルド時間短縮"
fi

if [ -z "$HINTS" ]; then
  exit 0
fi

cat <<EOF
<build_cache_hints>
ビルド関連コマンドに対応する build-cache skill があります。詳細が必要なら該当パスを Read してください。

$(printf "%b" "$HINTS")
</build_cache_hints>
EOF

exit 0
