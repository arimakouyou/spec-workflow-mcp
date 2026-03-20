#!/bin/bash
# Hook: Write|Edit - .rs ファイルに対して rustfmt + clippy を実行
set -euo pipefail

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')

echo "$f" | grep -qE '\.rs$' || exit 0

rustfmt "$f"

d="$(dirname "$f")"
while [ "$d" != "/" ]; do
  if [ -f "$d/Cargo.toml" ]; then
    cargo clippy --quiet --all-targets --manifest-path "$d/Cargo.toml" -- -D warnings 2>&1 || exit $?
    break
  fi
  d="$(dirname "$d")"
done
