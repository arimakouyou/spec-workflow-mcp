#!/usr/bin/env bash
# spec-workflow: tasks.md 読了後のガードレール
# PostToolUse(Read) フックから呼び出される

FILE_PATH=$(jq -r '.tool_input.file_path // empty')

if echo "$FILE_PATH" | grep -qE '[.]spec-workflow/specs/[^/]+/tasks[.]md$'; then
  echo "⛔ [spec-workflow] STOP — tasks.md を読みました。"
  echo ""
  echo "この後、いかなる理由があっても直接コードを書いてはなりません。"
  echo "次の行動: ユーザーに「/spec-implement を実行してください」と案内して即座に停止すること。"
  echo ""
  echo "禁止（問答無用）:"
  echo "  - Edit / Write / Bash でコードを書く"
  echo "  - /spec-implement を自分で起動する"
  echo "  - 「はい」「進めて」「OK」等の返答を受けて実装を開始する"
fi
