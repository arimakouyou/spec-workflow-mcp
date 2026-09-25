# sigcheck-rust.awk — spec の索引(TSV)から、design のシグネチャを検証する使い捨て crate を生成する。
# 使い方: gawk -v outdir=<dir> -v overlay_crates="<crate1 path1;crate2 path2>" -f sigcheck-rust.awk <index>
# 出力: <outdir>/Cargo.toml、<outdir>/src/lib.rs、<outdir>/linemap.tsv(生成行範囲 → ID)
#
# - Layer ごとに pub mod を作り、Layers 表で許可された Layer だけを glob import する
#   (許可されていない方向の参照は名前解決できずにコンパイルエラーになる)
# - DES / MOD / TST ごとに子モジュールを作り、関数本体(`;`)を `{ todo!() }` に置き換える。trait 定義内は `;` のまま
# - Held-as ごとに、その保持形で型が付くことと Send + Sync を確かめる関数を生成する

function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function modname(id) { return tolower(gensub(/-/, "_", "g", id)) }

function emit(s) { print s > librs; libline++ }

function brace_delta(s,    t, o, c) {
  t = s; gsub(/"([^"\\]|\\.)*"/, "", t)
  o = gsub(/\{/, "{", t); c = gsub(/\}/, "}", t)
  return o - c
}

# コード欄を出力する。Interfaces は関数本体を todo!() に置き換える
function emit_code(id, field, indent,    i, L, depth, intrait, insig) {
  depth = 0; intrait = 0; insig = 0
  for (i = 1; i <= ncode[id, field]; i++) {
    L = code[id, field, i]
    if (field == "Interfaces") {
      if (depth == 0 && L ~ /^[[:space:]]*(pub(\([^)]*\))?[[:space:]]+)?(unsafe[[:space:]]+)?trait[[:space:]]/) intrait = 1
      if (!intrait || depth == 0) {
        if (insig || L ~ /(^|[[:space:]])fn[[:space:]]+[A-Za-z_]/) {
          if (L ~ /;[[:space:]]*(\/\/.*)?$/) { sub(/;[[:space:]]*(\/\/.*)?$/, " { todo!() }", L); insig = 0 }
          else if (L !~ /\{[[:space:]]*$/) insig = 1
        }
      }
      depth += brace_delta(L)
      if (depth <= 0) { depth = 0; intrait = 0 }
    }
    emit(indent L)
  }
}

BEGIN { FS = "\t" }
$1 == "fm" { fm[$2, $3] = $4; next }
$1 == "def" && $2 == "design.md" { ids[++nid] = $3; name[$3] = $4; next }
$1 == "field" && $2 == "design.md" { F[$3, $4] = $5; next }
$1 == "code" && $2 == "design.md" { n = ++ncode[$3, $4]; code[$3, $4, n] = $5; next }
$1 == "text" && $2 == "design.md" && $3 == "Layers" && $6 ~ /^\|/ && $6 !~ /^\|[-[:space:]|]+\|?$/ {
  nc = split($6, cols, /\|/); ln = trim(cols[2])
  if (ln != "Layer" && ln != "") { layers[++nl] = ln; dd = trim(cols[4]); ldeps[ln] = (dd == "-" ? "" : dd) }
  next
}

END {
  cargo = outdir "/Cargo.toml"; librs = outdir "/src/lib.rs"; lmap = outdir "/linemap.tsv"
  libline = 0

  # --- Cargo.toml ------------------------------------------------------------------
  print "[package]\nname = \"" crate "\"\nversion = \"0.0.0\"\nedition = \"2021\"\npublish = false\n\n[lib]\npath = \"src/lib.rs\"\n\n[dependencies]" > cargo
  for (i = 1; i <= nid; i++) {
    id = ids[i]; if (id !~ /^DEP-/) continue
    feats = F[id, "Features"]; ver = F[id, "Version"]
    if (feats != "") { gsub(/[[:space:]]*,[[:space:]]*/, "\", \"", feats); print name[id] " = { version = \"" ver "\", features = [\"" feats "\"] }" > cargo }
    else print name[id] " = \"" ver "\"" > cargo
  }
  no = split(overlay_crates, oc, /;/)
  for (i = 1; i <= no; i++) {
    if (oc[i] == "") continue
    split(oc[i], pr, / /); print pr[1] " = { path = \"" pr[2] "\" }" > cargo
    un = pr[1]; gsub(/-/, "_", un); ovl[un] = 1
  }
  print "\n[workspace]" > cargo

  # --- src/lib.rs ------------------------------------------------------------------
  emit("// spec-sigcheck.sh が design.md から生成した検証用コード。手で編集しない。")
  emit("#![allow(unused, dead_code, unreachable_code, non_snake_case, non_camel_case_types, clippy::all)]")

  for (li = 1; li <= nl; li++) {
    ly = layers[li]
    emit("pub mod " ly " {")
    nd = split(ldeps[ly], dl, /,[[:space:]]*/)
    for (k = 1; k <= nd; k++) if (trim(dl[k]) != "") emit("    use crate::" trim(dl[k]) "::*;")
    for (c in ovl) emit("    use " c "::*;")
    for (i = 1; i <= nid; i++) {
      id = ids[i]; if (id !~ /^DES-/ || F[id, "Layer"] != ly) continue
      start = libline + 1
      emit("    pub mod " modname(id) " {")
      emit("        use super::*;")
      for (j = 1; j <= nid; j++) {
        mid = ids[j]
        if (mid ~ /^MOD-/ && F[mid, "Owner"] == id) {
          s2 = libline + 1; emit_code(mid, "Definition", "        "); if (libline >= s2) print s2 "\t" libline "\t" mid > lmap
        }
      }
      s2 = libline + 1; emit_code(id, "Interfaces", "        ")
      if (libline >= s2) print s2 "\t" libline "\t" id > lmap
      emit("    }")
      emit("    pub use " modname(id) "::*;")
    }
    emit("}")
  }

  # テスト支援(TST)は全 Layer を参照できる
  emit("pub mod test_support {")
  for (li = 1; li <= nl; li++) emit("    use crate::" layers[li] "::*;")
  for (c in ovl) emit("    use " c "::*;")
  for (i = 1; i <= nid; i++) {
    id = ids[i]; if (id !~ /^TST-/) continue
    emit("    pub mod " modname(id) " {")
    emit("        use super::*;")
    s2 = libline + 1; emit_code(id, "Interfaces", "        ")
    if (libline >= s2) print s2 "\t" libline "\t" id > lmap
    emit("    }")
    emit("    pub use " modname(id) "::*;")
  }
  emit("}")

  # Held-as: その保持形で型が付き、Send + Sync であること
  emit("mod held_as {")
  for (li = 1; li <= nl; li++) emit("    use crate::" layers[li] "::*;")
  for (c in ovl) emit("    use " c "::*;")
  emit("    fn assert_send_sync<T: ?Sized + Send + Sync>() {}")
  for (i = 1; i <= nid; i++) {
    id = ids[i]; h = F[id, "Held-as"]; if (id !~ /^DES-/ || h == "") continue
    gsub(/`/, "", h)
    s2 = libline + 1
    emit("    fn " modname(id) "() { assert_send_sync::<" h ">(); }")
    print s2 "\t" libline "\t" id " (Held-as)" > lmap
  }
  emit("}")
}
