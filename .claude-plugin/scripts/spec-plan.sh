#!/usr/bin/env bash
# design / test-design から実装タスクを導出し、tasks.md を生成する(手で書かない・承認しない)。
# 使い方: spec-plan.sh <spec> [project-root] [--check | --tsv | --stdout]
#   既定     tasks.md を書き出す
#   --check  生成結果と既存の tasks.md が一致しなければ exit 1(手編集・生成漏れの検出)
#   --tsv    "key<TAB>type<TAB>phase<TAB>title<TAB>tests<TAB>open|done" を標準出力に書く
#   --stdout tasks.md の内容を標準出力に書く
# 完了状態はコミットの trailer(Spec: <spec> / Spec-Task: <key>、再オープンは Spec-Reopen: <key>)から求める。
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-plan.sh <spec> [project-root] [--check|--tsv|--stdout]}"
shift
mode="write"; rootarg=""
for a in "$@"; do
  case "$a" in
    --check) mode=check ;;
    --tsv) mode=tsv ;;
    --stdout) mode=stdout ;;
    *) rootarg="$a" ;;
  esac
done
root="$(spec_project_root "$rootarg")"
sdir="$(spec_dir "$root" "$spec")"

done_keys="$(spec_done_keys "$root" "$spec")"

if [[ "$mode" == tsv ]]; then
  spec_index "$root" "$spec" | gawk -v done="$done_keys" -v mode=tsv -f "$SPEC_LIB_DIR/spec-plan.awk"
  exit 0
fi

generated="$(spec_index "$root" "$spec" | gawk -v done="$done_keys" -v mode=md -f "$SPEC_LIB_DIR/spec-plan.awk")"

case "$mode" in
  stdout) printf '%s\n' "$generated" ;;
  write)
    printf '%s\n' "$generated" > "$sdir/tasks.md"
    echo "tasks.md を生成した: $sdir/tasks.md" >&2 ;;
  check)
    if [[ ! -f "$sdir/tasks.md" ]] || ! diff -u "$sdir/tasks.md" <(printf '%s\n' "$generated") >&2; then
      echo "spec-plan: tasks.md が design / test-design / コミット履歴から生成した内容と一致しない" >&2
      exit 1
    fi
    echo "spec-plan: tasks.md は生成結果と一致" >&2 ;;
esac
