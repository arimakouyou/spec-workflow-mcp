#!/usr/bin/env bash
# grilling の 1 ラウンドを JEV(jevcli)に答えさせ、閾値で決着した問いと未決の問いに分ける。
# 使い方: spec-grill-jev.sh <request.json>   request.json は jevcli の入力({"state": ..., "questions": {...}})
# 出力(stdout、JSON 1 行): {"decided": {<問>: {...}}, "undecided": {<問>: {...}}, "model": ..., "cost": USD}
# 閾値: noul は yes の確率 ≥0.85 か ≤0.15、choice は最大確率 ≥0.6 かつ 1 位と 2 位の差 ≥0.2、score は最大確率 ≥0.5
# 終了コード: 0 成功 / 1 jevcli の失敗(stdout に jevcli の error JSON)/ 2 使い方の誤り / 4 jevcli が無い / その他 応答を解釈できない
set -euo pipefail

req="${1:?usage: spec-grill-jev.sh <request.json>}"
[[ -f "$req" ]] || { echo "spec-grill-jev: $req が無い" >&2; exit 2; }
jev="${JEVCLI:-jevcli}"
command -v "$jev" >/dev/null || { echo "spec-grill-jev: $jev が見つからない" >&2; exit 4; }

if ! res="$("$jev" < "$req")"; then
  printf '%s\n' "$res"
  exit 1
fi

jq -c '
  # jevcli の confidence は最大確率と一致しないことがあるため、閾値は probabilities から求める
  def ranked: [.probabilities | to_entries[]] | sort_by(-.value);
  def judge:
    if .type == "noul" then
      (if .noul >= 0.85 then {decided: true, answer: "yes"}
       elif .noul <= 0.15 then {decided: true, answer: "no"}
       else {decided: false} end) + {type, yes: .noul}
    elif .type == "choice" then
      ranked as $r | ($r[0].value - ($r[1].value // 0)) as $m
      | {decided: ($r[0].value >= 0.6 and $m >= 0.2), type, answer: $r[0].key,
         top: $r[0].value, margin: $m, probabilities}
    elif .type == "score" then
      ranked as $r
      | {decided: ($r[0].value >= 0.5), type, answer: .legend[$r[0].key], top: $r[0].value, probabilities}
    else {decided: false, type} end;
  (.answers | with_entries(.value |= judge)) as $a
  | {decided: ($a | with_entries(select(.value.decided)) | map_values(del(.decided))),
     undecided: ($a | with_entries(select(.value.decided | not)) | map_values(del(.decided))),
     model, cost: .usage.cost}
' <<<"$res"
