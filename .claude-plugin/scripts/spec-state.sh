#!/usr/bin/env bash
# 承認台帳から spec の各文書の状態を判定する(contract/approval-ledger-v1.md §5 の Bash 実装)。
# 使い方: spec-state.sh <spec | steering> [project-root] [--ready]
# 出力: "doc<TAB>state"(state: pending / unapproved / modified / stale / approved)
# --ready: 4 文書すべてが approved なら exit 0、そうでなければ状態を出力して exit 1
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

key="${1:?usage: spec-state.sh <spec|steering> [project-root] [--ready]}"
shift
ready=0; rootarg=""
for a in "$@"; do
  case "$a" in
    --ready) ready=1 ;;
    *) rootarg="$a" ;;
  esac
done
root="$(spec_project_root "$rootarg")"
approvals="$root/.spec-workflow/approvals"
ledger="$approvals/$key/ledger.json"

if [[ "$key" == "steering" ]]; then
  docs=(product tech structure)
else
  docs=(request-spec requirements design test-design)
fi

doc_path() {
  if [[ "$key" == "steering" ]]; then printf '.spec-workflow/steering/%s.md' "$1"
  else printf '.spec-workflow/specs/%s/%s.md' "$key" "$1"; fi
}
upstream_of() {
  case "$1" in
    requirements) echo "request-spec" ;;
    design) echo "requirements" ;;
    test-design) echo "requirements design" ;;
    tech) echo "product" ;;
    structure) echo "product tech" ;;
    *) echo "" ;;
  esac
}

# status が pending の承認リクエストの filePath
pending="$(find "$approvals" -mindepth 2 -maxdepth 2 -name '*.json' ! -name ledger.json -print0 2>/dev/null \
  | xargs -0 -r jq -r 'select(.status? == "pending") | .filePath' 2>/dev/null | sed 's#^\./##' || true)"

entry_sha() { [[ -f "$ledger" ]] && jq -r --arg d "$1" '.entries[$d].sha256 // empty' "$ledger" || true; }
file_sha() { local f; f="$root/$(doc_path "$1")"; [[ -f "$f" ]] && sha256sum "$f" | cut -d' ' -f1 || true; }
entry_up() { [[ -f "$ledger" ]] && jq -r --arg d "$1" --arg u "$2" '.entries[$d].upstream[$u] // empty' "$ledger" || true; }

declare -A state
all=1
for doc in "${docs[@]}"; do
  p="$(doc_path "$doc")"
  if grep -qxF "$p" <<<"$pending"; then st=pending
  else
    sha="$(entry_sha "$doc")"
    if [[ -z "$sha" ]]; then st=unapproved
    else
      cur=""
      [[ -f "$root/$p" ]] && cur="$(sha256sum "$root/$p" | cut -d' ' -f1)"
      if [[ "$cur" != "$sha" ]]; then st=modified
      else
        st=approved
        for u in $(upstream_of "$doc"); do
          if [[ "$key" == "steering" ]]; then
            # steering は上流の承認を求めない。承認時に記録した上流ファイルの sha と現在の sha を比べる
            if [[ "$(entry_up "$doc" "$u")" != "$(file_sha "$u")" ]]; then st=stale; fi
          elif [[ "${state[$u]}" != approved || "$(entry_up "$doc" "$u")" != "$(entry_sha "$u")" ]]; then st=stale; fi
        done
      fi
    fi
  fi
  state[$doc]=$st
  [[ "$st" == approved ]] || all=0
  printf '%s\t%s\n' "$doc" "$st"
done

if (( ready )); then
  (( all )) && exit 0
  exit 1
fi
