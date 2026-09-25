#!/usr/bin/env bash
# spec セッションの唯一のコミット経路。ゲート(G0-G9)を満たしたときだけ、trailer 付きの 1 コミットを作る。
# 使い方:
#   spec-git.sh start      <spec> <task>             タスク開始(作業ツリーが clean であることを記録)      … オーケストレーター
#   spec-git.sh checkpoint <spec> <task> <file>...   RED 完了時のテストファイルの sha を記録                … impl-worker
#   spec-git.sh commit     <spec> <task>             ゲートを通してコード + タスクログを 1 コミット         … review-worker
#   spec-git.sh record     <spec> <task>             コード変更のないタスク(REVIEW / TOOLS)の記録        … review-worker / オーケストレーター
#   spec-git.sh docs       <spec>                    承認済み文書と承認台帳だけをコミット                   … check-approval
#   spec-git.sh archive    <spec>                    spec を archive/specs/ へ移してコミット                … review-worker(FINAL)
#   spec-git.sh discard    <spec> <task>             失敗したタスクの変更を .spec-workflow を除いて破棄     … オーケストレーター
#   spec-git.sh verdict    <spec> <task> < json      review-worker の判定を runs/<task>/review.json に記録   … review-worker
#   spec-git.sh reopen     <spec> <task> [理由]      完了済みタスクを再オープン(Spec-Reopen trailer)       … オーケストレーター / spec-change
# 誰が呼べるかは hooks/guard-git.sh が agent_type で制限する。
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

cmd="${1:?usage: spec-git.sh <start|checkpoint|commit|record|docs|archive|discard|verdict|reopen> <spec> [task]}"
spec="${2:?spec が必要}"
task="${3:-}"
root="$(spec_project_root "${SPEC_PROJECT_ROOT:-}")"
sdir="$(spec_dir "$root" "$spec")"
runs="$sdir/runs"
g() { git -C "$root" "$@"; }
die() { printf 'spec-git: %b\n' "$*" >&2; exit 1; }
gate() { printf 'spec-git: %s NG — %b\n' "$1" "$2" >&2; exit 1; }

# 実行時だけの状態は git に載せない
ensure_ignore() {
  local f="$root/.spec-workflow/.gitignore" line
  touch "$f"
  for line in 'specs/*/runs/' '.active' '.resume' '.agent-lock' 'specs/*/.change-open' 'steering/.change-open'; do
    grep -qxF "$line" "$f" || printf '%s\n' "$line" >> "$f"
  done
}

# .spec-workflow の外で変更された追跡済みファイル
tracked_changes() {
  g status --porcelain -uno -- . ':(exclude).spec-workflow' | awk '{ p = substr($0, 4); sub(/^.* -> /, "", p); print p }'
}
# .spec-workflow の外にある未追跡ファイル(.gitignore 対象は除く)
untracked_now() {
  g ls-files --others --exclude-standard -- . ':(exclude).spec-workflow'
}
# spec の最初の start の時点で既にあった未追跡ファイルは利用者のもので、触らない。
# それ以降に増えた未追跡ファイルは、タスクが作ったものとして扱う。
untracked_base="$runs/untracked.base"
untracked_new() {
  if [[ -f "$untracked_base" ]]; then untracked_now | grep -vxF -f "$untracked_base" || true; else untracked_now; fi
}
# タスクが変更したパス(追跡済みの変更 + 開始後に増えた未追跡ファイル)
changed_since_start() { { tracked_changes; untracked_new; } | sort -u | grep -v '^$' || true; }

# spec 文書を .gitignore が除外していないか(除外されていると文書も実装もコミットできない)
ensure_trackable() {
  local probe="$1"
  if g check-ignore -q "$probe" 2>/dev/null; then
    die ".gitignore が ${probe#"$root"/} を除外している。spec 文書を追跡できるよう、.gitignore から .spec-workflow の除外を外す(または !.spec-workflow/specs/ を追加する)"
  fi
}

