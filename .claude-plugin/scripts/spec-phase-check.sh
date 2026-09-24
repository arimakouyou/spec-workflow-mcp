#!/usr/bin/env bash
# Phase の区切り(P{n}-REVIEW)で行う機械検査。結果を runs/P{n}-REVIEW/phase-check.json に書き、review-worker が読む。
# 使い方: spec-phase-check.sh <spec> <phase> [project-root]
# 検査: 仕様 ready・lint / ここまでの UT・CT・IT・ST・SMK / format・lint・audit /
#       完了済み DES・TST のシグネチャ適合 / 依存方向(use crate::<layer>)
# 終了コード: 0 すべて ok / 1 NG あり
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-phase-check.sh <spec> <phase> [project-root]}"
phase="${2:?phase が必要}"
root="$(spec_project_root "${3:-}")"
sdir="$(spec_dir "$root" "$spec")"
out="$sdir/runs/P$phase-REVIEW"
mkdir -p "$out"
results="[]"
add() { results="$(jq --arg c "$1" --arg s "$2" --arg d "$3" '. + [{check: $c, status: $s, detail: $d}]' <<<"$results")"; printf '%-4s %-12s %s\n' "$2" "$1" "$3"; }

if bash "$SPEC_SCRIPTS_DIR/spec-state.sh" "$spec" "$root" --ready >/dev/null; then add spec ok "4 文書が approved"; else add spec NG "仕様が ready でない"; fi
if lint="$(bash "$SPEC_SCRIPTS_DIR/spec-lint.sh" "$spec" "$root" 2>&1)"; then add lint ok "違反なし"; else add lint NG "$lint"; fi

for l in UT CT IT ST SMK; do
  if o="$(bash "$SPEC_SCRIPTS_DIR/spec-run-tests.sh" "$l" "$root" 2>&1)"; then add "test-$l" ok "$(tail -1 <<<"$o")"; else add "test-$l" NG "$(tail -20 <<<"$o")"; fi
done

for c in format lint audit; do
  q="$(tech_table_value "$root" "Quality Commands" "$c")"
  [[ -n "$q" && "$q" != "-" ]] || { add "quality-$c" ok "使わない(tech.md)"; continue; }
  if o="$(cd "$root" && bash -c "$q" 2>&1)"; then add "quality-$c" ok "$q"; else add "quality-$c" NG "$(tail -20 <<<"$o")"; fi
done

# 完了済みの DES / TST のシグネチャが design と一致する
idx="$(spec_index "$root" "$spec")"
done_keys="$(bash "$SPEC_SCRIPTS_DIR/spec-plan.sh" "$spec" "$root" --tsv | awk -F'\t' '$6 == "done" && $1 ~ /^(DES|TST)-/ { print $1 }')"
sig_ng=""
for k in $done_keys; do
  iface="$(awk -F'\t' -v id="$k" '$1 == "code" && $3 == id && $4 == "Interfaces" { print $5 }' <<<"$idx")"
  [[ -n "$iface" ]] || continue
  src=""
  for f in $(awk -F'\t' -v id="$k" '$1 == "field" && $3 == id && $4 == "Files" { print $5 }' <<<"$idx" | tr ',' ' '); do
    [[ -f "$root/$f" ]] && src="$src$(cat "$root/$f")"$'\n'
  done
  missing="$(gawk -f "$SPEC_LIB_DIR/signorm.awk" <<<"$iface" | sort -u | comm -23 - <(gawk -f "$SPEC_LIB_DIR/signorm.awk" <<<"$src" | sort -u))"
  [[ -z "$missing" ]] || sig_ng="$sig_ng $k: $missing"
done
if [[ -z "$sig_ng" ]]; then add signature ok "完了済みの DES / TST は design と一致"; else add signature NG "$sig_ng"; fi

# 依存方向: Layer のファイルが、許可されていない Layer を use crate::<layer> で参照していない
arch_ng="$(awk -F'\t' '
  $1 == "text" && $2 == "design.md" && $3 == "Layers" && $6 ~ /^\|/ && $6 !~ /^\|[-[:space:]|]+\|?$/ {
    n = split($6, c, /\|/); l = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", l); d = c[4]; gsub(/^[ \t]+|[ \t]+$/, "", d)
    if (l != "Layer" && l != "") { layers[l] = 1; deps[l] = d } }
  $1 == "field" && $3 ~ /^DES-/ && $4 == "Layer" { lay[$3] = $5 }
  $1 == "field" && $3 ~ /^DES-/ && $4 == "Files" { files[$3] = $5 }
  END { for (id in lay) { if (lay[id] == "-") continue; n = split(files[id], f, /,[[:space:]]*/)
          for (i = 1; i <= n; i++) print lay[id] "\t" f[i] "\t" deps[lay[id]] }
        for (l in layers) print "#LAYER\t" l }' <<<"$idx" | {
  layer_names=""; rows=""
  while IFS=$'\t' read -r a b c; do
    if [[ "$a" == "#LAYER" ]]; then layer_names="$layer_names $b"; else rows="$rows$a"$'\t'"$b"$'\t'"$c"$'\n'; fi
  done
  while IFS=$'\t' read -r lay file allowed; do
    [[ -n "$file" && -f "$root/$file" ]] || continue
    for other in $layer_names; do
      [[ "$other" == "$lay" ]] && continue
      [[ ",$(tr -d ' ' <<<"$allowed")," == *",$other,"* ]] && continue
      if grep -qE "(use|crate)::$other(::|;|\\b)|use crate::$other\\b" "$root/$file"; then echo "$file ($lay) → $other"; fi
    done
  done <<<"$rows"
})"
if [[ -z "$arch_ng" ]]; then add architecture ok "依存方向の違反なし"; else add architecture NG "$arch_ng"; fi

jq -n --arg phase "$phase" --argjson r "$results" '{phase: $phase, results: $r, ok: ([$r[] | select(.status == "NG")] | length == 0)}' > "$out/phase-check.json"
[[ "$(jq -r .ok "$out/phase-check.json")" == true ]]
