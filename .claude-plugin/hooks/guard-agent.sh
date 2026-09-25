#!/usr/bin/env bash
# PreToolUse(Agent): 実装セッション中(.spec-workflow/.active)の agent 起動を検査する。拒否は exit 2。
#   1. 直列: 別の agent が実行中(.agent-lock)なら起動しない。ロックは SubagentStop で解除する
#      (Agent ツールは非同期で、PostToolUse は起動直後に発火するため。docs/plugin/hook-probe.md)
#   2. プロンプトの先頭に TASK: <key> / SPEC: <spec> があり、spec が実装中のものと一致する
#   3. タスクの種類と agent の対応、実装 → 検証 → レビューの順序
set -uo pipefail

input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
active="$root/.spec-workflow/.active"
[[ -f "$active" ]] || exit 0

deny() { echo "guard-agent: $1" >&2; exit 2; }

sub="$(jq -r '.tool_input.subagent_type // empty' <<<"$input")"
name="${sub##*:}"
prompt="$(jq -r '.tool_input.prompt // empty' <<<"$input")"

# 仕様の調査・文書作成は実装の順序と無関係
case "$name" in Explore|spec-author|spec-reviewer) exit 0 ;; esac

spec="$(tr -d '[:space:]' < "$active")"
task="$(sed -n 's/^TASK:[[:space:]]*\([^[:space:]]*\).*/\1/p' <<<"$prompt" | head -1)"
pspec="$(sed -n 's/^SPEC:[[:space:]]*\([^[:space:]]*\).*/\1/p' <<<"$prompt" | head -1)"
[[ -n "$task" && -n "$pspec" ]] || deny "プロンプトの先頭に TASK: <key> と SPEC: <spec> を書く"
[[ "$pspec" == "$spec" ]] || deny "実装中の spec は $spec(プロンプトは $pspec)"

# 1. 直列
lock="$root/.spec-workflow/.agent-lock"
if [[ -f "$lock" ]]; then
  age=$(( $(date +%s) - $(stat -c %Y "$lock") ))
  if (( age < 7200 )); then
    deny "別の agent が実行中($(cat "$lock"))。完了通知を待ってから次を起動する"
  fi
fi

# 3. 種類と順序
type="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-plan.sh" "$spec" "$root" --tsv 2>/dev/null | awk -F'\t' -v k="$task" '$1 == k { print $2 }')"
[[ -n "$type" ]] || deny "タスク $task は $spec の tasks にない"
runs="$root/.spec-workflow/specs/$spec/runs/$task"
case "$name" in
  impl-worker)
    [[ "$type" == des-* || "$type" == refactor ]] || deny "impl-worker は DES / REFACTOR タスク用($task は $type)" ;;
  integ-test-worker)
    [[ "$type" == tst-* || "$type" =~ ^(it|st|smk|final)$ ]] || deny "integ-test-worker は TST / IT / ST / SMK / FINAL 用($task は $type)" ;;
  unit-test-engineer)
    [[ "$type" =~ ^(des-logic|des-types|refactor)$ ]] || deny "unit-test-engineer は logic / types / REFACTOR の検証用($task は $type)"
    [[ -f "$runs/impl.json" ]] || deny "実装の記録が無い。先に実装 agent を完了させる" ;;
  frontend-test-engineer)
    [[ "$type" == des-ui ]] || deny "frontend-test-engineer は ui の検証用($task は $type)"
    [[ -f "$runs/impl.json" ]] || deny "実装の記録が無い。先に実装 agent を完了させる" ;;
  integ-test-auditor)
    [[ "$type" =~ ^(it|st|smk|final)$ ]] || deny "integ-test-auditor は IT / ST / SMK / FINAL の監査用($task は $type)"
    [[ -f "$runs/impl.json" ]] || deny "実装の記録が無い。先に実装 agent を完了させる" ;;
  review-worker)
    if [[ "$type" != review ]]; then
      [[ -f "$runs/impl.json" ]] || deny "実装の記録が無い。レビューは実装と検証の後"
      if [[ "$type" =~ ^(des-logic|des-types|des-ui|it|st|smk|refactor|final)$ ]]; then
        [[ -f "$runs/verify.json" ]] || deny "検証の記録が無い。レビューは検証の後"
      fi
    else
      [[ -f "$runs/phase-check.json" ]] || deny "Phase の機械検査(spec-phase-check.sh)を先に実行する"
    fi ;;
  *) deny "実装セッション中に起動できない agent: $sub" ;;
esac

printf '%s %s %s\n' "$name" "$task" "$(date -u +%FT%TZ)" > "$lock"
exit 0
