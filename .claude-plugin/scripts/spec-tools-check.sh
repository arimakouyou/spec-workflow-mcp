#!/usr/bin/env bash
# design の TOOL-N を確かめる。Required: yes のツールが無い・古いときは停止する(黙って SKIP しない)。
# 使い方: spec-tools-check.sh <spec> [project-root]
# 出力: "TOOL-N<TAB>name<TAB>ok|missing|old|warn<TAB>detail"
# 終了コード: 0 必須ツールがすべて揃っている / 3 必須ツールが無い・古い
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-tools-check.sh <spec> [project-root]}"
root="$(spec_project_root "${2:-}")"

fail=0
while IFS=$'\t' read -r id name min check install required; do
  [[ -n "$id" ]] || continue
  out="$(cd "$root" && bash -c "$check" 2>&1)" && rc=0 || rc=$?
  if (( rc != 0 )); then
    st=missing; detail="$check が失敗(導入: $install)"
  else
    ver="$(grep -oE '[0-9]+(\.[0-9]+)+' <<<"$out" | head -1 || true)"
    if [[ -n "$min" && -n "$ver" && "$(printf '%s\n%s\n' "$min" "$ver" | sort -V | head -1)" != "$min" ]]; then
      st=old; detail="$ver < $min(更新: $install)"
    else
      st=ok; detail="${ver:-version 不明}"
    fi
  fi
  if [[ "$st" != ok ]]; then
    if [[ "$required" == yes ]]; then fail=1; else st=warn; fi
  fi
  printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$st" "$detail"
done < <(spec_index "$root" "$spec" | awk -F'\t' '
  $1 == "def" && $3 ~ /^TOOL-/ { order[++n] = $3; name[$3] = $4 }
  $1 == "field" && $3 ~ /^TOOL-/ { f[$3, $4] = $5 }
  END { for (i = 1; i <= n; i++) { id = order[i]; print id "\t" name[id] "\t" f[id, "Min"] "\t" f[id, "Check"] "\t" f[id, "Install"] "\t" f[id, "Required"] } }')

if (( fail )); then
  echo "spec-tools-check: 必須ツールが揃っていない。導入してから再実行する" >&2
  exit 3
fi