task_row() { bash "$SPEC_SCRIPTS_DIR/spec-plan.sh" "$spec" "$root" --tsv | awk -F'\t' -v k="$1" '$1 == k'; }
index_tsv() { spec_index "$root" "$spec"; }
field_of() { awk -F'\t' -v id="$2" -v f="$3" '$1 == "field" && $3 == id && $4 == f { print $5; exit }' <<<"$1"; }
split_list() { tr ',' '\n' <<<"$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^-\?$' || true; }
json() { [[ -f "$runs/$task/$1.json" ]] && cat "$runs/$task/$1.json" || echo '{}'; }

commit_with_trailers() { # subject, extra trailer lines...
  local subject="$1"; shift
  local msg; msg="$(printf '%s\n\nSpec: %s' "$subject" "$spec")"
  local t; for t in "$@"; do msg="$(printf '%s\n%s' "$msg" "$t")"; done
  g commit -q -m "$msg"
}

case "$cmd" in
start)
  [[ -n "$task" ]] || die "task が必要"
  ensure_trackable "$sdir/design.md"
  ensure_ignore
  dirty="$(tracked_changes)"
  [[ -z "$dirty" ]] || gate G0 "追跡済みファイルに未コミットの変更がある(前のタスクの残り):\n$dirty"
  mkdir -p "$runs/$task"
  [[ -f "$untracked_base" ]] || untracked_now > "$untracked_base"
  left="$(untracked_new)"
  [[ -z "$left" ]] || gate G0 "spec の開始後に増えた未追跡ファイルがある(前のタスクの残りなら spec-git.sh discard、利用者のファイルなら .gitignore に加える):\n$left"
  attempt=$(( $(jq -r '.attempt // 0' "$runs/$task/start.json" 2>/dev/null || echo 0) + 1 ))
  jq -n --arg t "$task" --arg b "$(g rev-parse HEAD)" --arg at "$(date -u +%FT%TZ)" --argjson n "$attempt" \
    '{task: $t, base: $b, at: $at, attempt: $n}' > "$runs/$task/start.json"
  echo "spec-git: $task を開始(base $(g rev-parse --short HEAD)、attempt $attempt)"
  ;;

