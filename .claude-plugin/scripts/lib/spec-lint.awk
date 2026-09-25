# spec-lint.awk — spec-parse.awk の索引(TSV)を読み、rules/doc-format.md の lint コードを判定する。
# 出力: CODE<TAB>doc<TAB>where<TAB>message(1 違反 1 行)

function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function err(code, doc, where, msg) { out[code "\t" doc "\t" where "\t" msg] = 1 }
function prefix(id) { sub(/-.*/, "", id); return id }
function inlist(x, list,    a, n, i) { n = split(list, a, /,[[:space:]]*/); for (i = 1; i <= n; i++) if (trim(a[i]) == x) return 1; return 0 }

function glob_re(g,    r) {
  r = g
  gsub(/\./, "\\.", r)
  gsub(/\*\*/, "\001", r)
  gsub(/\*/, "[^/]*", r)
  gsub(/\001/, ".*", r)
  return "^" r "$"
}

function is_literal(s) {
  return (s ~ /^-?[0-9][0-9_.]*$/ || s ~ /^".*"$/ || s ~ /^'.*'$/ || s ~ /^[\{\[]/ || s ~ /^\// \
    || s ~ /^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)([[:space:]].*)?$/ || s ~ /^(Ok|Err|Some|None|true|false|null)$/)
}
function is_plainid(s) { return s ~ /^(RQ|REQ|NFR|JRN|DES|MOD|API|TST|DEP|TOOL|KD|UT|CT|IT|ST|E2E|EV)-[A-Za-z0-9.-]+$/ }
function is_qref(s) { return s ~ /^(DES|MOD|TST)-[0-9]+:[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*$/ }

# 限定参照を解決する。解決できれば正規化したパス、できなければ "" を返し rerr に L06 / L07 を入れる
function resolve(id, path,    segs, n, s1, full, t) {
  rerr = ""
  n = split(path, segs, /::/)
  s1 = segs[1]
  if (prefix(id) == "MOD") {
    t = modtype[id]
    if (t == "" || s1 != t) { rerr = "L06"; return "" }
    if (n >= 2 && !((id SUBSEP t SUBSEP segs[2]) in mem)) { rerr = "L07"; return "" }
    return path
  }
  if (prefix(id) == "DES" || prefix(id) == "TST") {
    if ((id SUBSEP s1) in symkind) full = s1
    else if (bare[id, s1] == 1) full = barepath[id, s1]
    else { rerr = "L06"; return "" }
    if (n >= 2) {
      if ((id SUBSEP s1 "::" segs[2]) in symkind) return s1 "::" segs[2]
      if ((id SUBSEP s1 SUBSEP segs[2]) in mem) return path
      rerr = "L07"; return ""
    }
    return full
  }
  rerr = "L06"; return ""
}

# 文字列中の限定参照を取り出す(戻り値は件数、qid[i] / qpath[i] に格納)
function qrefs(s,    n, m, rest) {
  n = 0; rest = s
  while (match(rest, /`((DES|MOD|TST|API)-[0-9]+):([A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*)`/, m)) {
    n++; qid[n] = m[1]; qpath[n] = m[3]
    rest = substr(rest, RSTART + RLENGTH)
  }
  return n
}

# テンプレートの未記入箇所([...] / TBD / TODO)を含むか。コード表記・属性・リンクは除外する
function has_placeholder(s,    t) {
  t = s
  gsub(/`[^`]+`/, "", t)
  gsub(/#!?\[[^]]*\]/, "", t)
  gsub(/\[[^]]+\]\([^)]*\)/, "", t)
  return (t ~ /\[[^]]+\]/ || t ~ /(^|[^A-Za-z])(TBD|TODO)([^A-Za-z]|$)/)
}

function then_text(id,    s, i) {
  s = F[id, "Then"]
  for (i = 1; i <= nitems[id, "Then"]; i++) s = s " " items[id, "Then", i]
  return s
}

function ret_of(id, path,    r, c) {
  r = sigret[id, path]
  c = path; sub(/::[^:]*$/, "", c)
  if (c != path) gsub(/\<Self\>/, c, r)
  return r
}

function names_in(s, out,    n, m, rest) {
  n = 0; rest = s
  while (match(rest, /(^|[[:space:],])([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=/, m)) { out[m[2]] = 1; n++; rest = substr(rest, RSTART + RLENGTH) }
  return n
}

function set_eq_params(params, got,    a, n, i, k, want) {
  delete want
  n = (params == "" ? 0 : split(params, a, /,/))
  for (i = 1; i <= n; i++) want[a[i]] = 1
  for (k in want) if (!(k in got)) return 0
  for (k in got) if (!(k in want)) return 0
  return 1
}

BEGIN {
  FS = "\t"
  # ブロック種別ごとの欄(req: 必須、opt: 任意)
  req["RQ"] = "Actor,Goal,Flow"; opt["RQ"] = "Preconditions,Postconditions,Alternate,Exceptions"
  req["REQ"] = "Source,Story"; opt["REQ"] = "Evidence"
  req["NFR"] = "Category,Criterion,Rationale"; opt["NFR"] = ""
  req["JRN"] = "Covers,Steps"; opt["JRN"] = ""
  req["DES"] = "Kind,Layer,Phase,Files,Depends,Satisfies,Purpose"; opt["DES"] = "Evidence,Reuses,Held-as,Implements,Interfaces"
  req["MOD"] = "Owner,Definition"; opt["MOD"] = "Raises"
  req["API"] = "Handler,Auth,Request,Response"; opt["API"] = "Errors"
  req["TST"] = "Kind,Phase,Files,Depends,Interfaces"; opt["TST"] = "Implements"
  req["DEP"] = "Version,Scope,Purpose"; opt["DEP"] = "Features,Contract"
  req["TOOL"] = "Min,Check,Install,Required"; opt["TOOL"] = ""
  req["KD"] = "Decision,Rationale,ADR"; opt["KD"] = ""
  req["UT"] = "Target,Verifies,Category,Then"; opt["UT"] = "State,Given,Regression"
  req["CT"] = "Target,Verifies,Mount,Action,Then"; opt["CT"] = "State,Regression"
  req["IT"] = "Target,Verifies,File,Uses,Request,Then"; opt["IT"] = "Setup,State,Regression"
  req["ST"] = "Target,Verifies,File,Uses,Steps,Then"; opt["ST"] = "Setup,State,Regression"
  req["E2E"] = "Target,File,Uses,Steps,Then"; opt["E2E"] = "Setup,State"
  # 文書ごとに許される ## 節と必須の節
  allow["request-spec.md"] = "Overview,Requests,Out of Scope"; need["request-spec.md"] = "Overview,Requests"
  allow["requirements.md"] = "Requirements,Non-Functional,Journeys,Out of Scope"; need["requirements.md"] = "Requirements"
  allow["design.md"] = "Overview,Phases,Layers,Components,Types,APIs,Test Support,Dependencies,Tools,Decisions,Excluded Tests"; need["design.md"] = "Overview,Phases,Layers,Components"
  allow["test-design.md"] = "Unit Tests,Component Tests,Integration Tests,System Tests,E2E Tests"; need["test-design.md"] = ""
  techneed = "Stack,Test Commands,Quality Commands,Test Layout,Wiring Files,Health,Sigcheck"
  # task_type ごとの必須 EV カテゴリ
  evreq["feature-add"] = "code,contract"; evreq["feature-modify"] = "code,contract,tests"; evreq["bugfix"] = "code,tests,regressions"
  evreq["refactor"] = "code,tests"; evreq["legacy-migration"] = "code,contract,tests"; evreq["greenfield"] = "lib"; evreq["legacy"] = ""
}

$1 == "fm" { fm[$2, $3] = $4; next }
$1 == "sec" { secs[$2, $3] = 1; docs[$2] = 1; next }
$1 == "def" {
  if ($3 in defdoc) err("L01", $2, $3, "ID が 2 回定義されている(" defdoc[$3] " と " $2 ")")
  defdoc[$3] = $2; defname[$3] = $4; defsec[$3] = $6; defparent[$3] = $7; order[++ndef] = $3; docs[$2] = 1
  next
}
$1 == "grp" { grpdoc[$3] = $2; next }
$1 == "field" {
  if (($3 SUBSEP $4) in F) err("L16", $2, $3, "欄 " $4 " が重複している")
  F[$3, $4] = $5; next
}
$1 == "item" { n = ++nitems[$3, $4]; items[$3, $4, n] = $5; next }
$1 == "ac" {
  if ($3 in acdef) err("L01", $2, $3, "受入基準の ID が 2 回定義されている")
  acdef[$3] = $4; nac[$4]++; aclist[++nacall] = $3; next
}
$1 == "sym" {
  symkind[$3, $4] = $5
  if ($5 == "fn" && index($4, "::") > 0) { b = $4; sub(/^.*::/, "", b); if (barepath[$3, b] != $4) { bare[$3, b]++; barepath[$3, b] = $4 } }
  if (prefix($3) == "MOD" && $5 == "type" && modtype[$3] == "") modtype[$3] = $4
  next
}
$1 == "sig" { sigparams[$3, $4] = $5; sigret[$3, $4] = $6; next }
$1 == "member" { mem[$3, $4, $5] = 1; memlist[$3, $4] = memlist[$3, $4] "," $5; next }
$1 == "text" { nt++; tdoc[nt] = $2; tsec[nt] = $3; tid[nt] = $4; tfield[nt] = $5; tcont[nt] = $6; next }
$1 == "evfile" { evfile[$2] = 1; next }
$1 == "spec" { specname = $2; next }

END {
  tt = fm["request-spec.md", "task_type"]

  # --- L15 / L23: 節 -------------------------------------------------------------
  for (d in allow) {
    if (!(d in docs)) continue
    for (k in secs) { split(k, p, SUBSEP); if (p[1] == d && !inlist(p[2], allow[d])) err("L15", d, "## " p[2], "この文書に置けない節") }
    nn = split(need[d], a, /,/)
    for (i = 1; i <= nn; i++) if (!((d SUBSEP a[i]) in secs)) err("L15", d, "## " a[i], "必須の節が無い")
  }
  if (!("tech.md" in docs)) err("L23", "tech.md", "-", "steering/tech.md が無い")
  else { nn = split(techneed, a, /,/); for (i = 1; i <= nn; i++) if (!(("tech.md" SUBSEP a[i]) in secs)) err("L23", "tech.md", "## " a[i], "必須の節が無い") }

  # --- tech.md / design の表 -----------------------------------------------------
  for (i = 1; i <= nt; i++) {
    if (tdoc[i] == "tech.md" && tsec[i] == "Wiring Files" && match(tcont[i], /^- (.+)$/, m)) wiring[++nwiring] = glob_re(trim(m[1]))
    if (tdoc[i] == "design.md" && tsec[i] == "Layers" && tcont[i] ~ /^\|/ && tcont[i] !~ /^\|[-[:space:]|]+\|?$/) {
      nc = split(tcont[i], cols, /\|/)
      ln = trim(cols[2]); if (ln == "Layer" || ln == "") continue
      layer[ln] = 1; layerpaths[ln] = trim(cols[3]); dd = trim(cols[4]); layerdeps[ln] = (dd == "-" ? "" : dd)
    }
  }

  # --- L16: 欄 --------------------------------------------------------------------
  for (j = 1; j <= ndef; j++) {
    id = order[j]; pf = prefix(id)
    if (!(pf in req)) continue
    nn = split(req[pf], a, /,/)
    for (i = 1; i <= nn; i++) if (!((id SUBSEP a[i]) in F)) err("L16", defdoc[id], id, "必須の欄 " a[i] " が無い")
    for (k in F) { split(k, p, SUBSEP); if (p[1] == id && !inlist(p[2], req[pf]) && !inlist(p[2], opt[pf])) err("L16", defdoc[id], id, "この種類のブロックに無い欄 " p[2]) }
    if (pf == "DES") {
      kind = F[id, "Kind"]
      if (kind ~ /^(logic|types|adapter|ui)$/ && !((id SUBSEP "Interfaces") in F)) err("L16", "design.md", id, "Kind " kind " には Interfaces が必要")
      if (kind == "config" && ((id SUBSEP "Interfaces") in F)) err("L16", "design.md", id, "Kind config は Interfaces を持たない")
      if (F[id, "Layer"] == "-" && kind != "config") err("L16", "design.md", id, "Layer: - は Kind config だけに使える")
      if (kind !~ /^(logic|types|adapter|ui|wiring|config)$/) err("L16", "design.md", id, "Kind が不正: " kind)
    }
    if (pf == "TST" && F[id, "Kind"] == "double" && !((id SUBSEP "Implements") in F)) err("L16", "design.md", id, "Kind double には Implements が必要")
    if (pf == "REQ" && nac[id] == 0) err("L16", "requirements.md", id, "受入基準が 1 つも無い")
  }

  # --- テキスト走査: L02 L03 L04 L05 L06 L07 L13 L14 L18 -----------------------------
  for (i = 1; i <= nt; i++) {
    d = tdoc[i]; s = tcont[i]; where = (tid[i] == "-" ? "## " tsec[i] : tid[i])
    if (d == "tech.md" || d == "product.md" || d == "structure.md") {
      if (has_placeholder(s)) err("L14", d, where, "未記入のテンプレート文字列: " s)
      continue
    }
    # L03 行番号参照
    if (s ~ /[A-Za-z0-9_.\/-]+\.(md|rs|ts|tsx|js|cs|toml|json|ya?ml|py|go):[0-9]+/ || s ~ /#L[0-9]+/) err("L03", d, where, "行番号による参照: " s)
    # L14 プレースホルダ
    if (tfield[i] != "Request" && has_placeholder(s)) err("L14", d, where, "未記入のテンプレート文字列: " s)
    # L02 未定義 ID
    rest = s
    while (match(rest, /(^|[^A-Za-z0-9_-])((RQ|REQ|NFR|JRN|DES|MOD|API|TST|DEP|TOOL|KD|UT|CT|IT|ST|E2E)-[0-9]+(\.[0-9]+)?)([^0-9A-Za-z_]|$)/, m)) {
      rid = m[2]; rest = substr(rest, RSTART + length(m[1]) + length(m[2]))
      if (!(rid in defdoc) && !(rid in acdef)) err("L02", d, where, "未定義の ID を参照: " rid)
    }
    # L18 EV
    rest = s
    while (match(rest, /EV-[a-z]+(-[a-z]+)*-[0-9][0-9][0-9]/, m)) {
      ev = m[0]; rest = substr(rest, RSTART + RLENGTH); evcited[ev] = 1
      if (!(ev in evfile)) err("L18", d, where, "evidence ファイルが無い: " ev)
    }
    # L06 / L07 限定参照
    n = qrefs(s)
    for (q = 1; q <= n; q++) if (qid[q] != "" && prefix(qid[q]) != "API") {
      if (!(qid[q] in defdoc)) { err("L02", d, where, "未定義の ID を参照: " qid[q]); continue }
      if (resolve(qid[q], qpath[q]) == "") err(rerr, d, where, (rerr == "L06" ? "宣言されていない名前: " : "メンバーが無い: ") qid[q] ":" qpath[q])
    }
    # L04 / L05 コード表記
    rest = s; stripped = s
    while (match(rest, /`[^`]+`/)) {
      span = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
      if (is_qref(span) || is_literal(span) || is_plainid(span)) continue
      if (d == "design.md" && tfield[i] ~ /^(Held-as|Implements|Files)$/) continue
      err((d == "design.md" ? "L05" : "L04"), d, where, "所有者の外にあるコード表記: `" span "`")
    }
    gsub(/`[^`]+`/, "", stripped)
    if (stripped ~ /[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_]/ && !(d == "design.md" && tfield[i] ~ /^(Held-as|Implements|Files)$/))
      err((d == "design.md" ? "L05" : "L04"), d, where, "所有者の外にあるコード表記: " s)
    # L13 選言(Then)
    if (tfield[i] == "Then" && tolower(s) ~ /(^|[^a-z])(or|either)([^a-z]|$)|または|いずれか|もしくは|あるいは/) err("L13", d, where, "Then に選言がある: " s)
  }

  # --- L18: task_type の必須カテゴリ ----------------------------------------------
  if (tt in evreq) {
    nn = split(evreq[tt], a, /,/)
    for (i = 1; i <= nn; i++) { found = 0; for (e in evcited) if (index(e, "EV-" a[i] "-") == 1) found = 1; if (!found) err("L18", "requirements.md", "-", "task_type " tt " に必要な EV カテゴリ " a[i] " が引用されていない") }
  } else if (tt != "") err("L16", "request-spec.md", "-", "task_type が不正: " tt)

  # --- L09 / L10 / L19 / L20 / L24: design の構造 ----------------------------------
  for (j = 1; j <= ndef; j++) {
    id = order[j]; pf = prefix(id)
    if (pf != "DES" && pf != "TST") continue
    nf = split(F[id, "Files"], fl, /,[[:space:]]*/)
    for (i = 1; i <= nf; i++) {
      f = trim(fl[i]); if (f == "" || f == "-") continue
      isw = 0; for (w = 1; w <= nwiring; w++) if (f ~ wiring[w]) isw = 1
      if (!isw && (f in fileowner) && fileowner[f] != id) err("L09", "design.md", id, "ファイル " f " は " fileowner[f] " も所有している")
      if (!isw) fileowner[f] = id
      if (pf == "DES" && F[id, "Layer"] != "-" && !isw) {
        ly = F[id, "Layer"]
        if (!(ly in layer)) { err("L09", "design.md", id, "Layers 表に無い Layer: " ly); continue }
        ok = 0; np = split(layerpaths[ly], lp, /,[[:space:]]*/)
        for (k2 = 1; k2 <= np; k2++) if (f ~ glob_re(trim(lp[k2]))) ok = 1
        if (!ok) err("L09", "design.md", id, "ファイル " f " が Layer " ly " の Paths に無い")
      }
    }
    dep = F[id, "Depends"]
    if (dep != "" && dep != "-") {
      nd = split(dep, dl, /,[[:space:]]*/)
      for (i = 1; i <= nd; i++) {
        t = trim(dl[i]); edges[id] = edges[id] " " t
        if (!(t in defdoc)) continue
        if (pf == "DES" && prefix(t) == "DES" && F[id, "Layer"] != "-" && F[t, "Layer"] != "-" && F[t, "Layer"] != F[id, "Layer"] && !inlist(F[t, "Layer"], layerdeps[F[id, "Layer"]]))
          err("L10", "design.md", id, "Layer " F[id, "Layer"] " から " F[t, "Layer"] " への依存は Layers 表で許可されていない(" t ")")
        if ((F[t, "Phase"] + 0) > (F[id, "Phase"] + 0)) err("L20", "design.md", id, "後の Phase の " t "(Phase " F[t, "Phase"] ")に依存している")
      }
    }
    if (pf == "DES" && ((id SUBSEP "Held-as") in F)) {
      hasnew = 0
      for (k in symkind) { split(k, p, SUBSEP); if (p[1] == id && symkind[k] == "fn" && p[2] ~ /(^|::)new$/) hasnew = 1 }
      if (!hasnew) err("L24", "design.md", id, "Held-as があるのに Interfaces にコンストラクタ(new)が無い")
    }
    if (pf == "TST" && F[id, "Kind"] == "double" && ((id SUBSEP "Implements") in F)) {
      if (!match(F[id, "Implements"], /`((DES)-[0-9]+):([A-Za-z_][A-Za-z0-9_]*)`/, m) || symkind[m[1], m[3]] != "trait")
        err("L22", "design.md", id, "テストダブルが実装できるのは DES の Interfaces で宣言された trait だけ: " F[id, "Implements"])
    }
  }
  # L19 循環(DFS)
  for (j = 1; j <= ndef; j++) { id = order[j]; if (id in edges) { delete seen; if (cyc(id, id)) err("L19", "design.md", id, "Depends が循環している") } }

  # --- L25: Raises -------------------------------------------------------------
  for (j = 1; j <= ndef; j++) {
    id = order[j]; if (prefix(id) != "MOD" || nitems[id, "Raises"] == 0) continue
    t = modtype[id]; delete raised
    for (i = 1; i <= nitems[id, "Raises"]; i++) {
      it = items[id, "Raises", i]
      if (!match(it, /^([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$/, m)) { err("L25", "design.md", id, "Raises の書式が不正: " it); continue }
      v = m[1]; raised[v] = 1
      if (!((id SUBSEP t SUBSEP v) in mem)) err("L25", "design.md", id, "Raises の " v " は " t " の variant ではない")
      n = qrefs(m[2])
      for (q = 1; q <= n; q++) {
        rp = resolve(qid[q], qpath[q]); if (rp == "") continue
        if (ret_of(qid[q], rp) !~ ("(^|[^A-Za-z0-9_])" t "([^A-Za-z0-9_]|$)")) err("L25", "design.md", id, qid[q] ":" qpath[q] " の戻り値型に " t " が無い")
        rkey[++nr] = id SUBSEP t SUBSEP v SUBSEP qid[q] SUBSEP rp
      }
    }
    nm = split(substr(memlist[id, t], 2), ml, /,/)
    for (i = 1; i <= nm; i++) if (!(ml[i] in raised)) err("L25", "design.md", id, "variant " ml[i] " を返す関数が Raises に無い")
  }

  # --- test-design: L08 L12 L21 と網羅用の集計 --------------------------------------
  for (j = 1; j <= ndef; j++) {
    id = order[j]; pf = prefix(id)
    if (pf !~ /^(UT|CT|IT|ST|E2E)$/) continue
    tg = F[id, "Target"]; th = then_text(id)
    nv = split(F[id, "Verifies"], vl, /,[[:space:]]*/); for (i = 1; i <= nv; i++) verified[trim(vl[i])] = 1
    if (pf == "UT") {
      grpid = defparent[id]; num = id; sub(/^UT-/, "", num); sub(/\..*$/, "", num)
      if (grpid != "DES-" num) err("L12", "test-design.md", id, "UT の番号がグループ " grpid " と一致しない")
      if (!match(tg, /^`(DES-[0-9]+):([A-Za-z_][A-Za-z0-9_:]*)`$/, m)) { err("L12", "test-design.md", id, "UT の Target は `DES-N:fn` で書く: " tg); continue }
      if (m[1] != grpid) err("L12", "test-design.md", id, "Target " m[1] " がグループ " grpid " と違う")
      if (F[m[1], "Kind"] !~ /^(logic|types)$/) err("L12", "test-design.md", id, "UT の対象は Kind logic / types の DES: " m[1] " は " F[m[1], "Kind"])
      rp = resolve(m[1], m[2]); if (rp == "") continue
      utcov[m[1]] = 1; target_of[id] = m[1] SUBSEP rp
      if (!((m[1] SUBSEP rp) in sigret)) continue
      # L21 Given
      delete got; ng = 0
      for (i = 1; i <= nitems[id, "Given"]; i++) ng += names_in(items[id, "Given", i], got)
      if (!set_eq_params(sigparams[m[1], rp], got)) err("L21", "test-design.md", id, "Given の引数名がシグネチャ(" sigparams[m[1], rp] ")と一致しない")
      # L08
      rt = ret_of(m[1], rp); n = qrefs(th)
      for (q = 1; q <= n; q++) if (prefix(qid[q]) == "MOD" && modtype[qid[q]] != "" && rt !~ ("(^|[^A-Za-z0-9_])" modtype[qid[q]] "([^A-Za-z0-9_]|$)"))
        err("L08", "test-design.md", id, "Then の型 " qid[q] ":" qpath[q] " が Target の戻り値型 " rt " に無い")
    } else if (pf == "CT") {
      if (tg !~ /^DES-[0-9]+$/ || F[tg, "Kind"] != "ui") err("L12", "test-design.md", id, "CT の Target は Kind ui の DES")
      else ctcov[tg] = 1
    } else if (pf == "IT") {
      if (tg !~ /^API-[0-9]+$/) { err("L12", "test-design.md", id, "IT の Target は API-N"); continue }
      itcov[tg] = 1; itthen[tg] = itthen[tg] " " th
      allowed = " " F[tg, "Response"] " " F[tg, "Request"] " "
      for (i = 1; i <= nitems[tg, "Errors"]; i++) allowed = allowed " " items[tg, "Errors", i]
      n = qrefs(th)
      for (q = 1; q <= n; q++) if (prefix(qid[q]) == "MOD" && allowed !~ ("(^|[^0-9A-Za-z-])" qid[q] "([^0-9]|$)"))
        err("L08", "test-design.md", id, "Then の型 " qid[q] " が " tg " の Response / Errors に無い")
    } else if (pf == "ST") {
      if (tg !~ /^REQ-[0-9]+$/) err("L12", "test-design.md", id, "ST の Target は REQ-N"); else stcov[tg] = 1
    } else if (pf == "E2E") {
      if (tg !~ /^JRN-[0-9]+$/) err("L12", "test-design.md", id, "E2E の Target は JRN-N"); else e2ecov[tg] = 1
    }
    # L21 Setup
    for (i = 1; i <= nitems[id, "Setup"]; i++) {
      it = items[id, "Setup", i]
      if (!match(it, /^`((TST|DES)-[0-9]+):([A-Za-z_][A-Za-z0-9_:]*)`(.*)$/, m)) continue
      rp = resolve(m[1], m[3]); if (rp == "" || !((m[1] SUBSEP rp) in sigparams)) continue
      delete got; names_in(m[4], got)
      if (!set_eq_params(sigparams[m[1], rp], got)) err("L21", "test-design.md", id, "Setup の " m[1] ":" m[3] " の引数名がシグネチャ(" sigparams[m[1], rp] ")と一致しない")
    }
    thens[id] = th
  }

  # --- L11: 網羅 ------------------------------------------------------------------
  for (j = 1; j <= ndef; j++) {
    id = order[j]; pf = prefix(id)
    if (pf == "RQ") {
      c = 0
      for (k = 1; k <= ndef; k++) if (prefix(order[k]) == "REQ" && inlist(id, F[order[k], "Source"])) c = 1
      for (i = 1; i <= nt; i++) if (tdoc[i] == "requirements.md" && tsec[i] == "Out of Scope" && tcont[i] ~ ("^- " id ":")) c = 1
      if (!c) err("L11", "requirements.md", id, "どの REQ の Source にも Out of Scope にも無い")
    }
    if (pf == "JRN" && !(id in e2ecov)) err("L11", "test-design.md", id, "この JRN の E2E が無い")
    if (pf == "DES") {
      kind = F[id, "Kind"]
      if (kind ~ /^(logic|types)$/ && !(id in utcov)) err("L11", "test-design.md", id, "Kind " kind " の UT が無い")
      if (kind == "ui" && !(id in ctcov)) err("L11", "test-design.md", id, "Kind ui の CT が無い")
      ns = split(F[id, "Satisfies"], sl, /,[[:space:]]*/)
      for (i = 1; i <= ns; i++) { r = trim(sl[i]); sub(/\..*$/, "", r); reqkinds[r] = reqkinds[r] " " kind }
    }
    if (pf == "API") {
      if (!(id in itcov)) { err("L11", "test-design.md", id, "この API の IT が無い"); continue }
      split(F[id, "Response"], rs, /[[:space:]]+/)
      if (itthen[id] !~ ("status " rs[1])) err("L11", "test-design.md", id, "Response " rs[1] " を確かめる IT が無い")
      for (i = 1; i <= nitems[id, "Errors"]; i++) {
        split(items[id, "Errors", i], es, /:/)
        if (itthen[id] !~ ("status " trim(es[1]))) err("L11", "test-design.md", id, "エラー " trim(es[1]) " を確かめる IT が無い")
        if (match(items[id, "Errors", i], /DEP-[0-9]+/, m)) depverified[m[0]] = 1
      }
    }
    if (pf == "DEP" && nitems[id, "Contract"] > 0 && !(id in depverified)) err("L11", "design.md", id, "Contract を確かめる API のエラー(と IT)が無い")
  }
  for (i = 1; i <= nacall; i++) if (!(aclist[i] in verified)) err("L11", "test-design.md", aclist[i], "この受入基準を Verifies に持つテストが無い")
  for (r in reqkinds) if (reqkinds[r] ~ /ui/ && reqkinds[r] ~ /adapter/ && !(r in stcov)) err("L11", "test-design.md", r, "ui と adapter にまたがる REQ の ST が無い")
  # adapter の Handler を持つ API は IT 必須(上で確認済み)。Raises の網羅:
  for (i = 1; i <= nr; i++) {
    split(rkey[i], p, SUBSEP)   # p: MOD, type, variant, DES, fnpath
    want = "(^|[^A-Za-z0-9_-])" p[1] ":" p[2] "::" p[3] "`"
    c = 0
    if (F[p[4], "Kind"] == "adapter") {
      for (a2 = 1; a2 <= ndef; a2++) { ap = order[a2]; if (prefix(ap) != "API") continue
        if (match(F[ap, "Handler"], /`(DES-[0-9]+):([A-Za-z_][A-Za-z0-9_:]*)`/, m) && m[1] == p[4] && resolve(m[1], m[2]) == p[5] && itthen[ap] ~ want) c = 1 }
    } else {
      for (u in target_of) if (target_of[u] == p[4] SUBSEP p[5] && thens[u] ~ want) c = 1
    }
    if (!c) err("L11", "test-design.md", p[1], "Raises " p[3] "(" p[4] ":" p[5] ")を確かめるテストが無い")
  }

  # --- L17 / L26 -----------------------------------------------------------------
  for (i = 1; i <= nt; i++) if (tdoc[i] == "design.md" && tsec[i] == "Excluded Tests" && match(tcont[i], /^- ([A-Z0-9]+-[0-9.]+):[[:space:]]*(.*)$/, m)) {
    if (!(m[1] in defdoc)) err("L02", "design.md", "## Excluded Tests", "未定義のテスト: " m[1])
    if (m[2] !~ /[^[:space:]].* — .*[^[:space:]]/) err("L17", "design.md", m[1], "除外には「理由 — 代替の検証」が必要")
  }
  if (tt == "greenfield") {
    c = 0; for (j = 1; j <= ndef; j++) if (prefix(order[j]) == "DES" && F[order[j], "Kind"] == "config" && F[order[j], "Phase"] == "0") c = 1
    if (!c) err("L26", "design.md", "-", "greenfield には Phase 0 の Kind config の DES(ブートストラップ)が必要")
  }

  for (k in out) print k
}

function cyc(start, node,    nd, dl, i, t) {
  nd = split(edges[node], dl, /[[:space:]]+/)
  for (i = 1; i <= nd; i++) {
    t = dl[i]; if (t == "") continue
    if (t == start) return 1
    if (t in seen) continue
    seen[t] = 1
    if (cyc(start, t)) return 1
  }
  return 0
}
