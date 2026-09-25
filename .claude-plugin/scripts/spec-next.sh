#!/usr/bin/env bash
# 次に着手するタスクを返す。実装に入れるのは 4 文書がすべて approved のときだけ。
# 使い方: spec-next.sh <spec> [project-root]
# 出力: "key<TAB>type<TAB>phase<TAB>title<TAB>tests"
# 終了コード: 0 次のタスクあり / 2 すべて完了 / 3 仕様が ready でない(状態を stderr に出す)
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-next.sh <spec> [project-root]}"
root="$(spec_project_root "${2:-}")"

if ! states="$(bash "$SPEC_SCRIPTS_DIR/spec-state.sh" "$spec" "$root" --ready)"; then
  echo "spec-next: 仕様が ready でない(4 文書すべてが approved である必要がある)" >&2
  printf '%s\n' "$states" >&2
  exit 3
fi

next="$(bash "$SPEC_SCRIPTS_DIR/spec-plan.sh" "$spec" "$root" --tsv | awk -F'\t' '$6 == "open" { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5; exit }')"
if [[ -z "$next" ]]; then
  echo "DONE"
  exit 2
fi
printf '%s\n' "$next"
