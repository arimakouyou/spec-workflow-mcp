#!/usr/bin/env bash
# session-manage.sh
#
# Implementation session state manager. Creates and maintains
# `.implement-session.json` and `.implement-session.lock` at the project root
# so that dormant hooks（inject-spec / verify-tests-run / detect-new-files /
# log-implementation）become active during /spec-implement.
# これらの hook は lockfile の存在を dormancy 判定に使うため、`end` で一斉に dormant に
# 戻る。resume-hint だけはセッション本体を見て "Active: yes/no" を報告する役割のため、
# lockfile が無くても動作する。
#
# Subcommands:
#   init <spec_id>                       — 新規セッション作成（ロック取得）
#   start-task <task_id> [phase]         — current_task / current_phase を更新
#   complete-task <task_id> [commit_hash] — completed_tasks に追加し current_task をクリア
#   update-phase <phase>                 — current_phase を更新（RED / GREEN / REFACTOR / REVIEW 等）
#   mark-failure <category> [detail]     — last_failure_* を更新
#   clear-failure                        — last_failure_* をクリア
#   end                                  — lockfile 削除 + セッションを完了マーク（本体は保持）
#                                          hook は全て dormant に戻る
#   archive                              — セッション本体を archived に退避（spec-archive 時）
#
# 特徴:
#   - `CLAUDE_PROJECT_DIR` を優先、未設定なら pwd を使用
#   - jq があれば JSON を正確に更新、無ければ最小限の sed-based fallback
#   - 失敗しても常に exit 0（Orchestrator のタスクループを止めない方針）
#
# 注意:
#   - session ファイルは「真のソース」ではない。ヒントとして扱い、実状態は git / FS を正
#   - レートリミット中断時に phase 書き換え前に落ちる可能性があるため、hook 側でも
#     「信用しすぎない」前提で設計されている

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_FILE="${PROJECT_DIR}/.implement-session.json"
LOCKFILE="${PROJECT_DIR}/.implement-session.lock"

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

have_jq() {
  command -v jq >/dev/null 2>&1
}

# 既存セッションを受け取り jq で transform、なければ初期値から作成
jq_update() {
  local filter="$1"
  if [ ! -f "$SESSION_FILE" ]; then
    echo '{}' | jq "$filter" > "$SESSION_FILE"
  else
    local tmp="${SESSION_FILE}.tmp.$$"
    jq "$filter" "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  fi
}

cmd_init() {
  local spec_id="${1:-}"
  if [ -z "$spec_id" ]; then
    echo "session-manage: init requires <spec_id>" >&2
    return 0
  fi

  local ts
  ts="$(now_iso)"

  if have_jq; then
    jq -n \
      --arg spec_id "$spec_id" \
      --arg ts "$ts" \
      --arg pid "$$" \
      '{
        spec_id: $spec_id,
        session_start: $ts,
        session_updated: $ts,
        orchestrator_pid: ($pid | tonumber),
        current_task: null,
        current_phase: null,
        phase_started_at: null,
        phase_checkpoint: {},
        retry_count: 0,
        last_failure_category: null,
        last_failure_detail: null,
        rate_limit_state: { hit_at: null, reset_at: null, model: null },
        escalation: null,
        completed_tasks: [],
        remaining_tasks: [],
        agents: { implementer_last_run: null, reviewer_last_run: null }
      }' > "$SESSION_FILE"
  else
    # Fallback: 最小限のシリアライズ
    cat > "$SESSION_FILE" <<EOF
{
  "spec_id": "${spec_id}",
  "session_start": "${ts}",
  "session_updated": "${ts}",
  "orchestrator_pid": $$,
  "current_task": null,
  "current_phase": null,
  "phase_started_at": null,
  "phase_checkpoint": {},
  "retry_count": 0,
  "last_failure_category": null,
  "last_failure_detail": null,
  "rate_limit_state": {"hit_at": null, "reset_at": null, "model": null},
  "escalation": null,
  "completed_tasks": [],
  "remaining_tasks": [],
  "agents": {"implementer_last_run": null, "reviewer_last_run": null}
}
EOF
  fi

  # lockfile（pid と開始時刻を記録）
  echo "pid=$$" > "$LOCKFILE"
  echo "started=${ts}" >> "$LOCKFILE"

  echo "session-manage: initialized session for spec '${spec_id}'"
}

cmd_start_task() {
  local task_id="${1:-}"
  local phase="${2:-RED}"
  if [ -z "$task_id" ]; then
    echo "session-manage: start-task requires <task_id>" >&2
    return 0
  fi
  if [ ! -f "$SESSION_FILE" ]; then
    echo "session-manage: no active session (run init first)" >&2
    return 0
  fi

  local ts
  ts="$(now_iso)"

  if have_jq; then
    jq_update \
      ". + { \
        current_task: \"${task_id}\", \
        current_phase: \"${phase}\", \
        phase_started_at: \"${ts}\", \
        session_updated: \"${ts}\", \
        phase_checkpoint: {} \
      }"
  else
    # fallback: 既存ファイルの末尾に情報を追加する（簡易）
    echo "session-manage: jq not available, start-task best-effort only" >&2
  fi

  echo "session-manage: start-task ${task_id} (phase=${phase})"
}

