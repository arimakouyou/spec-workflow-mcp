#!/usr/bin/env bash
# aggregate-metrics.sh
#
# .implement-session/metrics.jsonl を集計して plan-redesign の運用判断に
# 必要な指標を出力する。
#
# 使い方:
#   .claude-plugin/scripts/aggregate-metrics.sh <subcommand>
#
# subcommands:
#   summary  — 全体概要 (event 種別別カウント、収集期間)
#   hooks    — Hook 別所要時間ランキング + warning 率 (撤去判断)
#   tools    — Tool 別所要時間ランキング (bottleneck 特定)
#   phases   — Phase 別所要時間 (律速フェーズ特定)
#   rules    — Rule 別 read / violation 集計 (昇格判断 + 撤去判断)
#   speedup [task_id_prefix] — 並列化 speedup 見積もり (task_id_prefix で wave をフィルタ)
#
# 出力:
#   人間可読な集計テーブル (tab 区切り、column コマンドで整形可能)
#
# 関連: .claude/_docs/plans/measurement-framework.md

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
METRICS_FILE="${PROJECT_DIR}/.implement-session/metrics.jsonl"

if ! command -v jq >/dev/null 2>&1; then
  echo "aggregate-metrics: jq is required" >&2
  exit 1
fi

if [ ! -f "$METRICS_FILE" ]; then
  echo "aggregate-metrics: metrics file not found: $METRICS_FILE" >&2
  exit 1
fi

cmd_summary() {
  echo "=== Metrics Summary ==="
  echo
  echo "File: $METRICS_FILE"
  echo "Total events: $(wc -l < "$METRICS_FILE")"
  echo
  echo "Event breakdown:"
  jq -r '.event' "$METRICS_FILE" | sort | uniq -c | sort -rn
  echo
  echo "Date range:"
  echo "  First: $(jq -r 'select(.ts) | .ts' "$METRICS_FILE" | head -1)"
  echo "  Last:  $(jq -r 'select(.ts) | .ts' "$METRICS_FILE" | tail -1)"
}