checkpoint)
  [[ -n "$task" ]] || die "task が必要"
  shift 3
  (( $# > 0 )) || die "RED を記録するテストファイルを指定する"
  mkdir -p "$runs/$task"
  obj='{}'
  for f in "$@"; do
    [[ -f "$root/$f" ]] || die "テストファイルが無い: $f"
    obj="$(jq --arg f "$f" --arg s "$(sha256sum "$root/$f" | cut -d' ' -f1)" '. + {($f): $s}' <<<"$obj")"
  done
  jq -n --argjson files "$obj" --arg at "$(date -u +%FT%TZ)" '{at: $at, files: $files}' > "$runs/$task/red.json"
  echo "spec-git: RED を記録($task、$# ファイル)"
  ;;

commit|record)
  [[ -n "$task" ]] || die "task が必要"
  idx="$(index_tsv)"
  row="$(task_row "$task")"; [[ -n "$row" ]] || die "タスク $task は tasks にない"
  IFS=$'\t' read -r _ type _ title tests state <<<"$row"
  [[ "$tests" == "-" ]] && tests=""
  [[ "$state" == open ]] || die "$task は完了済み"

  # G0 開始時点から他のコミットが入っていない
  [[ -f "$runs/$task/start.json" ]] || gate G0 "spec-git.sh start $spec $task が実行されていない"
  base="$(jq -r .base "$runs/$task/start.json")"
  [[ "$(g rev-parse HEAD)" == "$base" ]] || gate G0 "タスク開始後に別のコミットが入っている(base $base)"

  # G1 仕様が ready で lint が通る
  bash "$SPEC_SCRIPTS_DIR/spec-state.sh" "$spec" "$root" --ready >/dev/null || gate G1 "仕様が ready でない(spec-state.sh で確認)"
  bash "$SPEC_SCRIPTS_DIR/spec-lint.sh" "$spec" "$root" >/dev/null 2>&1 || gate G1 "spec-lint が通らない"

  # G2 手順の実行記録がそろっている(ツール確認タスクは確認そのものが記録)
  if [[ "$type" == tools ]]; then
    bash "$SPEC_SCRIPTS_DIR/spec-tools-check.sh" "$spec" "$root" > "$runs/$task/tools.tsv" || gate G2 "必須ツールが揃っていない(spec-tools-check.sh)"
  else
    review="$(json review)"
    [[ "$(jq -r '.verdict // empty' <<<"$review")" == commit ]] || gate G2 "review-worker の verdict: commit が記録されていない(runs/$task/review.json)"
  fi
  case "$type" in
    des-logic|des-types|des-ui|des-adapter|des-wiring|des-config|tst-*|it|st|smk|refactor|final)
      [[ "$(jq -r '.status // empty' <<<"$(json impl)")" == "done" ]] || gate G2 "実装の完了(status: done)が記録されていない(runs/$task/impl.json)" ;;
  esac
  case "$type" in
    des-logic|des-types|des-ui|it|st|smk|refactor|final)
      [[ "$(jq -r '.verdict // empty' <<<"$(json verify)")" == pass ]] || gate G2 "検証役の verdict: pass が記録されていない(runs/$task/verify.json)" ;;
  esac

  changed="$(changed_since_start)"
  if [[ "$cmd" == record ]]; then
    [[ -z "$changed" ]] || gate G3 "record はコード変更を含められない:\n$changed"
  else
    # G3 変更範囲
    allowed="$(mktemp)"; trap 'rm -f "$allowed"' EXIT
    jq -r '.tests.files[]? // empty' <<<"$(json impl)" >> "$allowed"
    case "$type" in
      des-*|tst-*) split_list "$(field_of "$idx" "$task" Files)" >> "$allowed" ;;
      it|st|final) for t in $(split_list "$tests"); do field_of "$idx" "$t" File; done >> "$allowed" ;;
      refactor) awk -F'\t' '$1 == "field" && $3 ~ /^DES-/ && $4 == "Files" { print $5 }' <<<"$idx" | tr ',' '\n' | sed 's/^[[:space:]]*//' >> "$allowed" ;;
    esac
    wiring="$(awk '/^## Wiring Files/{p=1; next} /^## /{p=0} p && /^- /{sub(/^- /, ""); print}' "$(steering_dir "$root")/tech.md")"
    bad=""
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      grep -qxF "$f" "$allowed" && continue
      ok=0; while IFS= read -r w; do [[ -n "$w" ]] || continue
        # shellcheck disable=SC2053  # glob 照合を意図している
        [[ "$f" == $w ]] && ok=1; done <<<"$wiring"
      (( ok )) || bad="$bad $f"
    done <<<"$changed"
    [[ -z "$bad" ]] || gate G3 "このタスクの範囲外のファイルを変更している:$bad"
    if [[ "$type" == refactor ]]; then
      [[ -z "$(jq -r '.tests.files[]? // empty' <<<"$(json impl)")" ]] || gate G3 "リファクタはテストファイルを変更しない"
    fi

    # G4 シグネチャ行が実装に存在する
    if [[ "$type" == des-* || "$type" == tst-* ]]; then
      iface="$(awk -F'\t' -v id="$task" '$1 == "code" && $3 == id && $4 == "Interfaces" { print $5 }' <<<"$idx")"
      if [[ -n "$iface" ]]; then
        src=""; for f in $(split_list "$(field_of "$idx" "$task" Files)"); do [[ -f "$root/$f" ]] && src="$src$(cat "$root/$f")"$'\n'; done
        have="$(gawk -f "$SPEC_LIB_DIR/signorm.awk" <<<"$src" | sort -u)"
        missing="$(gawk -f "$SPEC_LIB_DIR/signorm.awk" <<<"$iface" | sort -u | comm -23 - <(printf '%s\n' "$have"))"
        [[ -z "$missing" ]] || gate G4 "design の Interfaces と一致するシグネチャが実装に無い(変更は /spec-change で):\n$missing"
      fi
    fi

    # G5 テスト ID の集合が test-design と一致する
    if [[ -n "$tests" && "$type" != smk && "$type" != tools ]]; then
      files="$( { jq -r '.tests.files[]? // empty' <<<"$(json impl)"; for t in $(split_list "$tests"); do field_of "$idx" "$t" File; done; } | sort -u)"
      found="$(for f in $files; do [[ -f "$root/$f" ]] && grep -ohE '@test (UT|CT|IT|ST|E2E)-[0-9]+(\.[0-9]+)?' "$root/$f"; done | awk '{print $2}' | sort -u)"
      want="$(split_list "$tests" | sort -u)"
      [[ "$found" == "$want" ]] || gate G5 "テストの @test ID が test-design と一致しない(期待: $(tr '\n' ' ' <<<"$want")/ 実際: $(tr '\n' ' ' <<<"$found"))"
    fi

    # G6 RED 以降にテストが変わっていない
    if [[ "$type" == des-logic || "$type" == des-types || "$type" == des-ui ]]; then
      [[ -f "$runs/$task/red.json" ]] || gate G6 "RED の記録が無い(spec-git.sh checkpoint)"
      while IFS=$'\t' read -r f s; do
        [[ "$(sha256sum "$root/$f" 2>/dev/null | cut -d' ' -f1)" == "$s" ]] || gate G6 "RED 以降にテストファイルが変わっている: $f"
      done < <(jq -r '.files | to_entries[] | "\(.key)\t\(.value)"' "$runs/$task/red.json")
    fi

    # G7 テストが通る
    case "$type" in
      des-logic|des-types|tst-*) layers="UT" ;;
      des-ui) layers="UT CT" ;;
      des-adapter|des-wiring|des-config) layers="UT" ;;
      it) layers="IT" ;; st) layers="ST" ;; smk) layers="SMK" ;;
      refactor) layers="UT CT IT ST" ;;
      final) layers="UT CT IT ST SMK E2E" ;;
      *) layers="" ;;
    esac
    for l in $layers; do
      bash "$SPEC_SCRIPTS_DIR/spec-run-tests.sh" "$l" "$root" >/dev/null 2>&1 || gate G7 "$l のテストが通らない(spec-run-tests.sh $l で確認)"
    done

    # G8 フォーマット・静的解析・依存
    for c in format lint; do
      q="$(tech_table_value "$root" "Quality Commands" "$c")"
      [[ -n "$q" && "$q" != "-" ]] || continue
      (cd "$root" && bash -c "$q") >/dev/null 2>&1 || gate G8 "$c が通らない($q)"
    done
    deps_allowed="$(awk -F'\t' '$1 == "def" && $3 ~ /^DEP-/ { print $4 }' <<<"$idx")"
    added="$(g diff -U0 HEAD -- '*Cargo.toml' | awk '/^\[/{sec=$0} /^\+[A-Za-z0-9_-]+[[:space:]]*=/{ sub(/^\+/, ""); sub(/[[:space:]]*=.*/, ""); print }' | grep -vE '^(name|version|edition|publish|resolver|members|path|features|default|workspace)$' || true)"
    for d in $added; do
      grep -qxF "$d" <<<"$deps_allowed" || gate G8 "design の DEP に無い依存を追加している: $d"
    done
    q="$(tech_table_value "$root" "Quality Commands" audit)"
    lock_changed="$(g status --porcelain -- '*.lock' 'package-lock.json' 'packages.lock.json' | head -1)"
    if [[ -n "$q" && "$q" != "-" && -n "$lock_changed" ]]; then
      (cd "$root" && bash -c "$q") >/dev/null 2>&1 || gate G8 "依存の監査が通らない($q)"
    fi
  fi

  # G9 タスクログ・backlog・申し送り・tasks.md を同梱して 1 コミット
  mkdir -p "$sdir/task-logs"
  attempt="$(jq -r '.attempt // 1' "$runs/$task/start.json")"
  {
    echo "# $task $title"; echo
    echo "- Spec: $spec"; echo "- Type: $type"; echo "- Attempt: $attempt"; echo
    for r in impl verify review; do
      [[ -f "$runs/$task/$r.json" ]] || continue
      echo "## $r"; echo; echo '```json'; jq . "$runs/$task/$r.json"; echo '```'; echo
    done
    if [[ -f "$runs/$task/tools.tsv" ]]; then
      echo "## tools"; echo; echo '```'; cat "$runs/$task/tools.tsv"; echo '```'; echo
    fi
  } > "$sdir/task-logs/$task.md"
  rfs="$(jq -c '(.rf // [])[]' "$runs/$task/"*.json 2>/dev/null || true)"
  if [[ -n "$rfs" ]]; then
    bl="$sdir/refactor-backlog.md"
    [[ -f "$bl" ]] || printf '# Refactor Backlog\n\n| RF | From | Status | Note |\n|---|---|---|---|\n' > "$bl"
    n="$(grep -cE '^\| RF-[0-9]{3} ' "$bl" || true)"
    while IFS= read -r rf; do
      n=$((n + 1)); printf '| RF-%03d | %s | open | %s |\n' "$n" "$task" "$(jq -r 'if type == "string" then . else .text end' <<<"$rf")" >> "$bl"
    done <<<"$rfs"
  fi
  # リファクタタスクが消化した RF 行を done にする
  for id in $(jq -r '(.rf_done // [])[]' "$runs/$task/"*.json 2>/dev/null || true); do
    [[ -f "$sdir/refactor-backlog.md" ]] && sed -i "s/^| $id | \\([^|]*\\) | open | /| $id | \\1 | done | /" "$sdir/refactor-backlog.md"
  done
  jq -c --arg from "$task" '(.handoffs // [])[] | {from: $from, to: .to, text: .text}' "$runs/$task/"*.json 2>/dev/null >> "$sdir/handoffs.jsonl" || true
  [[ -s "$sdir/handoffs.jsonl" ]] || rm -f "$sdir/handoffs.jsonl"
  SPEC_PLAN_EXTRA_DONE="$task" bash "$SPEC_SCRIPTS_DIR/spec-plan.sh" "$spec" "$root" 2>/dev/null
  inputs="$(bash "$SPEC_SCRIPTS_DIR/spec-brief.sh" "$spec" "$task" "$root" --inputs-only 2>/dev/null | sha256sum | cut -c1-12)"
  # 追跡済みの変更と、開始後に増えたファイルだけを載せる(開始前からの未追跡ファイルは利用者のもの)
  g add -u -- . ':(exclude).spec-workflow/approvals'
  mapfile -t new_files < <(untracked_new)
  (( ${#new_files[@]} == 0 )) || g add -- "${new_files[@]}"
  g add -- "$sdir" .spec-workflow/.gitignore
  case "$type" in des-*) kind="feat" ;; tst-*|it|st|smk|final) kind="test" ;; refactor) kind="refactor" ;; *) kind="chore" ;; esac
  commit_with_trailers "$kind($spec): $task $title" "Spec-Task: $task" "Spec-Inputs: $inputs" "Spec-Attempt: $attempt"
  echo "spec-git: $task をコミット($(g rev-parse --short HEAD))"
  ;;

