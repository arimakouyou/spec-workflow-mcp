#!/usr/bin/env bash
# 無人で実装を進めるループ。claude -p で /spec-implement を実行し、API エラーで止まったら待って再開する。
# 使い方: spec-resume-loop.sh <spec> [project-root] [--max N]
# 終了コード: 0 すべて完了 / 43 escalate などで人の判断が必要 / 44 再開回数の上限
# 位置の正はコミット trailer なので、何度再開しても同じタスクをやり直すだけで進み方は変わらない。
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-resume-loop.sh <spec> [project-root] [--max N]}"
shift
max=20; rootarg=""
while (( $# > 0 )); do
  case "$1" in
    --max) max="$2"; shift ;;
    *) rootarg="$1" ;;
  esac
  shift
done
root="$(spec_project_root "$rootarg")"
resume="$root/.spec-workflow/.resume"
wait_s=60

for ((i = 1; i <= max; i++)); do
  if bash "$SPEC_SCRIPTS_DIR/spec-next.sh" "$spec" "$root" >/dev/null 2>&1; then :; else
    rc=$?
    if (( rc == 2 )); then echo "spec-resume-loop: すべてのタスクが完了した"; exit 0; fi
    echo "spec-resume-loop: 仕様が ready でない。人の判断が必要" >&2; exit 43
  fi
  rm -f "$resume"
  echo "spec-resume-loop: 実行 $i / $max"
  (cd "$root" && printf '/spec-implement %s\n' "$spec" | claude -p) || true
  if [[ -f "$resume" ]]; then
    echo "spec-resume-loop: $(jq -r '.reason' "$resume") で中断。${wait_s} 秒待って再開する"
    sleep "$wait_s"
    wait_s=$(( wait_s * 2 > 1800 ? 1800 : wait_s * 2 ))
    continue
  fi
  # 中断ではなく止まった: escalate か、人の判断が必要な状態
  if ! bash "$SPEC_SCRIPTS_DIR/spec-next.sh" "$spec" "$root" >/dev/null 2>&1; then
    [[ $? -eq 2 ]] && { echo "spec-resume-loop: すべてのタスクが完了した"; exit 0; }
  fi
  echo "spec-resume-loop: 中断以外の理由で止まった。セッションの出力を確認する" >&2
  exit 43
done
echo "spec-resume-loop: 再開回数の上限($max)に達した" >&2
exit 44