cmd_update_phase() {
  local phase="${1:-}"
  if [ -z "$phase" ]; then
    echo "session-manage: update-phase requires <phase>" >&2
    return 0
  fi
  if [ ! -f "$SESSION_FILE" ]; then
    return 0
  fi

  local ts
  ts="$(now_iso)"

  if have_jq; then
    jq_update \
      ". + { \
        current_phase: \"${phase}\", \
        phase_started_at: \"${ts}\", \
        session_updated: \"${ts}\" \
      }"
  fi

  echo "session-manage: update-phase ${phase}"
}

cmd_complete_task() {
  local task_id="${1:-}"
  local commit_hash="${2:-}"
  if [ -z "$task_id" ]; then
    echo "session-manage: complete-task requires <task_id>" >&2
    return 0
  fi
  if [ ! -f "$SESSION_FILE" ]; then
    return 0
  fi

  local ts
  ts="$(now_iso)"

  if have_jq; then
    jq_update \
      ". + { \
        current_task: null, \
        current_phase: null, \
        phase_started_at: null, \
        phase_checkpoint: {}, \
        session_updated: \"${ts}\" \
      } | .completed_tasks += [{ task_id: \"${task_id}\", commit_hash: \"${commit_hash}\", completed_at: \"${ts}\" }]"
  fi

  echo "session-manage: complete-task ${task_id}"
}

cmd_mark_failure() {
  local category="${1:-unknown}"
  local detail="${2:-}"
  if [ ! -f "$SESSION_FILE" ]; then
    return 0
  fi

  local ts
  ts="$(now_iso)"

  if have_jq; then
    jq_update \
      ". + { \
        last_failure_category: \"${category}\", \
        last_failure_detail: $(printf '%s' "$detail" | jq -Rs .), \
        retry_count: ((.retry_count // 0) + 1), \
        session_updated: \"${ts}\" \
      }"
  fi
}

cmd_clear_failure() {
  if [ ! -f "$SESSION_FILE" ]; then
    return 0
  fi
  local ts
  ts="$(now_iso)"
  if have_jq; then
    jq_update \
      ". + { \
        last_failure_category: null, \
        last_failure_detail: null, \
        retry_count: 0, \
        session_updated: \"${ts}\" \
      }"
  fi
}

cmd_end() {
  # lockfile だけ削除（＝非アクティブ）。session 本体は参考情報として残す。
  # hook の dormancy 判定は lockfile の存在なので、この時点で全て dormant に戻る
  # （resume-hint のみセッション本体を見て "Active: no" を報告する役割のため対象外）
  rm -f "$LOCKFILE"

  if [ -f "$SESSION_FILE" ] && have_jq; then
    jq_update ". + { session_updated: \"$(now_iso)\" }"
  fi

  echo "session-manage: session ended (lockfile removed, session file preserved)"
}

cmd_archive() {
  # デフォルト保存先は archive-service.ts と同じ `.spec-workflow/archive/` ルート
  local archive_dir="${1:-${PROJECT_DIR}/.spec-workflow/archive/sessions}"
  if [ ! -f "$SESSION_FILE" ]; then
    echo "session-manage: no session to archive"
    return 0
  fi
  mkdir -p "$archive_dir"
  local ts
  ts="$(date -u +%Y%m%dT%H%M%S)"
  mv "$SESSION_FILE" "$archive_dir/implement-session-${ts}.json"
  rm -f "$LOCKFILE"
  echo "session-manage: archived to ${archive_dir}/implement-session-${ts}.json"
}

main() {
  local subcmd="${1:-}"
  shift || true

  case "$subcmd" in
    init)             cmd_init "$@" ;;
    start-task)       cmd_start_task "$@" ;;
    update-phase)     cmd_update_phase "$@" ;;
    complete-task)    cmd_complete_task "$@" ;;
    mark-failure)     cmd_mark_failure "$@" ;;
    clear-failure)    cmd_clear_failure "$@" ;;
    end)              cmd_end "$@" ;;
    archive)          cmd_archive "$@" ;;
    "")
      echo "session-manage: usage: $(basename "$0") <init|start-task|update-phase|complete-task|mark-failure|clear-failure|end|archive> [args...]" >&2
      ;;
    *)
      echo "session-manage: unknown subcommand '${subcmd}'" >&2
      ;;
  esac

  # Orchestrator のフローを止めないため、失敗しても常に exit 0
  exit 0
}

main "$@"
