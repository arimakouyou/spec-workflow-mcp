# spec-parse.awk — 1 つの spec 文書を索引レコード(TSV)に変換する。
# 文法の定義は rules/doc-format.md。使い方: gawk -v doc=design.md -f spec-parse.awk <file>
#
# 出力レコード(1 行 1 レコード、タブ区切り):
#   fm     doc key value                 frontmatter
#   sec    doc title line                ## 見出し
#   hdr    doc level title line          ID を持たない ###/#### 見出し
#   grp    doc ID line                   test-design の ### DES-N グループ見出し
#   def    doc ID name line section parent
#   field  doc ID Field value line
#   item   doc ID Field text line        欄の下位項目
#   ac     doc ACID REQID text line
#   code   doc ID Field codeline line
#   text   doc section ID Field content line   コードブロック外の本文すべて
#   sym    doc ID path kind              コードから抽出した宣言(kind: trait|impl|type|fn)
#   sig    doc ID path params ret        関数シグネチャ(params は self を除く引数名のカンマ区切り)
#   member doc ID Type member            構造体のフィールド / enum の variant

function clean(s) { gsub(/\t/, " ", s); sub(/\r$/, "", s); return s }
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }

# 括弧の深さを見てトップレベルのカンマで分割する
function split_top(s, out,    n, i, c, d, buf) {
  n = 0; d = 0; buf = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(" || c == "<" || c == "[" || c == "{") d++
    else if (c == ")" || c == ">" || c == "]" || c == "}") d--
    if (c == "," && d == 0) { out[++n] = trim(buf); buf = ""; continue }
    buf = buf c
  }
  if (trim(buf) != "") out[++n] = trim(buf)
  return n
}

function param_names(s,    parts, n, i, p, name, res) {
  n = split_top(s, parts); res = ""
  for (i = 1; i <= n; i++) {
    p = parts[i]
    if (p ~ /^&?('[a-z_]+[[:space:]]+)?(mut[[:space:]]+)?self$/) continue
    if (p ~ /^(mut[[:space:]]+)?self[[:space:]]*:/) continue
    name = p
    if (index(p, ":") > 0) name = trim(substr(p, 1, index(p, ":") - 1))
    sub(/^mut[[:space:]]+/, "", name)
    res = (res == "" ? name : res "," name)
  }
  return res
}

# 1 つの fn シグネチャ文字列を解析して sig / sym を出力する
function emit_fn(id, container, sigtext,    m, name, rest, i, c, d, pstart, params, ret, path) {
  if (!match(sigtext, /fn[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m)) return
  name = m[1]
  rest = substr(sigtext, RSTART + RLENGTH)
  sub(/^<[^(]*>/, "", rest)
  pstart = index(rest, "(")
  if (pstart == 0) return
  d = 0; params = ""
  for (i = pstart; i <= length(rest); i++) {
    c = substr(rest, i, 1)
    if (c == "(") { d++; if (d == 1) continue }
    if (c == ")") { d--; if (d == 0) break }
    params = params c
  }
  ret = substr(rest, i + 1)
  if (match(ret, /->/)) ret = substr(ret, RSTART + 2); else ret = ""
  sub(/[[:space:]]*(where.*)?[;{][[:space:]]*$/, "", ret)
  ret = trim(ret)
  path = (container != "" ? container "::" name : name)
  print "sig", doc, id, path, param_names(params), clean(ret)
  print "sym", doc, id, path, "fn"
}

# 行内に書かれた { ... } の中身から variant / フィールドを取り出す
function emit_inline_members(id, tname, body,    parts, n, i, p, m) {
  n = split_top(body, parts)
  for (i = 1; i <= n; i++) {
    p = parts[i]
    if (match(p, /^(pub[[:space:]]+)?([a-z_][A-Za-z0-9_]*)[[:space:]]*:/, m)) print "member", doc, id, tname, m[2]
    else if (match(p, /^([A-Z][A-Za-z0-9_]*)/, m)) print "member", doc, id, tname, m[1]
  }
}

function brace_delta(s,    t, o, c) {
  t = s
  gsub(/"([^"\\]|\\.)*"/, "", t)
  o = gsub(/\{/, "{", t); c = gsub(/\}/, "}", t)
  return o - c
}

# コードブロック(Interfaces / Definition)から宣言を抽出する(Rust)
function analyze_code(id, n,    i, L, m, depth, container, ckind, sigbuf, insig, tname, inner) {
  depth = 0; container = ""; ckind = ""; sigbuf = ""; insig = 0
  for (i = 1; i <= n; i++) {
    L = codebuf[i]
    sub(/\/\/.*$/, "", L)
    if (insig) {
      sigbuf = sigbuf " " trim(L)
      if (L ~ /[;{][[:space:]]*$/) { emit_fn(id, (depth >= 1 ? container : ""), sigbuf); insig = 0; depth += brace_delta(L); if (depth <= 0) { depth = 0; container = "" } }
      continue
    }
    if (L ~ /^[[:space:]]*#\[/ || L ~ /^[[:space:]]*use[[:space:]]/ || L ~ /^[[:space:]]*$/) continue
    if (depth == 0) {
      if (match(L, /^[[:space:]]*(pub(\([^)]*\))?[[:space:]]+)?(unsafe[[:space:]]+)?trait[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m)) {
        container = m[4]; ckind = "trait"; print "sym", doc, id, container, "trait"
      } else if (match(L, /^[[:space:]]*impl(<[^>]*>)?[[:space:]]+([A-Za-z_][A-Za-z0-9_:<>]*)([[:space:]]+for[[:space:]]+([A-Za-z_][A-Za-z0-9_]*))?/, m)) {
        container = (m[4] != "" ? m[4] : m[2]); sub(/<.*$/, "", container); ckind = "impl"
        print "sym", doc, id, container, "impl"
      } else if (match(L, /^[[:space:]]*(pub(\([^)]*\))?[[:space:]]+)?(struct|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)/, m)) {
        tname = m[4]; ckind = m[3]; container = tname
        print "sym", doc, id, tname, "type"
        if (match(L, /\{(.*)\}/, inner)) { emit_inline_members(id, tname, inner[1]); container = ""; continue }
      } else if (match(L, /(^|[[:space:]])fn[[:space:]]+[A-Za-z_]/)) {
        if (L ~ /[;{][[:space:]]*$/) emit_fn(id, "", L); else { sigbuf = L; insig = 1 }
        depth += brace_delta(L); if (depth < 0) depth = 0
        continue
      }
      depth += brace_delta(L); if (depth <= 0) { depth = 0; container = "" }
      continue
    }
    # depth >= 1: コンテナの中
    if (depth == 1 && (ckind == "trait" || ckind == "impl") && match(L, /(^|[[:space:]])fn[[:space:]]+[A-Za-z_]/)) {
      if (L ~ /[;{][[:space:]]*$/) emit_fn(id, container, L); else { sigbuf = L; insig = 1; continue }
    } else if (depth == 1 && ckind == "struct" && match(L, /^[[:space:]]*(pub(\([^)]*\))?[[:space:]]+)?([a-z_][A-Za-z0-9_]*)[[:space:]]*:/, m)) {
      print "member", doc, id, container, m[3]
    } else if (depth == 1 && ckind == "enum" && match(L, /^[[:space:]]*([A-Z][A-Za-z0-9_]*)[[:space:]]*([,({]|$)/, m)) {
      print "member", doc, id, container, m[1]
    }
    depth += brace_delta(L); if (depth <= 0) { depth = 0; container = "" }
  }
}

BEGIN { OFS = "\t"; in_fm = 0; in_code = 0; cur = ""; field = ""; group = ""; section = "-"; ncode = 0 }

NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
in_fm {
  if ($0 ~ /^---[[:space:]]*$/) { in_fm = 0; next }
  if (match($0, /^([A-Za-z_]+):[[:space:]]*(.*)$/, fm)) { v = fm[2]; sub(/[[:space:]]+#.*$/, "", v); print "fm", doc, fm[1], clean(v) }
  next
}

# コードフェンス
/^[[:space:]]*```/ {
  if (!in_code) { in_code = 1; ncode = 0; code_id = cur; code_field = field; match($0, /^[[:space:]]*/); code_indent = RLENGTH; next }
  in_code = 0
  if (code_id != "" && (code_field == "Interfaces" || code_field == "Definition")) analyze_code(code_id, ncode)
  next
}
in_code {
  line = $0
  if (code_indent > 0 && substr(line, 1, code_indent) ~ /^[[:space:]]*$/) line = substr(line, code_indent + 1)
  codebuf[++ncode] = line
  print "code", doc, code_id, code_field, clean(line), NR
  next
}

# 見出し
match($0, /^(#+)[[:space:]]+(.*)$/, h) {
  lvl = length(h[1]); t = clean(trim(h[2])); field = ""
  if (lvl <= 2) { cur = ""; group = ""; if (lvl == 2) { section = t; print "sec", doc, t, NR } }
  else if (lvl == 3 && match(t, /^(RQ|REQ|NFR|JRN|DES|MOD|API|TST|DEP|TOOL|KD|IT|ST|E2E)-([0-9]+)(:[[:space:]]*(.*))?$/, d)) {
    id = d[1] "-" d[2]
    if (doc == "test-design.md" && d[1] == "DES" && d[3] == "") { group = id; cur = ""; print "grp", doc, id, NR }
    else { cur = id; print "def", doc, id, d[4], NR, section, "-" }
  }
  else if (lvl == 4 && match(t, /^(UT|CT)-([0-9]+\.[0-9]+):[[:space:]]*(.*)$/, d)) {
    cur = d[1] "-" d[2]; print "def", doc, cur, d[3], NR, section, (group == "" ? "-" : group)
  }
  else { cur = ""; print "hdr", doc, lvl, t, NR }
  # 見出しも本文として走査の対象にする(行番号参照・未記入・コード表記は見出しにも入りうる)
  print "text", doc, section, (cur == "" ? "-" : cur), "-", t, NR
  next
}

{
  raw = clean($0)
  if (cur != "") {
    if (match(raw, /^- (REQ-[0-9]+\.[0-9]+):[[:space:]]*(.*)$/, a)) {
      field = ""; print "ac", doc, a[1], cur, a[2], NR
    } else if (match(raw, /^- ([A-Z][A-Za-z-]*):[[:space:]]?(.*)$/, f)) {
      field = f[1]; print "field", doc, cur, field, trim(f[2]), NR
    } else if (field != "" && match(raw, /^[[:space:]]+- (.*)$/, it)) {
      print "item", doc, cur, field, trim(it[1]), NR
    } else if (raw !~ /^[[:space:]]*$/ && raw !~ /^[[:space:]]/) {
      field = ""
    }
  }
  if (raw !~ /^[[:space:]]*$/) print "text", doc, section, (cur == "" ? "-" : cur), (field == "" ? "-" : field), raw, NR
}
