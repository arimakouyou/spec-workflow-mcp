#!/usr/bin/env bash
# StopFailure(rate_limit|overloaded|server_error): 実装セッションが API エラーで止まったことを記録する。
# 次のセッションの SessionStart がこれを読んで再開位置を伝える(位置の正はコミット trailer)。
set -uo pipefail

input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
active="$root/.spec-workflow/.active"
[[ -f "$active" ]] || exit 0
reason="$(jq -r '.error // .error_type // .reason // .matcher // "unknown"' <<<"$input")"
jq -n --arg spec "$(tr -d '[:space:]' < "$active")" --arg reason "$reason" --arg at "$(date -u +%FT%TZ)" \
  '{spec: $spec, reason: $reason, at: $at}' > "$root/.spec-workflow/.resume"
rm -f "$root/.spec-workflow/.agent-lock"
exit 0
