///|
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
fn json_string(json : Json, key : String) -> String {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(String(v)) => v
        _ => ""
      }
    _ => ""
  }
}

///|
fn json_int(json : Json, key : String) -> Int {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
}

///|
fn json_array(json : Json, key : String) -> Array[Json] {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(Array(arr)) => arr
        _ => []
      }
    _ => []
  }
}

///|
fn json_string_array(json : Json, key : String) -> Array[String] {
  json_array(json, key).map(fn(j) -> String {
    match j {
      String(v) => v
      _ => ""
    }
  })
}

///|
fn format_stats(json : Json, key : String) -> String {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(Object(st)) => {
          let get = fn(k : String) -> String {
            match st.get(k) {
              Some(Number(n, ..)) => n.to_int().to_string()
              _ => "0"
            }
          }
          let h = get("h")
          let a = get("a")
          let b = get("b")
          let c = get("c")
          let d = get("d")
          let sp = get("s")
          "\{h}/\{a}/\{b}/\{c}/\{d}/\{sp}"
        }
        _ => "0/0/0/0/0/0"
      }
    _ => "0/0/0/0/0/0"
  }
}

///|
/// member に optional で保持する nature / stat_points / actual_stats を
/// "-" フォールバック付きで取り出す。Json::null / 欠損 / 0 埋めを区別せず
/// 表示上すべて "-" 扱いにすると SP=0 の振りを消してしまうため、存在する
/// キーは値として出すが、親キーが null/欠損なら "-" を返す。
fn format_stats_opt(json : Json, key : String) -> String {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(Object(st)) => {
          let get = fn(k : String) -> String {
            match st.get(k) {
              Some(Number(n, ..)) => n.to_int().to_string()
              _ => "-"
            }
          }
          let h = get("h")
          let a = get("a")
          let b = get("b")
          let c = get("c")
          let d = get("d")
          let sp = get("s")
          "\{h}/\{a}/\{b}/\{c}/\{d}/\{sp}"
        }
        _ => "-"
      }
    _ => "-"
  }
}

///|
/// nullable 文字列用。null / 欠損 / 空文字 を "-" として扱う。
fn json_string_opt(json : Json, key : String) -> String {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(String(v)) => if v.length() == 0 { "-" } else { v }
        _ => "-"
      }
    _ => "-"
  }
}