docs)
  if [[ "$spec" == steering ]]; then paths=(.spec-workflow/steering .spec-workflow/approvals/steering); ensure_trackable "$root/.spec-workflow/steering/tech.md"
  else paths=(".spec-workflow/specs/$spec" ".spec-workflow/approvals/$spec"); ensure_trackable "$sdir/design.md"; fi
  staged="$(g diff --cached --name-only)"
  if [[ -n "$staged" ]]; then
    other="$(grep -vE "^($(printf '%s|' "${paths[@]}" | sed 's/|$//'))(/|$)" <<<"$staged" || true)"
    [[ -z "$other" ]] || die "文書以外のファイルがステージされている:\n$other"
  fi
  ensure_ignore
  existing=(); for p in "${paths[@]}" .spec-workflow/.gitignore; do [[ -e "$root/$p" ]] && existing+=("$p"); done
  g add -A -- "${existing[@]}"
  if g diff --cached --quiet; then echo "spec-git: 記録する変更は無い"; exit 0; fi
  commit_with_trailers "docs($spec): 承認済みの文書を記録"
  echo "spec-git: 文書を記録($(g rev-parse --short HEAD))"
  ;;

archive)
  [[ -d "$sdir" ]] || die "$sdir が無い"
  mkdir -p "$root/.spec-workflow/archive/specs"
  g mv "$sdir" "$root/.spec-workflow/archive/specs/$spec"
  commit_with_trailers "chore($spec): spec をアーカイブ" "Spec-Archive: $spec"
  ;;

