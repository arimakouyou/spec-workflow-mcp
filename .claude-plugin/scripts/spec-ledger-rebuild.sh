#!/usr/bin/env bash
# 台帳導入前の承認記録(approvals/{key}/*.json と .snapshots/)から承認台帳を再構築する。
# 使い方: spec-ledger-rebuild.sh <spec> [project-root] [--write]
# 既定は標準出力に台帳 JSON を書くだけ。--write は実装セッション外でのみ ledger.json に書き込む。
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

key="${1:?usage: spec-ledger-rebuild.sh <spec> [project-root] [--write]}"
shift
write=0; rootarg=""
for a in "$@"; do
  case "$a" in
    --write) write=1 ;;
    *) rootarg="$a" ;;
  esac
done
root="$(spec_project_root "$rootarg")"
dir="$root/.spec-workflow/approvals/$key"
[[ -d "$dir" ]] || { echo "error: $dir が無い" >&2; exit 1; }

# 旧フローは承認後に承認リクエストの JSON を削除するため、承認の記録はスナップショットから取る。
# trigger が approved のスナップショットごとに、本文の sha256 を求める
events="$(mktemp)"
trap 'rm -f "$events"' EXIT
for meta in "$dir"/.snapshots/*/metadata.json; do
  [[ -f "$meta" ]] || continue
  snapdir="$(dirname "$meta")"
  doc="$(basename "$snapdir" .md)"
  case "$doc" in request-spec|requirements|design|test-design|product|tech|structure) ;; *) continue ;; esac
  while IFS=$'\t' read -r at id file; do
    [[ -f "$snapdir/$file" ]] || continue
    sha="$(jq -j '.content' "$snapdir/$file" | sha256sum | cut -d' ' -f1)"
    printf '%s\t%s\t%s\t%s\n' "$at" "$doc" "$sha" "$id" >> "$events"
  done < <(jq -r '.snapshots[] | select(.trigger == "approved") | [.timestamp, .approvalId, .filename] | @tsv' "$meta")
done

# 時刻順に並べ、各承認の時点での上流の最新承認 sha を upstream として記録する
ledger="$(sort "$events" | jq -R -s '
  def ups($d): {"request-spec": [], "requirements": ["request-spec"], "design": ["requirements"], "test-design": ["requirements", "design"],
            "product": [], "tech": [], "structure": []}[$d];
  (split("\n") | map(select(length > 0) | split("\t") | {at: .[0], doc: .[1], sha256: .[2], approvalId: .[3]}))
  | reduce .[] as $e ({version: 1, entries: {}, history: []};
      . as $l
      | ([ups($e.doc)[] | {key: ., value: ($l.entries[.].sha256 // null)} | select(.value != null)] | from_entries) as $up
      | .entries[$e.doc] = {sha256: $e.sha256, approvalId: $e.approvalId, approvedAt: $e.at, upstream: $up}
      | .history += [{event: "approved", doc: $e.doc, sha256: $e.sha256, approvalId: $e.approvalId, at: $e.at, upstream: $up}])
')"

if (( write )); then
  if [[ -e "$root/.spec-workflow/.active" ]]; then
    echo "error: 実装セッション中は台帳を書き換えない(.spec-workflow/.active がある)" >&2
    exit 1
  fi
  tmp="$dir/ledger.json.$$.tmp"
  printf '%s\n' "$ledger" > "$tmp"
  mv "$tmp" "$dir/ledger.json"
  echo "ledger.json を書き込んだ: $dir/ledger.json" >&2
else
  printf '%s\n' "$ledger"
fi
