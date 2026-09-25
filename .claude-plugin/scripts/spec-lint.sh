#!/usr/bin/env bash
# spec 文書を rules/doc-format.md の文法で検査する(決定的 lint)。
# 使い方: spec-lint.sh <spec> [project-root]
# 出力: 違反 1 件 1 行 "CODE<TAB>文書<TAB>場所<TAB>内容"(コード順)。違反があれば exit 1。
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-lint.sh <spec> [project-root]}"
root="$(spec_project_root "${2:-}")"

result="$(spec_index "$root" "$spec" | gawk -f "$SPEC_LIB_DIR/spec-lint.awk" | LC_ALL=C sort)"
if [[ -n "$result" ]]; then
  printf '%s\n' "$result"
  printf 'spec-lint: %s 件の違反(%s)\n' "$(printf '%s\n' "$result" | wc -l)" "$spec" >&2
  exit 1
fi
printf 'spec-lint: 違反なし(%s)\n' "$spec" >&2