discard)
  [[ -n "$task" ]] || die "task が必要"
  [[ -f "$runs/$task/start.json" ]] || die "$task は start されていない(clean な開始点が無いので破棄しない)"
  g restore -SW -- . ':(exclude).spec-workflow'
  # 開始後に増えたファイルだけを消す(開始前からの未追跡ファイルは残す)
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    rm -f -- "$root/$f"
    rmdir -p --ignore-fail-on-non-empty -- "$(dirname "$root/$f")" 2>/dev/null || true
  done < <(untracked_new)
  echo "spec-git: $task の変更を破棄した(.spec-workflow を除く)"
  ;;

verdict)
  [[ -n "$task" ]] || die "task が必要"
  v="$(cat)"
  jq -e --arg t "$task" '.task == $t and (.verdict | IN("commit", "rework", "escalate"))' <<<"$v" >/dev/null \
    || die "判定 JSON が不正({task: \"$task\", verdict: commit|rework|escalate, ...} が必要)"
  if [[ "$(jq -r .verdict <<<"$v")" == rework ]]; then
    jq -e '.rework_from | IN("red", "green")' <<<"$v" >/dev/null || die "rework には rework_from: red|green が必要"
  fi
  mkdir -p "$runs/$task"
  jq . <<<"$v" > "$runs/$task/review.json"
  jq -c . <<<"$v" >> "$runs/$task/history.jsonl"
  echo "spec-git: $task の判定を記録($(jq -r .verdict <<<"$v"))"
  ;;

reopen)
  [[ -n "$task" ]] || die "task が必要"
  reason="${4:-再オープン}"
  state="$(bash "$SPEC_SCRIPTS_DIR/spec-plan.sh" "$spec" "$root" --tsv | awk -F'\t' -v k="$task" '$1 == k { print $6 }')"
  [[ "$state" == "done" ]] || die "$task は完了済みではない(状態: ${state:-不明})"
  g commit -q --allow-empty -m "$(printf 'chore(%s): %s を再オープン — %s\n\nSpec: %s\nSpec-Reopen: %s' "$spec" "$task" "$reason" "$spec" "$task")"
  SPEC_PLAN_EXTRA_DONE="" bash "$SPEC_SCRIPTS_DIR/spec-plan.sh" "$spec" "$root" 2>/dev/null
  if ! g diff --quiet -- "$sdir/tasks.md"; then g add -- "$sdir/tasks.md"; g commit -q --amend --no-edit; fi
  echo "spec-git: $task を再オープン"
  ;;

*) die "未知のサブコマンド: $cmd" ;;
esac
