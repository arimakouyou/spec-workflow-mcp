#!/usr/bin/env bash
# spec-implement セッション中の Task 呼び出しに対し BEGIN イベントを記録する PreToolUse フック。
# - セッションファイル (.spec-workflow/.implement-session.json) が存在するときのみ能動動作
# - <spec-step> タグ欠落時は exit 2 でブロック (silent failure 防止)
# - progress.md (task 単位) に BEGIN 行を append
# - git checkpoint tag を best-effort で作成 (失敗しても継続)
#
# 参照: .claude/_docs/plans/step-resume-mechanism.md §4.4, §4.8, §5.1, §8

set -uo pipefail

INPUT=$(cat)

# 実験で判明: hook 実行時の cwd は Claude Code から渡される cwd = プロジェクトルート
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD"
fi

SESSION_FILE=".spec-workflow/.implement-session.json"

# spec-implement セッション中でなければ素通し
if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

# Task tool (内部名 Agent) 以外は素通し
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
if [ "$TOOL_NAME" != "Agent" ] && [ "$TOOL_NAME" != "Task" ]; then
  exit 0
fi

PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // ""' 2>/dev/null || true)

# <spec-step ...> タグを prompt 先頭側から抽出
TAG=$(printf '%s' "$PROMPT" | grep -oE '<spec-step[^>]*>' | head -n 1 || true)

if [ -z "$TAG" ]; then
  {
    echo "⛔ [progress-begin] spec-implement セッション中の Task 呼び出しに <spec-step> タグがありません"
    echo "   Task tool の prompt 先頭に以下形式のタグを含めてください:"
    echo "   <spec-step spec=\"{specName}\" task=\"{taskId}\" step=\"{stepId}\" attempt=\"{N}\">"
    echo "   欠落は再開位置の喪失を招くためブロックします"
  } >&2
  exit 2
fi

extract_attr() {
  local name="$1"
  printf '%s' "$TAG" | grep -oE "${name}=\"[^\"]*\"" | head -n 1 | sed -E 's/^[^"]*"([^"]*)".*$/\1/' || true
}

SPEC=$(extract_attr spec)
TASK=$(extract_attr task)
STEP=$(extract_attr step)
ATTEMPT=$(extract_attr attempt)

if [ -z "$SPEC" ] || [ -z "$TASK" ] || [ -z "$STEP" ]; then
  {
    echo "⛔ [progress-begin] <spec-step> タグに必須属性 (spec/task/step) が欠落しています"
    echo "   受信タグ: $TAG"
  } >&2
  exit 2
fi

if [ -z "$ATTEMPT" ]; then
  ATTEMPT=1
fi

# step id バリデーション (progress-log-parser と規約一致)
if ! printf '%s' "$STEP" | grep -qE '^[a-z0-9-]+$'; then
  echo "⛔ [progress-begin] step id が不正です: $STEP (許容: [a-z0-9-]+)" >&2
  exit 2
fi

# task id を sanitize ('.' と '/' を '-' に)
SANITIZED_TASK=$(printf '%s' "$TASK" | tr './' '--')

PROGRESS_DIR=".spec-workflow/specs/${SPEC}/Implementation Logs"
PROGRESS_FILE="${PROGRESS_DIR}/task-${SANITIZED_TASK}_progress.md"

mkdir -p "$PROGRESS_DIR"

# 新規ファイルならヘッダを書く
if [ ! -f "$PROGRESS_FILE" ]; then
  {
    printf '# Progress Log: Task %s\n' "$TASK"
    printf '# spec=%s task=%s\n' "$SPEC" "$TASK"
    printf '# format: <ISO8601>\\t<EVENT>\\t<STEP_ID>\\t<META_JSON>\n'
    printf '# hook + skill が append する append-only ログ (手編集禁止)\n'
  } > "$PROGRESS_FILE"
fi

# git checkpoint tag を best-effort で作成
CHECKPOINT=""
TAG_NAME="spec-impl/${SPEC}/task-${SANITIZED_TASK}/step-${STEP}/attempt-${ATTEMPT}"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git tag -f "$TAG_NAME" >/dev/null 2>&1; then
    CHECKPOINT="$TAG_NAME"
  fi
fi

PROMPT_HASH=$(printf '%s' "$PROMPT" | sha1sum | awk '{print substr($1,1,12)}')

META=$(jq -cn \
  --arg prompt_hash "$PROMPT_HASH" \
  --arg checkpoint "$CHECKPOINT" \
  --argjson attempt "${ATTEMPT}" \
  '{prompt_hash: $prompt_hash, checkpoint: $checkpoint, attempt: $attempt}' 2>/dev/null || printf '{}')

TS=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
printf '%s\tBEGIN\t%s\t%s\n' "$TS" "$STEP" "$META" >> "$PROGRESS_FILE"

exit 0