///|
/// members に育成データ (nature / stat_points / actual_stats) が 1 つでも
/// 入っているかを判定。全員 null / 欠損なら育成テーブル自体を出さない。
fn has_any_build_data(members : Array[Json]) -> Bool {
  for m in members {
    match m {
      Object(obj) => {
        match obj.get("nature") {
          Some(String(s)) if s.length() > 0 => return true
          _ => ()
        }
        match obj.get("stat_points") {
          Some(Object(_)) => return true
          _ => ()
        }
        match obj.get("actual_stats") {
          Some(Object(_)) => return true
          _ => ()
        }
      }
      _ => ()
    }
  }
  false
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

///|
/// 性格 / SP or EV / 実数値を 1 つのテーブルにまとめる。
/// select が damage 計算で利用するフィールドのため、各メンバーの欠損状況が
/// 可視化されていることが重要。欠損セルは "-" で空値を示す。
fn build_build_data_table(members : Array[Json]) -> @markdown.Block {
  let header = [
    cell("#"),
    cell("ポケモン"),
    cell("性格"),
    cell("SP/EV (H/A/B/C/D/S)"),
    cell("実数値 (H/A/B/C/D/S)"),
  ]
  let rows : Array[Array[@markdown.TableCell]] = []
  for i, m in members {
    rows.push([
      cell((i + 1).to_string()),
      cell(json_string(m, "name")),
      cell(json_string_opt(m, "nature")),
      cell(format_stats_opt(m, "stat_points")),
      cell(format_stats_opt(m, "actual_stats")),
    ])
  }
  make_table(header, none_aligns(5), rows)
}

///|
fn build_members_table(members : Array[Json]) -> @markdown.Block {
  let header = [
    cell("#"),
    cell("ポケモン"),
    cell("タイプ"),
    cell("種族値 (H/A/B/C/D/S)"),
    cell("特性"),
    cell("持ち物"),
    cell("メモ"),
  ]
  let rows : Array[Array[@markdown.TableCell]] = []
  for i, m in members {
    let types_arr = json_string_array(m, "types")
    let types_str = types_arr.join("/")
    let bs_str = format_stats(m, "base_stats")
    rows.push([
      cell((i + 1).to_string()),
      cell(json_string(m, "name")),
      cell(types_str),
      cell(bs_str),
      cell(json_string(m, "ability")),
      cell(json_string(m, "item")),
      cell(json_string(m, "role")),
    ])
  }
  make_table(header, none_aligns(7), rows)
}

///|
fn build_moves_section(members : Array[Json]) -> Array[@markdown.Block] {
  let blocks : Array[@markdown.Block] = []
  for m in members {
    let name = json_string(m, "name")
    blocks.push(heading(3, name))
    let header = [
      cell("技名"),
      cell("タイプ"),
      cell("分類"),
      cell("威力"),
    ]
    let rows : Array[Array[@markdown.TableCell]] = []
    for mv in json_array(m, "moves") {
      rows.push([
        cell(json_string(mv, "name")),
        cell(json_string(mv, "type")),
        cell(json_string(mv, "category")),
        cell(json_int(mv, "power").to_string()),
      ])
    }
    blocks.push(make_table(header, none_aligns(4), rows))
  }
  blocks
}

///|
fn build_coverage_table(coverage : Array[Json]) -> @markdown.Block {
  let header = [
    cell("防御タイプ"),
    cell("最大打点の技タイプ"),
    cell("使用者"),
    cell("倍率"),
  ]
  let rows : Array[Array[@markdown.TableCell]] = []
  for c in coverage {
    rows.push([
      cell(json_string(c, "def_type")),
      cell(json_string(c, "best_move_type")),
      cell(json_string(c, "user")),
      cell(json_string(c, "multiplier")),
    ])
  }
  make_table(header, none_aligns(4), rows)
}

///|
fn build_defense_table(
  defense_matrix : Array[Json],
  members : Array[Json],
) -> @markdown.Block {
  let member_names = members.map(fn(m) -> String { json_string(m, "name") })
  let header_cells : Array[@markdown.TableCell] = [cell("攻撃タイプ")]
  let col_count = member_names.length() + 2
  for name in member_names {
    header_cells.push(cell(name))
  }
  header_cells.push(cell("最善受け先"))
  let rows : Array[Array[@markdown.TableCell]] = []
  for entry in defense_matrix {
    let row_cells : Array[@markdown.TableCell] = [
      cell(json_string(entry, "atk_type")),
    ]
    match entry {
      Object(m) =>
        match m.get("matchups") {
          Some(Object(matchups)) =>
            for name in member_names {
              match matchups.get(name) {
                Some(String(v)) => row_cells.push(cell(v))
                _ => row_cells.push(cell("-"))
              }
            }
          _ =>
            for _name in member_names {
              row_cells.push(cell("-"))
            }
        }
      _ =>
        for _name in member_names {
          row_cells.push(cell("-"))
        }
    }
    row_cells.push(cell(json_string(entry, "best_switch")))
    rows.push(row_cells)
  }
  make_table(header_cells, none_aligns(col_count), rows)
}

///|
fn build_matchup_plans(
  plans : Array[Json],
  battle_format : String,
) -> Array[@markdown.Block] {
  let blocks : Array[@markdown.Block] = []
  let sep = " + "
  for plan in plans {
    let opponent = json_string(plan, "opponent")
    let opp_type = json_string(plan, "opponent_type")
    blocks.push(heading(3, "vs \{opponent} (\{opp_type})"))
    let leads = json_string_array(plan, "leads")
    let backs = json_string_array(plan, "backs")
    let reason = json_string(plan, "reason")
    if battle_format == "doubles" {
      let leads_str = leads.join(sep)
      let backs_str = backs.join(sep)
      let items = [
        "先発: \{leads_str}",
        "後発: \{backs_str}",
        "理由: \{reason}",
      ]
      blocks.push(bullet_list(items))
    } else {
      let all : Array[String] = []
      all.push_iter(leads.iter())
      all.push_iter(backs.iter())
      let all_str = all.join(sep)
      let items = ["選出: \{all_str}", "理由: \{reason}"]
      blocks.push(bullet_list(items))
    }
  }
  blocks
}

///|
/// 表選出 / 裏選出 を「### 表選出 | ### 裏選出」の 2 セクションに分けて emit。
/// members が空 (未入力) の場合そのセクションは省略する。
fn build_selection_plan_block(
  plan : Json,
  heading_text : String,
) -> Array[@markdown.Block] {
  let blocks : Array[@markdown.Block] = []
  let members = json_string_array(plan, "members")
  if members.length() == 0 {
    return blocks
  }
  blocks.push(heading(3, heading_text))
  let sep = " + "
  let members_str = members.join(sep)
  let items : Array[String] = ["選出: \{members_str}"]
  blocks.push(bullet_list(items))
  let note = json_string(plan, "note")
  if note.length() > 0 {
    blocks.push(
      @markdown.Block::Paragraph(
        children=[text(note)],
        span=s,
        leading_trivia=t,
        trailing_trivia=t,
      ),
    )
  }
  blocks
}

///|
pub fn build_team_document(
  json : Json,
  axis : String,
  date : String,
  publish~ : Bool = false,
) -> @markdown.Document {
  let blocks : Array[@markdown.Block] = []
  let battle_format = json_string(json, "battle_format")
  let mechanics = json_string(json, "mechanics")
  let version = json_string(json, "version")
  let members = json_array(json, "members")

  blocks.push(heading(1, "\{axis}軸構築 - \{date}"))
  blocks.push(heading(2, "フォーマット"))
  blocks.push(
    bullet_list([
      "バトル形式: \{battle_format}",
      "メカニクス: \{mechanics}",
      "ゲームバージョン: \{version}",
    ]),
  )
  let concept = json_string(json, "concept")
  if concept.length() > 0 {
    blocks.push(heading(2, "構築コンセプト"))
    blocks.push(
      @markdown.Block::Paragraph(
        children=[text(concept)],
        span=s,
        leading_trivia=t,
        trailing_trivia=t,
      ),
    )
  }
  blocks.push(heading(2, "チーム"))
  blocks.push(build_members_table(members))
  if has_any_build_data(members) {
    blocks.push(heading(2, "育成データ"))
    blocks.push(build_build_data_table(members))
  }
  blocks.push(heading(2, "推奨技構成"))
  blocks.push_iter(build_moves_section(members).iter())
  let coverage = json_array(json, "coverage")
  if coverage.length() > 0 {
    blocks.push(heading(2, "攻撃カバー率"))
    blocks.push(build_coverage_table(coverage))
  }
  let defense = json_array(json, "defense_matrix")
  if defense.length() > 0 {
    blocks.push(heading(2, "防御相性マトリクス"))
    blocks.push(build_defense_table(defense, members))
  }
  let empty_obj : Json = ({} : Map[String, Json]).to_json()
  let primary_sel = match json {
    Object(root) =>
      match root.get("primary_selection") {
        Some(v) => v
        None => empty_obj
      }
    _ => empty_obj
  }
  let alternate_sel = match json {
    Object(root) =>
      match root.get("alternate_selection") {
        Some(v) => v
        None => empty_obj
      }
    _ => empty_obj
  }
  let primary_blocks = build_selection_plan_block(primary_sel, "表選出")
  let alternate_blocks = build_selection_plan_block(
    alternate_sel, "裏選出",
  )
  if primary_blocks.length() > 0 || alternate_blocks.length() > 0 {
    blocks.push(heading(2, "選出パターン"))
    blocks.push_iter(primary_blocks.iter())
    blocks.push_iter(alternate_blocks.iter())
  }
  // 旧 schema 互換: primary/alternate が空で matchup_plans があれば従来の
  // 「vs 相手」カードを emit (既存 meta.json 取り込み向け)。
  let plans = json_array(json, "matchup_plans")
  let has_new = primary_blocks.length() > 0 || alternate_blocks.length() > 0
  if not(has_new) && plans.length() > 0 {
    blocks.push(heading(2, "選出パターン"))
    blocks.push_iter(build_matchup_plans(plans, battle_format).iter())
  }
  {
    frontmatter: Some(build_team_frontmatter(json, axis, date, publish~)),
    children: blocks,
    span: s,
  }
}

///|
/// Build a YAML frontmatter for the generated team markdown.
///
/// The block_parser in mizchi/markdown only understands `key: value` lines and
/// strips surrounding quotes, so we emit one scalar per line and rely on
/// downstream Astro (gray-matter) for proper YAML parsing of flow arrays.
pub fn build_team_frontmatter(
  json : Json,
  axis : String,
  date : String,
  publish~ : Bool = false,
) -> @markdown.Frontmatter {
  let battle_format = json_string(json, "battle_format")
  let mechanics = json_string(json, "mechanics")
  let version = json_string(json, "version")
  let regulation = json_string(json, "regulation")
  let members = json_array(json, "members")
  let member_names = members.map(fn(m) -> String { json_string(m, "name") })
  let title = "\{axis}軸構築 - \{date}"
  let entries : Array[(String, String)] = []
  let buf = StringBuilder::new()
  fn add_quoted(key : String, value : String) -> Unit {
    entries.push((key, value))
    buf.write_string(key)
    buf.write_string(": ")
    buf.write_string(yaml_escape_double_quoted(value))
    buf.write_char('\n')
  }

  fn add_plain(key : String, value : String) -> Unit {
    entries.push((key, value))
    buf.write_string(key)
    buf.write_string(": ")
    buf.write_string(value)
    buf.write_char('\n')
  }

  add_quoted("title", title)
  add_quoted("axis", axis)
  add_plain("date", date)
  add_plain("battle_format", battle_format)
  add_quoted("mechanics", mechanics)
  add_plain("version", version)
  if regulation.length() > 0 {
    add_quoted("regulation", regulation)
  }
  let members_value = yaml_string_array(member_names)
  add_plain("members", members_value)
  add_plain("tags", "[]")
  add_plain("edited", "false")
  // `published: false` を既定にして、構築を意図せず公開しない。`--publish` で
  // `true` に書き換わる。team-builder Phase 8 の「構築ブログで公開するか」
  // 質問で「はい」が選ばれた時のみ build_team_document(publish=true) が呼ばれる。
  let published_value = if publish { "true" } else { "false" }
  add_plain("published", published_value)
  add_plain("generated_by", "team-builder")
  add_plain("schema_version", "1")
  { raw: buf.to_string(), entries, span: s }
}

///|
/// Return true when the given markdown text carries a frontmatter with
/// `edited: true`. Unlocked on: missing frontmatter, missing `edited` key,
/// non-literal-"true" values, and parse failures.
pub fn has_edit_lock(md_text : String) -> Bool {
  if md_text.length() == 0 {
    return false
  }
  let result = @markdown.parse(md_text)
  match result.document.frontmatter {
    Some(fm) => {
      for entry in fm.entries {
        let (k, v) = entry
        if k == "edited" {
          return v == "true"
        }
      }
      false
    }
    None => false
  }
}

///|
/// Escape a string for embedding in a YAML double-quoted scalar.
/// Only `\` and `"` are escaped — keeping the parser contract simple.
fn yaml_escape_double_quoted(content : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for c in content {
    match c {
      '\\' => buf.write_string("\\\\")
      '"' => buf.write_string("\\\"")
      _ => buf.write_char(c)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// Emit a YAML flow-style string array: `["a", "b"]`.
fn yaml_string_array(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  buf.write_char('[')
  let mut first = true
  for item in items {
    if not(first) {
      buf.write_string(", ")
    }
    first = false
    buf.write_string(yaml_escape_double_quoted(item))
  }
  buf.write_char(']')
  buf.to_string()
}
