#!/usr/bin/env bash
# PreToolUse(Bash): 実装セッション中(.spec-workflow/.active)のコミット経路を spec-git.sh に限る。拒否は exit 2。
#   - 生の git commit / merge / reset / push / rebase / cherry-pick を拒否(cd x && git … や git -C … も検出)
#   - spec-git.sh のサブコマンドを呼べる主体を agent_type で制限する
#   - 承認台帳・承認記録への Bash での書き込みを拒否する
set -uo pipefail

input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
[[ -n "$cmd" ]] || exit 0
root="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
name="$(jq -r '.agent_type // empty' <<<"$input")"; name="${name##*:}"
agent_id="$(jq -r '.agent_id // empty' <<<"$input")"

deny() { echo "guard-git: $1" >&2; exit 2; }

# 承認台帳・承認記録は承認サーバーだけが書く(セッションの内外を問わない)
if grep -qE "(>>?|tee([[:space:]]+-a)?)[[:space:]]*[\"']?[^[:space:]]*\.spec-workflow/approvals/|(^|[;&|[:space:]])(mv|cp|rm|sed[[:space:]]+-i)[[:space:]].*\.spec-workflow/approvals/" <<<"$cmd"; then
  deny ".spec-workflow/approvals/ は承認サーバーだけが書く"
fi

[[ -f "$root/.spec-workflow/.active" ]] || exit 0

if grep -qE '(^|[;&|(`]|[[:space:]])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|merge|reset|push|rebase|cherry-pick|revert)([[:space:]]|$)' <<<"$cmd"; then
  deny "実装セッション中のコミットは spec-git.sh 経由だけ(生の git commit / merge / reset / push は使わない)"
fi

if [[ "$cmd" =~ spec-git\.sh[[:space:]]+([a-z]+) ]]; then
  sub="${BASH_REMATCH[1]}"
  main=0; [[ -z "$agent_id" ]] && main=1
  case "$sub" in
    commit|verdict|archive)
      [[ "$name" == review-worker ]] || deny "spec-git.sh $sub は review-worker だけが実行できる" ;;
    record)
      if [[ "$name" != review-worker ]]; then
        [[ $main -eq 1 && "$cmd" =~ P0-TOOLS ]] || deny "spec-git.sh record は review-worker(ツール確認はオーケストレーター)だけが実行できる"
      fi ;;
    checkpoint)
      [[ "$name" == impl-worker || "$name" == integ-test-worker ]] || deny "spec-git.sh checkpoint は実装 agent だけが実行できる" ;;
    start|discard|reopen|docs)
      [[ $main -eq 1 ]] || deny "spec-git.sh $sub はオーケストレーター(メインエージェント)だけが実行できる" ;;
  esac
fi
exit 0
