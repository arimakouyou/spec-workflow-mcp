#!/usr/bin/env bash
# タスクに渡す資料(brief)を、承認済み文書の断片だけから組み立てる。
# tasks.md には事実を書かないので、実装する側が読むのはこの brief と、そこに載った ID の正本だけ。
# 使い方: spec-brief.sh <spec> <task-key> [project-root] [--inputs-only]
#   --inputs-only  承認済み文書に由来する断片だけを出す(申し送り・前回のレビュー指摘を除く)。
#                  コミット trailer の Spec-Inputs と、仕様変更後の再オープン判定(spec-reopen.sh)に使う
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

inputs_only=0; args=()
for a in "$@"; do if [[ "$a" == --inputs-only ]]; then inputs_only=1; else args+=("$a"); fi; done
spec="${args[0]:?usage: spec-brief.sh <spec> <task-key> [project-root] [--inputs-only]}"
key="${args[1]:?usage: spec-brief.sh <spec> <task-key> [project-root] [--inputs-only]}"
root="$(spec_project_root "${args[2]:-}")"
sdir="$(spec_dir "$root" "$spec")"
tech="$(steering_dir "$root")/tech.md"

index="$(spec_index "$root" "$spec")"
row="$(bash "$SPEC_SCRIPTS_DIR/spec-plan.sh" "$spec" "$root" --tsv | awk -F'\t' -v k="$key" '$1 == k')"
[[ -n "$row" ]] || { echo "error: タスク $key は tasks にない" >&2; exit 1; }
IFS=$'\t' read -r _ type phase title tests _ <<<"$row"
[[ "$tests" == "-" ]] && tests=""

