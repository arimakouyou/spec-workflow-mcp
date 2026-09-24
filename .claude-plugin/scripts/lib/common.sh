#!/usr/bin/env bash
# spec-workflow v2 スクリプト共通の関数。source して使う。

SPEC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # source した側のスクリプトが使う
SPEC_SCRIPTS_DIR="$(dirname "$SPEC_LIB_DIR")"

# プロジェクトルートを決める(引数 > $SPEC_PROJECT_ROOT > カレントから .spec-workflow を上に探す)
spec_project_root() {
  local start="${1:-${SPEC_PROJECT_ROOT:-$PWD}}" dir
  dir="$(cd "$start" && pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.spec-workflow" ]]; then printf '%s\n' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  echo "error: .spec-workflow が見つからない(起点: $start)" >&2
  return 1
}

spec_dir() { printf '%s/.spec-workflow/specs/%s\n' "$1" "$2"; }
steering_dir() { printf '%s/.spec-workflow/steering\n' "$1"; }

# spec の索引(TSV)を標準出力に書く。引数: <project-root> <spec>
spec_index() {
  local root="$1" spec="$2" sdir stdir f
  sdir="$(spec_dir "$root" "$spec")"
  stdir="$(steering_dir "$root")"
  for f in tech.md product.md structure.md; do
    [[ -f "$stdir/$f" ]] && gawk -v doc="$f" -f "$SPEC_LIB_DIR/spec-parse.awk" "$stdir/$f"
  done
  for f in request-spec.md requirements.md design.md test-design.md; do
    [[ -f "$sdir/$f" ]] && gawk -v doc="$f" -f "$SPEC_LIB_DIR/spec-parse.awk" "$sdir/$f"
  done
  if [[ -d "$sdir/evidence" ]]; then
    for f in "$sdir"/evidence/EV-*.md; do
      [[ -f "$f" ]] && printf 'evfile\t%s\n' "$(basename "$f" .md)"
    done
  fi
  printf 'spec\t%s\n' "$spec"
}
