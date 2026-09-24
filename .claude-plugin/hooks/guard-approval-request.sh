#!/usr/bin/env bash
# PreToolUse(mcp__*__approvals): 承認リクエストの前に決定的な検査を強制する。拒否は exit 2。
#   - tasks.md は生成物なので依頼できない
#   - spec 文書は spec-lint.sh、design はさらに spec-sigcheck.sh が通ること
#   - steering 文書は spec-lint.sh _steering が通ること
set -uo pipefail

input="$(cat)"
[[ "$(jq -r '.tool_input.action // empty' <<<"$input")" == request ]] || exit 0
fp="$(jq -r '.tool_input.filePath // empty' <<<"$input")"
root="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
[[ -n "$fp" && -n "$root" ]] || exit 0
fp="${fp#./}"
scripts="${CLAUDE_PLUGIN_ROOT}/scripts"

deny() { printf 'guard-approval-request: %s\n' "$1" >&2; exit 2; }

if [[ "$fp" =~ ^\.spec-workflow/specs/([^/]+)/tasks\.md$ ]]; then
  deny "tasks.md は spec-plan.sh の生成物で、承認の対象ではない"
fi

if [[ "$fp" =~ ^\.spec-workflow/specs/([^/]+)/(request-spec|requirements|design|test-design)\.md$ ]]; then
  spec="${BASH_REMATCH[1]}"; doc="${BASH_REMATCH[2]}"
  if ! out="$(bash "$scripts/spec-lint.sh" "$spec" "$root" 2>&1)"; then
    deny "$(printf 'spec-lint が通らない。/spec-review で直してから依頼する\n%s' "$out")"
  fi
  if [[ "$doc" == design ]]; then
    out="$(bash "$scripts/spec-sigcheck.sh" "$spec" "$root" 2>&1)"; rc=$?
    if (( rc != 0 )); then
      deny "$(printf 'spec-sigcheck が通らない(exit %s)。シグネチャを直すか、必要なツールを導入してから依頼する\n%s' "$rc" "$out")"
    fi
  fi
  exit 0
fi

if [[ "$fp" =~ ^\.spec-workflow/steering/(product|tech|structure)\.md$ ]]; then
  if ! out="$(bash "$scripts/spec-lint.sh" _steering "$root" 2>&1)"; then
    deny "$(printf 'steering の spec-lint が通らない\n%s' "$out")"
  fi
fi
exit 0
