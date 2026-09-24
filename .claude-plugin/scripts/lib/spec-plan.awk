# spec-plan.awk — 索引(TSV)から実装タスクの順序を決め、tasks.md を出力する。
# -v done="KEY KEY ..."  完了済みのタスクキー(コミット trailer から求めたもの)
# -v mode="md|tsv"       md: tasks.md、tsv: "key<TAB>type<TAB>phase<TAB>title<TAB>tests" の一覧
#
# タスクの並び:
#   P0-TOOLS(TOOL があれば)
#   Phase ごとに: DES / TST(依存順)→ P{n}-IT → P{n}-ST → P{n}-SMK → P{n}-REFACTOR → P{n}-REVIEW
#   FINAL
# 依存順は同じ Phase 内の Depends と、UT が参照するテストダブル(TST)→ その UT の DES を辺にしたトポロジカル順。
# 同順位は design での定義順。

function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function pf(id) { sub(/-.*/, "", id); return id }
function then_all(id,    s, i) { s = F[id, "Then"] " " F[id, "State"] " " F[id, "Given"]; for (i = 1; i <= nit[id, "Then"]; i++) s = s " " it[id, "Then", i]; for (i = 1; i <= nit[id, "Given"]; i++) s = s " " it[id, "Given", i]; return s }
function joinlist(arr, n,    i, s) { s = ""; for (i = 1; i <= n; i++) s = (s == "" ? arr[i] : s ", " arr[i]); return s }

function add_task(key, type, phase, title, tests) {
  nt++; tkey[nt] = key; ttype[nt] = type; tphase[nt] = phase; ttitle[nt] = title; ttests[nt] = tests
}

BEGIN { FS = "\t"; nd = split(done, dl, /[[:space:]]+/); for (i = 1; i <= nd; i++) if (dl[i] != "") isdone[dl[i]] = 1 }
$1 == "def" { order[++ndef] = $3; name[$3] = $4; parent[$3] = $7; next }
$1 == "field" { F[$3, $4] = $5; next }
$1 == "item" { n = ++nit[$3, $4]; it[$3, $4, n] = $5; next }
$1 == "ac" { acreq[$3] = $4; next }
$1 == "text" && $2 == "design.md" && $3 == "Phases" && match($6, /^- P([0-9]+):[[:space:]]*(.*)$/, m) { phasename[m[1]] = m[2]; if (m[1] + 0 > maxphase) maxphase = m[1] + 0; next }
$1 == "spec" { spec = $2; next }