cmd_hooks() {
  echo "=== Hook 別所要時間ランキング (撤去 / 設計見直し判断) ==="
  echo
  printf "%-30s %10s %10s %10s %10s\n" "Hook" "Total(ms)" "Count" "Avg(ms)" "Warn%"
  echo "$(printf '%80s' | tr ' ' '-')"
  jq -c 'select(.event=="hook")' "$METRICS_FILE" \
    | jq -s -r '
      group_by(.hook) |
      map({
        hook: .[0].hook,
        total: ([.[].duration_ms] | add // 0),
        count: length,
        warn: ([.[] | select(.exit_code != 0)] | length)
      }) |
      sort_by(-.total) |
      .[] |
      [.hook, .total, .count,
       (if .count > 0 then ((.total / .count) | floor) else 0 end),
       (if .count > 0 then ((.warn * 100 / .count) | floor) else 0 end)
      ] |
      @tsv' \
    | awk -F'\t' '{ printf "%-30s %10s %10s %10s %9s%%\n", $1, $2, $3, $4, $5 }'
  echo
  echo "判定基準:"
  echo "  - Avg > 1000ms       → UX 阻害 Hook、軽量化検討"
  echo "  - Warn% > 50%        → false positive 多発、検出条件見直し"
  echo "  - Count = 0 (記録外) → 一度も発火していない、撤去候補"
}

cmd_tools() {
  echo "=== Tool 別所要時間ランキング (bottleneck 特定) ==="
  echo
  printf "%-30s %10s %10s %10s\n" "Tool" "Total(ms)" "Count" "Avg(ms)"
  echo "$(printf '%65s' | tr ' ' '-')"
  jq -c 'select(.event=="tool")' "$METRICS_FILE" \
    | jq -s -r '
      group_by(.tool) |
      map({
        tool: .[0].tool,
        total: ([.[].duration_ms] | add // 0),
        count: length
      }) |
      sort_by(-.total) |
      .[] |
      [.tool, .total, .count,
       (if .count > 0 then ((.total / .count) | floor) else 0 end)
      ] |
      @tsv' \
    | awk -F'\t' '{ printf "%-30s %10s %10s %10s\n", $1, $2, $3, $4 }'

  echo
  echo "=== Bash コマンド分類 (cmd_summary の先頭 2 単語別) ==="
  echo
  printf "%-40s %10s %10s\n" "Command Class" "Total(ms)" "Count"
  echo "$(printf '%65s' | tr ' ' '-')"
  jq -c 'select(.event=="tool" and .tool=="Bash")' "$METRICS_FILE" \
    | jq -s -r '
      map(.cmd_summary |= (split(" ") | .[0:2] | join(" "))) |
      group_by(.cmd_summary) |
      map({
        cmd: .[0].cmd_summary,
        total: ([.[].duration_ms] | add // 0),
        count: length
      }) |
      sort_by(-.total) |
      .[] |
      [.cmd, .total, .count] |
      @tsv' \
    | awk -F'\t' '{ printf "%-40s %10s %10s\n", $1, $2, $3 }'
}

cmd_phases() {
  echo "=== Phase 別所要時間 (律速フェーズ特定) ==="
  echo
  printf "%-30s %10s %10s %10s %10s\n" "Phase" "Total(ms)" "Count" "Avg(ms)" "Ratio%"
  echo "$(printf '%75s' | tr ' ' '-')"
  jq -c 'select(.event=="phase_end")' "$METRICS_FILE" \
    | jq -s -r '
      (([.[].duration_ms] | add) // 1) as $total_all |
      group_by(.phase) |
      map({
        phase: .[0].phase,
        total: ([.[].duration_ms] | add // 0),
        count: length,
        ratio: ((([.[].duration_ms] | add // 0) * 100 / $total_all) | floor)
      }) |
      sort_by(-.total) |
      .[] |
      [.phase, .total, .count,
       (if .count > 0 then ((.total / .count) | floor) else 0 end),
       .ratio
      ] |
      @tsv' \
    | awk -F'\t' '{ printf "%-30s %10s %10s %10s %9s%%\n", $1, $2, $3, $4, $5 }'
  echo
  echo "判定基準 (#16 並列化判断):"
  echo "  - review-worker phase が > 50%   → review bound、並列効果限定的"
  echo "  - cargo build phase が > 60%     → compile bound、sccache hit 率次第"
  echo "  - test phase が > 50% + DB 不要  → test bound、並列化に好適"
}

cmd_rules() {
  echo "=== Rule 別 read 頻度 (使われていない Rule 抽出) ==="
  echo
  printf "%-40s %10s\n" "Rule" "Reads"
  echo "$(printf '%55s' | tr ' ' '-')"
  jq -c 'select(.event=="rule_read")' "$METRICS_FILE" \
    | jq -s -r 'group_by(.rule) | sort_by(-length) | .[] | [.[0].rule, length] | @tsv' \
    | awk -F'\t' '{ printf "%-40s %10s\n", $1, $2 }'

  echo
  echo "=== Rule 別違反検出 (昇格判断) ==="
  echo
  printf "%-50s %10s\n" "Rule" "Violations"
  echo "$(printf '%65s' | tr ' ' '-')"
  jq -c 'select(.event=="rule_violation")' "$METRICS_FILE" \
    | jq -s -r 'group_by(.rule) | sort_by(-length) | .[] | [.[0].rule, length] | @tsv' \
    | awk -F'\t' '{ printf "%-50s %10s\n", $1, $2 }'

  echo
  echo "判定基準:"
  echo "  - 同一 rule の violation >= 2 件 → L1 → L2 昇格候補"
  echo "  - rule_read = 0 + violation = 0  → 効いていない、撤去候補"
}

cmd_speedup() {
  local prefix="${1:-}"
  echo "=== 並列化 speedup 見積もり ==="
  echo
  if [ -n "$prefix" ]; then
    echo "Filter: task_id starts with '$prefix'"
  fi
  echo

  jq -c 'select(.event=="task_end")' "$METRICS_FILE" \
    | jq -s --arg prefix "$prefix" '
      map(select($prefix == "" or (.task_id | startswith($prefix))))
    ' \
    | jq -r '
      if length == 0 then
        "(no task_end events match the filter)"
      else
        ([.[].duration_ms] | add) as $sequential |
        ([.[].duration_ms] | max) as $critical |
        length as $n |
        "Tasks: \($n)",
        "Sequential time: \($sequential)ms (\(($sequential / 1000) | floor)s)",
        "Critical path:   \($critical)ms (\(($critical / 1000) | floor)s)",
        "Speedup ratio:   \(if $critical > 0 then (($sequential * 100 / $critical) | floor) / 100 else 0 end)x"
      end
    '
  echo
  echo "判定基準:"
  echo "  - Speedup ratio >= 1.5  → 並列化に着手する価値あり"
  echo "  - Speedup ratio < 1.5   → 複雑化コストに見合わない、入れない判断"
}

main() {
  local subcmd="${1:-summary}"
  shift || true

  case "$subcmd" in
    summary) cmd_summary "$@" ;;
    hooks)   cmd_hooks "$@" ;;
    tools)   cmd_tools "$@" ;;
    phases)  cmd_phases "$@" ;;
    rules)   cmd_rules "$@" ;;
    speedup) cmd_speedup "$@" ;;
    *)
      echo "aggregate-metrics: usage: $(basename "$0") <summary|hooks|tools|phases|rules|speedup [task_id_prefix]>" >&2
      exit 1
      ;;
  esac
}

main "$@"