slice() { bash "$SPEC_SCRIPTS_DIR/spec-slice.sh" "$spec" "$1" "$root"; printf '\n'; }
field() { awk -F'\t' -v id="$1" -v f="$2" '$1 == "field" && $3 == id && $4 == f { print $5; exit }' <<<"$index"; }
ids_in() { { grep -oE "$1-[0-9]+(\.[0-9]+)?" || true; } | awk '!seen[$0]++'; }
owned_mods() { awk -F'\t' -v o="$1" '$1 == "field" && $4 == "Owner" && $5 == o { print $3 }' <<<"$index"; }
tech_section() { awk -v s="## $1" '$0 == s { p = 1; print; next } /^## / { p = 0 } p' "$tech"; }
list() { tr ',' '\n' <<<"$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^-\?$' || true; }

echo "# Brief: $key $title"
echo
echo "- Spec: $spec"
echo "- Type: $type"
echo "- Phase: $phase"
echo
echo "資料はこの brief と、ここに載っている ID の正本(design.md / test-design.md / requirements.md)だけを使う。"
echo "テストケースの正本は test-design、シグネチャの正本は DES の Interfaces。両者が食い違えば選ばずに blocked(spec_conflict) を返す。"
echo

case "$type" in
  des-*|tst-*)
    echo "## 対象"; echo
    slice "$key"
    for m in $(owned_mods "$key"); do slice "$m"; done
    deps="$(field "$key" Depends)"
    impl="$(field "$key" Implements | ids_in DES)"
    if [[ -n "$(list "$deps")$impl" ]]; then
      echo "## 依存先(このタスクが呼ぶ・実装する Interfaces)"; echo
      for d in $(list "$deps") $impl; do slice "$d"; for m in $(owned_mods "$d"); do slice "$m"; done; done
    fi
    sat="$(field "$key" Satisfies)"
    if [[ -n "$(list "$sat")" ]]; then
      echo "## 満たす受入基準"; echo
      for a in $(list "$sat"); do
        if [[ "$a" == *.* ]]; then slice "$a"; else slice "$a"; fi
      done
    fi
    if [[ -n "$tests" ]]; then
      echo "## テスト(RED で書くテストの正本)"; echo
      for t in $(list "$tests"); do slice "$t"; done
      used="$(for t in $(list "$tests"); do bash "$SPEC_SCRIPTS_DIR/spec-slice.sh" "$spec" "$t" "$root"; done | ids_in TST)"
      if [[ -n "$used" ]]; then
        echo "## テストが使うテスト支援(TST)"; echo
        for u in $used; do slice "$u"; done
      fi
    fi
    echo "## テストの置き場所とコマンド"; echo
    tech_section "Test Layout"; echo
    tech_section "Test Commands"; echo
    ;;
  it|st)
    echo "## テスト"; echo
    for t in $(list "$tests"); do slice "$t"; done
    targets="$(for t in $(list "$tests"); do awk -F'\t' -v id="$t" '$1 == "field" && $3 == id && $4 == "Target" { print $5 }' <<<"$index"; done | awk '!s[$0]++')"
    echo "## 対象"; echo
    for g in $targets; do slice "$g"; done
    uses="$(for t in $(list "$tests"); do field "$t" Uses; done | tr ',' '\n' | sed 's/[[:space:]]//g' | grep -v '^$' | awk '!s[$0]++' || true)"
    if [[ -n "$uses" ]]; then echo "## テスト支援(TST)"; echo; for u in $uses; do slice "$u"; done; fi
    deps="$(for g in $targets; do bash "$SPEC_SCRIPTS_DIR/spec-slice.sh" "$spec" "$g" "$root" 2>/dev/null; done | ids_in DEP)"
    if [[ -n "$deps" ]]; then echo "## 前提にするライブラリの契約"; echo; for d in $deps; do slice "$d"; done; fi
    echo "## コマンド"; echo; tech_section "Test Commands"; echo
    ;;
  smk)
    echo "## スモーク対象"; echo
    echo "$tests"; echo
    for a in $(list "$tests" | grep -oE 'API-[0-9]+' | awk '!s[$0]++'); do slice "$a"; done
    tech_section "Health"; echo
    echo "スモークの 4 層は rules/test-taxonomy.md §1 を参照。"
    ;;
  refactor)
    echo "## リファクタ backlog"; echo
    if [[ -f "$sdir/refactor-backlog.md" ]]; then cat "$sdir/refactor-backlog.md"; else echo "(backlog は空)"; fi
    echo; echo "テストファイルは変更しない。振る舞いを変えない。"
    ;;
  review)
    echo "## この Phase のタスク"; echo
    bash "$SPEC_SCRIPTS_DIR/spec-plan.sh" "$spec" "$root" --tsv | awk -F'\t' -v p="$phase" '$3 == p { print "- " $1 " " $4 " (" $6 ")" }'
    echo; echo "機械検査は spec-phase-check.sh が行う。レビューは rules/verdict.md に従う。"
    ;;
  final)
    echo "## E2E"; echo
    for t in $(list "$tests"); do slice "$t"; done
    for j in $(for t in $(list "$tests"); do field "$t" Target; done | awk '!s[$0]++'); do slice "$j"; done
    echo "## コマンド"; echo; tech_section "Test Commands"; echo
    ;;
  tools)
    echo "## 必要ツール"; echo
    for t in $(list "$tests"); do slice "$t"; done
    ;;
esac

(( inputs_only )) && exit 0

# 自分宛ての申し送りと、前回のレビュー指摘
if [[ -f "$sdir/handoffs.jsonl" ]]; then
  h="$(jq -r --arg k "$key" 'select(.to == $k) | "- (\(.from)) \(.text)"' "$sdir/handoffs.jsonl")"
  if [[ -n "$h" ]]; then echo "## 申し送り"; echo; printf '%s\n\n' "$h"; fi
fi
if [[ -f "$sdir/runs/$key/review.json" ]]; then
  echo "## 前回のレビュー指摘"; echo
  jq -r '.findings[]? | "- [\(.severity)] \(.ids // [] | join(", ")) \(.file // "") \(.text)"' "$sdir/runs/$key/review.json"
  echo
fi
