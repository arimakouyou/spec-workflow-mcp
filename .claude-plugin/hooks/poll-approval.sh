#!/usr/bin/env bash
# poll-approval.sh — 承認ファイルをポーリングし、ステータス変更またはタイムアウトで終了する
set -euo pipefail

# --- デフォルト値 ---
TIMEOUT=3600      # 60分
INTERVAL=15       # 15秒
WORKFLOW_ROOT=".spec-workflow"

# --- 使い方 ---
usage() {
  cat >&2 <<EOF
Usage: poll-approval.sh <approvalId> [workflowRoot] [--timeout N] [--interval N]

Arguments:
  approvalId    承認 ID（必須）
  workflowRoot  ワークフロールートディレクトリ（デフォルト: .spec-workflow）

Options:
  --timeout N   タイムアウト秒数（デフォルト: 3600）
  --interval N  ポーリング間隔秒数（デフォルト: 15）
EOF
  exit 1
}

# --- 引数パース ---
APPROVAL_ID=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -lt 1 ]]; then
  echo '{"error":"approvalId is required"}' >&2
  exit 1
fi

APPROVAL_ID="${POSITIONAL_ARGS[0]}"
if [[ ${#POSITIONAL_ARGS[@]} -ge 2 ]]; then
  WORKFLOW_ROOT="${POSITIONAL_ARGS[1]}"
fi

# --- jq の存在確認 ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# --- 承認ファイルの検索 ---
find_approval_file() {
  local approvals_dir="${WORKFLOW_ROOT}/approvals"
  if [[ ! -d "$approvals_dir" ]]; then
    return 1
  fi
  # approvals/{categoryName}/{approvalId}.json を再帰検索
  find "$approvals_dir" -name "${APPROVAL_ID}.json" -type f 2>/dev/null | head -1
}

APPROVAL_FILE=""
APPROVAL_FILE=$(find_approval_file || true)

if [[ -z "$APPROVAL_FILE" ]]; then
  echo "{\"error\":\"approval file not found\",\"approvalId\":\"${APPROVAL_ID}\"}" >&2
  exit 1
fi

# --- ポーリングループ ---
ELAPSED=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  if [[ ! -f "$APPROVAL_FILE" ]]; then
    echo "{\"error\":\"approval file disappeared\",\"approvalId\":\"${APPROVAL_ID}\"}" >&2
    exit 1
  fi

  STATUS=$(jq -r '.status // "unknown"' "$APPROVAL_FILE" 2>/dev/null || echo "unknown")

  if [[ "$STATUS" != "pending" && "$STATUS" != "unknown" ]]; then
    # ステータスが変更された — JSON 全体を出力して終了
    jq '.' "$APPROVAL_FILE"
    exit 0
  fi

  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

# --- タイムアウト ---
echo "{\"error\":\"timeout\",\"approvalId\":\"${APPROVAL_ID}\",\"elapsed\":${ELAPSED},\"timeout\":${TIMEOUT}}" >&2
exit 1
