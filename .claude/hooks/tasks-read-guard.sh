#!/usr/bin/env bash
# spec-workflow: guardrail triggered after reading tasks.md
# Called from the PostToolUse(Read) hook

FILE_PATH=$(jq -r '.tool_input.file_path // empty' 2>/dev/null || echo '')

if echo "$FILE_PATH" | grep -qE '[.]spec-workflow/specs/[^/]+/tasks[.]md$'; then
  echo "⛔ [spec-workflow] STOP — tasks.md has been read."
  echo ""
  echo "You must not write code directly for any reason after this point."
  echo "Next action: Guide the user with 'Please run /spec-implement' and stop immediately."
  echo ""
  echo "Prohibited (no exceptions):"
  echo "  - Writing code via Edit / Write / Bash"
  echo "  - Launching /spec-implement yourself"
  echo "  - Starting implementation in response to 'yes', 'go ahead', 'OK', etc."
fi