END {
  # --- 各要素の Phase を決める ---------------------------------------------------
  for (j = 1; j <= ndef; j++) {
    id = order[j]; p = pf(id)
    if (p == "DES" || p == "TST") { ph[id] = F[id, "Phase"] + 0; if (ph[id] > maxphase) maxphase = ph[id] }
  }
  for (j = 1; j <= ndef; j++) {
    id = order[j]; p = pf(id)
    if (p == "API" && match(F[id, "Handler"], /(DES-[0-9]+)/, m)) ph[id] = ph[m[1]]
  }
  for (j = 1; j <= ndef; j++) {
    id = order[j]; p = pf(id)
    if (p == "IT") {
      x = ph[F[id, "Target"]] + 0
      nu = split(F[id, "Uses"], ul, /,[[:space:]]*/); for (i = 1; i <= nu; i++) if (ph[trim(ul[i])] + 0 > x) x = ph[trim(ul[i])] + 0
      ph[id] = x; itby[x] = itby[x] (itby[x] == "" ? "" : ", ") id
    } else if (p == "ST") {
      x = 0; r = F[id, "Target"]
      for (k = 1; k <= ndef; k++) { d = order[k]; if (pf(d) != "DES") continue
        ns = split(F[d, "Satisfies"], sl, /,[[:space:]]*/)
        for (i = 1; i <= ns; i++) { a = trim(sl[i]); sub(/\..*$/, "", a); if (a == r && ph[d] > x) x = ph[d] } }
      nu = split(F[id, "Uses"], ul, /,[[:space:]]*/); for (i = 1; i <= nu; i++) if (ph[trim(ul[i])] + 0 > x) x = ph[trim(ul[i])] + 0
      ph[id] = x; stby[x] = stby[x] (stby[x] == "" ? "" : ", ") id
    } else if (p == "E2E") {
      e2e = e2e (e2e == "" ? "" : ", ") id
    } else if (p == "UT" || p == "CT") {
      tests[parent[id] != "-" ? parent[id] : F[id, "Target"]] = tests[parent[id] != "-" ? parent[id] : F[id, "Target"]] ((tests[parent[id] != "-" ? parent[id] : F[id, "Target"]] == "") ? "" : ", ") id
      # UT / CT が参照するテストダブルは、その DES より先に用意する
      s = then_all(id)
      while (match(s, /TST-[0-9]+/, m)) { extra[parent[id], m[0]] = 1; s = substr(s, RSTART + RLENGTH) }
    }
  }
  # スモーク(API ごと)
  for (j = 1; j <= ndef; j++) {
    id = order[j]; if (pf(id) != "API") continue
    x = ph[id]; n = id; sub(/^API-/, "", n)
    smk[x] = smk[x] (smk[x] == "" ? "" : ", ") "SMK-L2-" id
    if (F[id, "Auth"] == "required") smk[x] = smk[x] ", SMK-L3-" id
    if (F[id, "Request"] != "" && F[id, "Request"] != "-") smk[x] = smk[x] ", SMK-L4-" id
    if (!(x in smkfirst)) { smkfirst[x] = 1; if (!firstsmk) { smk[x] = "SMK-L1, " smk[x]; firstsmk = 1 } }
  }

  # --- タスクを並べる ---------------------------------------------------------------
  ntool = 0; for (j = 1; j <= ndef; j++) if (pf(order[j]) == "TOOL") toolids[++ntool] = order[j]
  if (ntool > 0) add_task("P0-TOOLS", "tools", 0, "必要ツールの確認", joinlist(toolids, ntool))

  for (P = 0; P <= maxphase; P++) {
    # 同じ Phase の DES / TST を依存順に(Kahn 法、同順位は定義順)
    delete indeg; delete nodes; nn = 0
    for (j = 1; j <= ndef; j++) { id = order[j]; if ((pf(id) == "DES" || pf(id) == "TST") && ph[id] == P) { nodes[++nn] = id; indeg[id] = 0 } }
    delete edge
    for (a = 1; a <= nn; a++) {
      id = nodes[a]
      nd2 = split(F[id, "Depends"], dl2, /,[[:space:]]*/)
      for (i = 1; i <= nd2; i++) { dep = trim(dl2[i]); if ((dep in indeg) && !((dep, id) in edge)) { edge[dep, id] = 1; indeg[id]++ } }
      for (b = 1; b <= nn; b++) { t = nodes[b]; if (((id, t) in extra) && !((t, id) in edge)) { edge[t, id] = 1; indeg[id]++ } }
    }
    delete placed; placedn = 0
    while (placedn < nn) {
      progressed = 0
      for (a = 1; a <= nn; a++) {
        id = nodes[a]; if ((id in placed) || indeg[id] > 0) continue
        placed[id] = 1; placedn++; progressed = 1
        kind = F[id, "Kind"]
        add_task(id, (pf(id) == "DES" ? "des-" kind : "tst-" kind), P, name[id] "(" kind ")", tests[id])
        for (b = 1; b <= nn; b++) if ((id, nodes[b]) in edge) indeg[nodes[b]]--
        break
      }
      if (!progressed) { print "error: Phase " P " の依存が循環している" > "/dev/stderr"; exit 2 }
    }
    if (itby[P] != "") add_task("P" P "-IT", "it", P, "結合テスト(IT)", itby[P])
    if (stby[P] != "") add_task("P" P "-ST", "st", P, "システムテスト(ST)", stby[P])
    if (smk[P] != "") add_task("P" P "-SMK", "smk", P, "スモークテスト", smk[P])
    has = 0; for (i = 1; i <= nt; i++) if (tphase[i] == P && tkey[i] != "P0-TOOLS") has = 1
    if (has || P == 0 && ntool > 0) {
      add_task("P" P "-REFACTOR", "refactor", P, "リファクタ backlog の消化", "")
      add_task("P" P "-REVIEW", "review", P, "Phase " P " のレビュー", "")
    }
  }
  add_task("FINAL", "final", maxphase + 1, "E2E と全層の実行・最終レビュー・PR", e2e)

  if (mode == "tsv") {
    for (i = 1; i <= nt; i++) print tkey[i] "\t" ttype[i] "\t" tphase[i] "\t" ttitle[i] "\t" ttests[i] "\t" ((tkey[i] in isdone) ? "done" : "open")
    exit
  }

  print "<!-- GENERATED by spec-plan.sh: do not edit -->"
  print "# Tasks: " spec
  cur = -1
  for (i = 1; i <= nt; i++) {
    if (tphase[i] != cur) {
      cur = tphase[i]
      if (tkey[i] == "FINAL") print "\n## Final"
      else print "\n## P" cur ": " phasename[cur]
      print ""
    }
    line = "- [" ((tkey[i] in isdone) ? "x" : " ") "] " tkey[i] " " ttitle[i]
    if (ttests[i] != "") line = line " — " ttests[i]
    print line
  }
}
