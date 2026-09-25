#!/usr/bin/env bash
# ID で指定したブロック(見出しから、同じか上位の次の見出しまで)を文書から抜き出す。
# 受入基準(REQ-N.M)はその 1 行を返す。
# 使い方: spec-slice.sh <spec> <ID> [project-root]
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-slice.sh <spec> <ID> [project-root]}"
id="${2:?usage: spec-slice.sh <spec> <ID> [project-root]}"
root="$(spec_project_root "${3:-}")"
sdir="$(spec_dir "$root" "$spec")"

case "$id" in
  RQ-*) doc=request-spec.md ;;
  REQ-*|NFR-*|JRN-*) doc=requirements.md ;;
  DES-*|MOD-*|API-*|TST-*|DEP-*|TOOL-*|KD-*) doc=design.md ;;
  UT-*|CT-*|IT-*|ST-*|E2E-*) doc=test-design.md ;;
  *) echo "error: 未対応の ID: $id" >&2; exit 2 ;;
esac

out="$(gawk -v id="$id" '
  BEGIN { found = 0; lvl = 0 }
  /^[[:space:]]*```/ { fence = !fence }
  !fence && match($0, /^(#+)[[:space:]]+(.*)$/, h) {
    if (found && length(h[1]) <= lvl) exit
    if (!found && (h[2] == id || index(h[2], id ": ") == 1)) { found = 1; lvl = length(h[1]) }
  }
  found { print; next }
  id ~ /^REQ-[0-9]+\.[0-9]+$/ && index($0, "- " id ": ") == 1 { print; exit }
' "$sdir/$doc")"

if [[ -z "$out" ]]; then
  echo "error: $id が $doc に無い" >&2
  exit 1
fi
printf '%s\n' "$out"
