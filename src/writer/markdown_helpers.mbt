///|
/// Empty span/trivia placeholders used by every constructor below. Generated
/// AST nodes are always serialized from scratch (no source location is carried
/// through), so an empty span/trivia is the canonical "no extra trivia" value
/// for every node this package emits.
let s : @markdown.Span = @markdown.Span::empty()

///|
let t : @markdown.Trivia = @markdown.Trivia::empty()

///|
fn text(content : String) -> @markdown.Inline {
  @markdown.Inline::Text(content~, span=s)
}

///|
fn heading(level : Int, content : String) -> @markdown.Block {
  @markdown.Block::Heading(
    level~,
    style=@markdown.HeadingStyle::Atx,
    children=[text(content)],
    closing_hashes=0,
    span=s,
    leading_trivia=t,
    trailing_trivia=t,
  )
}

///|
/// Markdown テーブル セル は 1 行で完結する必要があり、改行や復帰文字が残ると行が壊れる。
/// 自由入力メモ (members[].role) が user 起源でサニタイズされていないため、
/// 空白系制御文字を半角スペース 1 個に正規化してから cell に詰める。
/// パイプ `|` は mizchi/markdown 側が `\|` に自動エスケープする。
fn normalize_cell_text(content : String) -> String {
  let buf = StringBuilder::new()
  for c in content {
    match c {
      '\n' | '\r' | '\t' => buf.write_char(' ')
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn cell(content : String) -> @markdown.TableCell {
  { children: [text(normalize_cell_text(content))], span: s }
}

///|
fn bullet_list(items : Array[String]) -> @markdown.Block {
  let list_items = items.map(fn(item) -> @markdown.ListItem {
    {
      children: [
        @markdown.Block::Paragraph(
          children=[text(item)],
          span=s,
          leading_trivia=t,
          trailing_trivia=t,
        ),
      ],
      checked: None,
      marker_offset: 0,
      content_offset: 2,
      span: s,
    }
  })
  @markdown.Block::BulletList(
    marker=@markdown.BulletMarker::Dash,
    tight=true,
    items=list_items,
    span=s,
    leading_trivia=t,
    trailing_trivia=t,
  )
}

///|
fn make_table(
  header : Array[@markdown.TableCell],
  alignments : Array[@markdown.TableAlign],
  rows : Array[Array[@markdown.TableCell]],
) -> @markdown.Block {
  @markdown.Block::Table(
    header~,
    alignments~,
    rows~,
    span=s,
    leading_trivia=t,
    trailing_trivia=t,
  )
}

///|
fn none_aligns(n : Int) -> Array[@markdown.TableAlign] {
  let arr : Array[@markdown.TableAlign] = []
  for _i in 0..<n {
    arr.push(@markdown.TableAlign::None)
  }
  arr
}
