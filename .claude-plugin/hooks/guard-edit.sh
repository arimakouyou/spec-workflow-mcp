#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit): 仕様の正本と生成物を守る。拒否は exit 2(stderr がモデルに届く)。
#   1. .spec-workflow/approvals/ 以下は承認サーバーだけが書く
#   2. tasks.md / trace.md は生成物(spec-plan.sh / spec-trace.sh が書く)
#   3. 承認済みの文書は、上流の変更で stale になったもの、または spec-change で開いたもの(.change-open)だけ編集できる
#   4. 実装セッション中(.spec-workflow/.active)は、メインエージェントがソースを直接編集しない(サブエージェントに委ねる)
set -uo pipefail

input="$(cat)"
file="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[[ -n "$file" ]] || exit 0
agent_id="$(jq -r '.agent_id // empty' <<<"$input")"
root="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
[[ -n "$root" ]] || exit 0

case "$file" in /*) abs="$file" ;; *) abs="$root/$file" ;; esac
rel="${abs#"$root"/}"

deny() { echo "guard-edit: $1" >&2; exit 2; }

case "$rel" in
  .spec-workflow/approvals/*)
    deny "$rel は承認サーバーだけが書く(承認台帳・承認記録)。承認はダッシュボードで行う" ;;
  .spec-workflow/specs/*/tasks.md|.spec-workflow/specs/*/trace.md)
    deny "$rel は生成物。design / test-design を直してから spec-plan.sh / spec-trace.sh で生成し直す" ;;
esac

if [[ "$rel" =~ ^\.spec-workflow/specs/([^/]+)/(request-spec|requirements|design|test-design)\.md$ ]]; then
  spec="${BASH_REMATCH[1]}"; doc="${BASH_REMATCH[2]}"
  ledger="$root/.spec-workflow/approvals/$spec/ledger.json"
  if [[ -f "$ledger" ]] && jq -e --arg d "$doc" '.entries[$d]' "$ledger" >/dev/null 2>&1; then
    marker="$root/.spec-workflow/specs/$spec/.change-open"
    if [[ -f "$marker" ]] && grep -qxF "$doc" "$marker"; then exit 0; fi
    state="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh" "$spec" "$root" 2>/dev/null | awk -F'\t' -v d="$doc" '$1 == d { print $2 }')"
    [[ "$state" == stale || "$state" == pending ]] && exit 0
    deny "$doc.md は承認済み($state)。変更は /spec-change $spec で開いてから行う"
  fi
  exit 0
fi

if [[ "$rel" =~ ^\.spec-workflow/steering/(product|tech|structure)\.md$ ]]; then
  doc="${BASH_REMATCH[1]}"
  ledger="$root/.spec-workflow/approvals/steering/ledger.json"
  if [[ -f "$ledger" ]] && jq -e --arg d "$doc" '.entries[$d]' "$ledger" >/dev/null 2>&1; then
    marker="$root/.spec-workflow/steering/.change-open"
    if [[ -f "$marker" ]] && grep -qxF "$doc" "$marker"; then exit 0; fi
    state="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh" steering "$root" 2>/dev/null | awk -F'\t' -v d="$doc" '$1 == d { print $2 }')"
    [[ "$state" == stale || "$state" == pending ]] && exit 0
    deny "steering/$doc.md は承認済み。変更は /steering-doc で revise として開く(.spec-workflow/steering/.change-open に $doc を書く)"
  fi
  exit 0
fi

# 実装セッション中のメインエージェントによるソース編集
if [[ -f "$root/.spec-workflow/.active" && -z "$agent_id" ]]; then
  case "$rel" in
    .spec-workflow/*|.claude/*) exit 0 ;;
  esac
  deny "実装セッション中はメインエージェントがソースを直接編集しない。impl-worker などのサブエージェントに委ねる($rel)"
fi
exit 0
