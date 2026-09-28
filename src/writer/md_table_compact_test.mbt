///|
/// mizchi/markdown はテーブルセルを列幅で揃えて出力するため、期待値を
/// `| a | b |` の最小形に正規化してから比較する。
fn compact_tables(md : String) -> String {
  let out = StringBuilder()
  let mut first = true
  for line in md.split("\n") {
    if !first {
      out.write_char('\n')
    }
    first = false
    let line_str = line.to_owned()
    if line_str.has_prefix("|") {
      out.write_string(compact_table_line(line_str))
    } else {
      out.write_string(line_str)
    }
  }
  out.to_string()
}

///|
fn compact_table_line(line : String) -> String {
  let cells : Array[String] = []
  for piece in line.split("|") {
    cells.push(piece.to_owned().trim().to_owned())
  }
  let out = StringBuilder()
  for i, c in cells {
    if i == 0 || i == cells.length() - 1 {
      continue
    }
    out.write_string("| ")
    out.write_string(if is_delimiter_cell(c) { "---" } else { c })
    out.write_char(' ')
  }
  out.write_char('|')
  out.to_string()
}

///|
fn is_delimiter_cell(c : String) -> Bool {
  c.length() >= 3 && c.iter().all(fn(ch) { ch == '-' || ch == ':' })
}

///|
test "compact_tables: collapses padded cells and delimiter runs" {
  let padded =
    #|| 項目   | 値                 |
    #|| ---- | ----------------- |
    #|| ポケモン | ガブリアス             |
    #|text line
  let expected =
    #|| 項目 | 値 |
    #|| --- | --- |
    #|| ポケモン | ガブリアス |
    #|text line
  assert_true(compact_tables(padded) == expected)
}
