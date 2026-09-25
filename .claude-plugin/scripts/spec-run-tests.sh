#!/usr/bin/env bash
# steering/tech.md の Test Commands で、指定した層のテストを実行する。
# 使い方: spec-run-tests.sh <layer> [project-root]   layer: UT / CT / IT / ST / E2E / SMK
# 終了コード: テストコマンドの終了コード / 0 層を使わない宣言(-)/ 3 層の行が無い(黙って SKIP しない)
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

layer="${1:?usage: spec-run-tests.sh <UT|CT|IT|ST|E2E|SMK> [project-root]}"
root="$(spec_project_root "${2:-}")"
cmd="$(tech_table_value "$root" "Test Commands" "$layer")"

if [[ -z "$cmd" ]]; then
  echo "spec-run-tests: tech.md の Test Commands に $layer の行が無い" >&2
  exit 3
fi
if [[ "$cmd" == "-" ]]; then
  echo "spec-run-tests: $layer は使わない層として宣言されている(tech.md)"
  exit 0
fi
echo "spec-run-tests: $layer: $cmd"
cd "$root"
bash -c "$cmd"
