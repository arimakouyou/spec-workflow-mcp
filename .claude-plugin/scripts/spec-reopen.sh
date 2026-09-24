#!/usr/bin/env bash
# 仕様の変更後に、入力(承認済み文書の断片)が変わった完了済みタスクを求める。
# 完了時のコミット trailer Spec-Inputs と、現在の spec-brief.sh --inputs-only のハッシュを比べる。
# 使い方: spec-reopen.sh <spec> [project-root] [--apply]
# 出力: "reopen<TAB>key<TAB>旧ハッシュ<TAB>新ハッシュ" / "removed<TAB>key"(design から消えた完了済みタスク)
# --apply: reopen の行を spec-git.sh reopen で再オープンする(removed は人の判断に回す)
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-reopen.sh <spec> [project-root] [--apply]}"
shift
apply=0; rootarg=""
for a in "$@"; do case "$a" in --apply) apply=1 ;; *) rootarg="$a" ;; esac; done
root="$(spec_project_root "$rootarg")"

# 各タスクの最新の完了コミットの Spec-Inputs
declare -A recorded
while IFS=$'\t' read -r s t in; do
  [[ "$s" == "$spec" && -n "$t" ]] || continue
  recorded[$t]="$in"
done < <(git -C "$root" log --reverse --format='%(trailers:key=Spec,valueonly,separator=%x20)%x09%(trailers:key=Spec-Task,valueonly,separator=%x20)%x09%(trailers:key=Spec-Inputs,valueonly,separator=%x20)' 2>/dev/null)

plan="$(bash "$SPEC_SCRIPTS_DIR/spec-plan.sh" "$spec" "$root" --tsv)"
reopen=()
while IFS=$'\t' read -r key _ _ _ _ state; do
  [[ "$state" == "done" && -n "${recorded[$key]:-}" ]] || continue
  now="$(bash "$SPEC_SCRIPTS_DIR/spec-brief.sh" "$spec" "$key" "$root" --inputs-only 2>/dev/null | sha256sum | cut -c1-12)"
  if [[ "$now" != "${recorded[$key]}" ]]; then
    printf 'reopen\t%s\t%s\t%s\n' "$key" "${recorded[$key]}" "$now"
    reopen+=("$key")
  fi
done <<<"$plan"

for key in "${!recorded[@]}"; do
  grep -qP "^\Q$key\E\t" <<<"$plan" || printf 'removed\t%s\n' "$key"
done

if (( apply )); then
  for key in "${reopen[@]}"; do
    SPEC_PROJECT_ROOT="$root" bash "$SPEC_SCRIPTS_DIR/spec-git.sh" reopen "$spec" "$key" "仕様の変更で入力が変わった"
  done
fi
