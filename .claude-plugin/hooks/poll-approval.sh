#!/usr/bin/env bash
# poll-approval.sh — 承認ファイルをポーリングし、ステータス変更またはタイムアウトで終了する
set -euo pipefail

# --- デフォルト値 ---
TIMEOUT=3600      # 60分
INTERVAL=15       # 15秒
WORKFLOW_ROOT=".spec-workflow"

# --- 終了コード ---
# 0: 承認ステータス変更（approved/needs-revision/rejected）
# 1: タイムアウト
# 2: エラー（引数不正、ファイル未検出、jq 未インストール等）

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

Exit codes:
  0  承認ステータスが変更された（stdout に JSON 出力）
  1  タイムアウト
  2  エラー
EOF
  exit 2
}

# --- 引数パース ---
APPROVAL_ID=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        echo "--timeout requires a numeric value" >&2
        usage
      fi
      TIMEOUT="$2"
      shift 2
      ;;
    --interval)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        echo "--interval requires a numeric value" >&2
        usage
      fi
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
  exit 2
fi

# --- 数値バリデーション ---
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -le 0 ]]; then
  echo "--timeout must be a positive integer, got: $TIMEOUT" >&2
  exit 2
fi
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -le 0 ]]; then
  echo "--interval must be a positive integer, got: $INTERVAL" >&2
  exit 2
fi

APPROVAL_ID="${POSITIONAL_ARGS[0]}"
if [[ ${#POSITIONAL_ARGS[@]} -ge 2 ]]; then
  WORKFLOW_ROOT="${POSITIONAL_ARGS[1]}"
fi

# --- approvalId のバリデーション ---
if ! [[ "$APPROVAL_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo '{"error":"approvalId contains invalid characters (allowed: a-zA-Z0-9_-)"}' >&2
  exit 2
fi

# --- jq の存在確認 ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 2
fi

# --- 承認ファイルの検索 ---
find_approval_file() {
  local approvals_dir="${WORKFLOW_ROOT}/approvals"
  if [[ ! -d "$approvals_dir" ]]; then
    return 1
  fi
  # approvals/{categoryName}/{approvalId}.json を再帰検索（-print -quit で SIGPIPE 回避）
  find "$approvals_dir" -name "${APPROVAL_ID}.json" -type f -print -quit 2>/dev/null
}

APPROVAL_FILE=""
APPROVAL_FILE=$(find_approval_file || true)

if [[ -z "$APPROVAL_FILE" ]]; then
  echo "{\"error\":\"approval file not found\",\"approvalId\":\"${APPROVAL_ID}\"}" >&2
  exit 2
fi

# --- ポーリングループ ---
ELAPSED=0
PARSE_FAILURES=0
MAX_PARSE_FAILURES=3

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  if [[ ! -f "$APPROVAL_FILE" ]]; then
    echo "{\"error\":\"approval file disappeared\",\"approvalId\":\"${APPROVAL_ID}\"}" >&2
    exit 2
  fi

  if STATUS=$(jq -r '.status // "unknown"' "$APPROVAL_FILE" 2>/dev/null); then
    PARSE_FAILURES=0
  else
    PARSE_FAILURES=$((PARSE_FAILURES + 1))
    if [[ $PARSE_FAILURES -ge $MAX_PARSE_FAILURES ]]; then
      echo "{\"error\":\"approval file parse failed after ${MAX_PARSE_FAILURES} consecutive attempts\",\"approvalId\":\"${APPROVAL_ID}\"}" >&2
      exit 2
    fi
    STATUS="unknown"
  fi

  # 既知の終了ステータスをホワイトリストで判定
  if [[ "$STATUS" == "approved" || "$STATUS" == "needs-revision" || "$STATUS" == "rejected" ]]; then
    # ステータスが変更された — JSON 全体を出力して終了
    if ! jq '.' "$APPROVAL_FILE" 2>/dev/null; then
      echo "{\"error\":\"failed to read approval result\",\"approvalId\":\"${APPROVAL_ID}\"}" >&2
      exit 2
    fi
    exit 0
  fi

  # pending / unknown 以外の未知のステータスはエラー
  if [[ "$STATUS" != "pending" && "$STATUS" != "unknown" ]]; then
    echo "{\"error\":\"unexpected approval status\",\"status\":\"${STATUS}\",\"approvalId\":\"${APPROVAL_ID}\"}" >&2
    exit 2
  fi

  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

# --- タイムアウト ---
echo "{\"error\":\"timeout\",\"approvalId\":\"${APPROVAL_ID}\",\"elapsed\":${ELAPSED},\"timeout\":${TIMEOUT}}" >&2
exit 1
