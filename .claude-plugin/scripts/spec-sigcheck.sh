#!/usr/bin/env bash
# design.md のシグネチャ(DES Interfaces / MOD Definition / DEP / Held-as / Layers)を
# 使い捨ての crate に展開してコンパイルし、実装可能かをコンパイラで確かめる。
# 使い方: spec-sigcheck.sh <spec> [project-root]
# 出力: エラー 1 件 1 行 "SIG<TAB>ID<TAB>コンパイラのメッセージ"。
# 終了コード: 0 成功 / 1 コンパイルエラー / 3 ツール不足・未対応の宣言なし(黙って SKIP しない)
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

spec="${1:?usage: spec-sigcheck.sh <spec> [project-root]}"
root="$(spec_project_root "${2:-}")"
tech="$(steering_dir "$root")/tech.md"

lang="$(awk '/^## Sigcheck/{s=1; next} /^## /{s=0} s && /^- Language:/{sub(/^- Language:[[:space:]]*/, ""); print; exit}' "$tech" 2>/dev/null || true)"
case "$lang" in
  rust) ;;
  unsupported*)
    echo "sigcheck: 対象外として宣言されている(tech.md: $lang)"
    exit 0 ;;
  dotnet)
    echo "sigcheck: dotnet 版は未実装。承認前のコンパイル確認は行われていない" >&2
    exit 3 ;;
  "")
    echo "sigcheck: tech.md に ## Sigcheck の Language が無い" >&2
    exit 3 ;;
  *)
    echo "sigcheck: 未対応の言語: $lang(tech.md に unsupported (理由) と宣言する)" >&2
    exit 3 ;;
esac

if ! command -v cargo >/dev/null 2>&1; then
  echo "sigcheck: cargo が見つからない。design の TOOL に従って導入してから再実行する" >&2
  exit 3
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/spec-sigcheck.XXXXXX")"
mkdir -p "$work/src"
index="$work/index.tsv"
spec_index "$root" "$spec" > "$index"

# 既存コードの型を参照できるよう、greenfield 以外ではプロジェクトの lib crate を path 依存に加える(overlay)
task_type="$(awk -F'\t' '$1=="fm" && $2=="request-spec.md" && $3=="task_type"{print $4}' "$index")"
overlay=""
if [[ "$task_type" != "greenfield" && -f "$root/Cargo.toml" ]]; then
  overlay="$(cargo metadata --no-deps --format-version 1 --manifest-path "$root/Cargo.toml" 2>/dev/null \
    | jq -r '[.packages[] | select(any(.targets[]; any(.kind[]; . == "lib"))) | "\(.name) \(.manifest_path | rtrimstr("/Cargo.toml"))"] | join(";")' || true)"
fi

gawk -v outdir="$work" -v overlay_crates="$overlay" -f "$SPEC_LIB_DIR/sigcheck-rust.awk" "$index"

target="${SPEC_SIGCHECK_TARGET:-${XDG_CACHE_HOME:-$HOME/.cache}/spec-workflow/sigcheck-target}"
mkdir -p "$target"
if CARGO_TARGET_DIR="$target" cargo check --quiet --message-format short --manifest-path "$work/Cargo.toml" 2> "$work/cargo.err"; then
  echo "sigcheck: コンパイル成功($spec、$([[ -n "$overlay" ]] && echo overlay || echo standalone))"
  rm -rf "$work"
  exit 0
fi

# 生成コードの行 → ID に対応づけて報告する
gawk -F'\t' '
  FNR == NR { s[NR] = $1; e[NR] = $2; id[NR] = $3; n = NR; next }
  match($0, /^src\/lib\.rs:([0-9]+):[0-9]+: (error.*)$/, m) {
    who = "-"; for (i = 1; i <= n; i++) if (m[1] + 0 >= s[i] + 0 && m[1] + 0 <= e[i] + 0) who = id[i]
    print "SIG\t" who "\t" m[2]; next
  }
  /^error/ { print "SIG\t-\t" $0 }
' "$work/linemap.tsv" "$work/cargo.err"
echo "sigcheck: コンパイルエラー。生成したコード: $work/src/lib.rs" >&2
exit 1
