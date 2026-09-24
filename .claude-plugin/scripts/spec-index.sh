#!/usr/bin/env bash
# spec 文書を索引(TSV)に変換して標準出力に書く。
# 使い方: spec-index.sh <spec> [project-root]
# レコード形式は lib/spec-parse.awk の先頭コメントを参照。
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-index.sh <spec> [project-root]}"
root="$(spec_project_root "${2:-}")"
spec_index "$root" "$spec"
