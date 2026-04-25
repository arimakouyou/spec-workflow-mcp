#!/bin/bash
# auto-resume.sh
#
# /spec-implement を wrap してレートリミット中断からの自動再開を実現する。
#
# 使い方:
#   .claude-plugin/scripts/auto-resume.sh [SPEC_ID]
#
# 動作:
#   - claude --print で /spec-implement を非対話実行
#   - exit code を見て分岐:
#     - 0: 完了、ループ終了
#     - 42: レートリミット、sleep してリトライ
#     - 43: ユーザー確認必要、即時終了
#     - その他: 未知のエラー、即時終了
#   - sleep 時間は exponential backoff (60s → 120s → 300s の上限)
#
# 前提:
#   - Orchestrator (spec-implement) が上記 exit code 規約に従うこと
#   - claude CLI が --print モードで headless 実行できること
#
# 環境変数:
#   - MAX_ATTEMPTS    : 最大試行回数 (default: 20)
#   - INITIAL_SLEEP   : 初回 sleep 秒数 (default: 60)
#   - MAX_SLEEP       : sleep 秒数の上限 (default: 300)
#   - LOG_FILE        : ログ出力先 (default: .auto-resume.log)
#
# 注意:
#   - 最大試行回数を設定して無限ループを防ぐ
#   - メトリクス (中断回数・所要時間) を LOG_FILE に記録してレビュー可能にする

set -euo pipefail

SPEC_ID="${1:-}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-20}"
INITIAL_SLEEP="${INITIAL_SLEEP:-60}"
MAX_SLEEP="${MAX_SLEEP:-300}"
LOG_FILE="${LOG_FILE:-.auto-resume.log}"

# Exit code 規約 (Orchestrator と共有)
readonly EXIT_COMPLETED=0
readonly EXIT_RATE_LIMIT=42
readonly EXIT_NEED_USER=43

attempt=0
sleep_seconds=$INITIAL_SLEEP
start_time=$(date +%s)

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[${ts}] $*" | tee -a "$LOG_FILE"
}

log "=== auto-resume started (spec: ${SPEC_ID:-<default>}, max_attempts: ${MAX_ATTEMPTS}) ==="

while [ $attempt -lt $MAX_ATTEMPTS ]; do
  attempt=$((attempt + 1))
  log "Attempt ${attempt}/${MAX_ATTEMPTS}: invoking /spec-implement"

  # claude --print で非対話実行
  # Orchestrator は stdin のプロンプトを受けて /spec-implement を走らせる設計
  if [ -n "$SPEC_ID" ]; then
    PROMPT="/spec-implement --auto-resume ${SPEC_ID}"
  else
    PROMPT="/spec-implement --auto-resume"
  fi

  set +e
  echo "$PROMPT" | claude --print 2>&1 | tee -a "$LOG_FILE"
  EXIT_CODE=${PIPESTATUS[1]}
  set -e

  case $EXIT_CODE in
    "$EXIT_COMPLETED")
      end_time=$(date +%s)
      elapsed=$((end_time - start_time))
      log "=== Completed in ${attempt} attempts, ${elapsed}s total ==="
      exit 0
      ;;
    "$EXIT_RATE_LIMIT")
      log "Rate limit hit. Sleeping ${sleep_seconds}s before retry..."
      sleep "$sleep_seconds"
      # exponential backoff (上限あり)
      sleep_seconds=$((sleep_seconds * 2))
      if [ $sleep_seconds -gt $MAX_SLEEP ]; then
        sleep_seconds=$MAX_SLEEP
      fi
      ;;
    "$EXIT_NEED_USER")
      log "User intervention needed. Exiting."
      exit $EXIT_NEED_USER
      ;;
    *)
      log "Unknown exit code: ${EXIT_CODE}. Exiting."
      exit "$EXIT_CODE"
      ;;
  esac
done

log "=== Max attempts (${MAX_ATTEMPTS}) reached. Giving up. ==="
exit 1
