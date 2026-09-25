# signorm.awk — Rust のソース / Interfaces から関数シグネチャを取り出し、比較用に正規化して 1 行ずつ出力する。
# 正規化: コメント除去、可視性(pub / pub(crate) 等)を除去、空白をすべて除去、閉じ括弧直前のカンマを除去。
# async / unsafe / const / extern は署名の一部として残す。本体の { と宣言の ; の手前までを署名とする。

function flush_sig(s) {
  gsub(/[[:space:]]+/, "", s)
  gsub(/,\)/, ")", s); gsub(/,>/, ">", s); gsub(/,\]/, "]", s)
  print s
}

{
  line = $0
  sub(/\/\/.*$/, "", line)
  buf = buf " " line
}

END {
  s = buf
  while (match(s, /((async|unsafe|const|extern("[^"]*")?)[[:space:]]+)*fn[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
    start = RSTART
    rest = substr(s, start)
    d = 0; out = ""
    for (i = 1; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "(" || c == "[" ) d++
      else if (c == ")" || c == "]") d--
      if (d == 0 && (c == "{" || c == ";")) break
      out = out c
    }
    flush_sig(out)
    s = substr(rest, i + 1)
  }
}
