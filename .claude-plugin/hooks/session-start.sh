#!/usr/bin/env bash
# SessionStart(startup|resume|compact): 実装セッションの状態と再開位置をモデルに渡す(stdout はコンテキストに入る)。
# 状態の正は git のコミット trailer と承認台帳。.active / .resume は目印にすぎない。
set -uo pipefail

input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
[[ -n "$root" && -d "$root/.spec-workflow" ]] || exit 0
active="$root/.spec-workflow/.active"
resume="$root/.spec-workflow/.resume"
[[ -f "$active" || -f "$resume" ]] || exit 0

spec="$(cat "$active" 2>/dev/null || true)"
[[ -n "$spec" ]] || spec="$(jq -r '.spec // empty' "$resume" 2>/dev/null || true)"
[[ -n "$spec" ]] || exit 0
scripts="${CLAUDE_PLUGIN_ROOT}/scripts"

echo "## spec-workflow: 実装セッション($spec)"
echo
if [[ -f "$resume" ]]; then
  echo "前回のセッションは $(jq -r '"\(.reason) で \(.at) に中断"' "$resume" 2>/dev/null || echo 中断) した。"
fi
echo "文書の状態:"
bash "$scripts/spec-state.sh" "$spec" "$root" 2>/dev/null | sed 's/^/- /'
next="$(bash "$scripts/spec-next.sh" "$spec" "$root" 2>/dev/null)"; rc=$?
case $rc in
  0) echo "次のタスク: $(cut -f1,4 <<<"$next" | tr '\t' ' ')" ;;
  2) echo "すべてのタスクが完了している。" ;;
  *) echo "仕様が ready でない。/check-approval か /spec-change で文書を承認済みに戻す。" ;;
esac
echo
echo "続けるには /spec-implement $spec を実行する。途中だったタスクの変更は破棄してやり直す(位置はコミット trailer から再計算される)。"
