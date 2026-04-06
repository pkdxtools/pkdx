///|
/// キャッシュ JSON の nested path からオブジェクトを取得
fn get_nested(json : Json, key1 : String) -> Json {
  match json {
    Object(m) =>
      match m.get(key1) {
        Some(j) => j
        _ => Json::null()
      }
    _ => Json::null()
  }
}

///|
/// キャッシュ JSON の nested path から int を取得 (long key: hp/atk/def/spa/spd/spe)
fn nested_int(json : Json, section : String, obj : String, key : String) -> Int {
  match json {
    Object(m) =>
      match m.get(section) {
        Some(Object(sec)) =>
          match sec.get(obj) {
            Some(Object(inner)) =>
              match inner.get(key) {
                Some(Number(n, ..)) => n.to_int()
                _ => 0
              }
            _ => 0
          }
        _ => 0
      }
    _ => 0
  }
}

///|
fn format_stat_table(json : Json) -> @markdown.Block {
  let header = [
    cell("ステータス"),
    cell("種族値"),
    cell("努力値"),
    cell("実数値"),
  ]
  let stat_labels = [
    "HP", "こうげき", "ぼうぎょ", "とくこう", "とくぼう", "すばやさ",
  ]
  let stat_keys = ["hp", "atk", "def", "spa", "spd", "spe"]
  let rows : Array[Array[@markdown.TableCell]] = []
  for i, label in stat_labels {
    let key = stat_keys[i]
    let base = nested_int(json, "pokemon", "base_stats", key)
    let ev = nested_int(json, "build", "evs", key)
    let actual = nested_int(json, "build", "actual_stats", key)
    rows.push([
      cell(label),
      cell(base.to_string()),
      cell(ev.to_string()),
      cell(actual.to_string()),
    ])
  }
  make_table(header, none_aligns(4), rows)
}

///|
fn format_move_table(json : Json) -> @markdown.Block {
  let header = [
    cell("技名"),
    cell("タイプ"),
    cell("分類"),
    cell("威力"),
    cell("命中"),
  ]
  let build = get_nested(json, "build")
  let rows : Array[Array[@markdown.TableCell]] = []
  for mv in json_array(build, "moves") {
    rows.push([
      cell(json_string(mv, "name")),
      cell(json_string(mv, "type")),
      cell(json_string(mv, "category")),
      cell(json_int(mv, "power").to_string()),
      cell(json_int(mv, "accuracy").to_string()),
    ])
  }
  make_table(header, none_aligns(5), rows)
}

///|
fn format_damage_calcs(json : Json) -> Array[@markdown.Block] {
  let blocks : Array[@markdown.Block] = []
  let calcs = json_array(json, "damage_calcs")
  if calcs.length() == 0 {
    return blocks
  }
  blocks.push(heading(2, "ダメージ計算結果"))
  for calc in calcs {
    let direction = json_string(calc, "direction")
    let opponent = json_string(calc, "opponent")
    let move_name = json_string(calc, "move")
    let dir_label = if direction == "attack" { "攻撃側" } else { "防御側" }
    blocks.push(heading(3, "\{dir_label} vs \{opponent} / \{move_name}"))
    let damages = json_array(calc, "damages")
    let percents = json_array(calc, "percents")
    if damages.length() > 0 {
      let dmg_header : Array[@markdown.TableCell] = [cell("")]
      let dmg_row : Array[@markdown.TableCell] = [cell("ダメージ")]
      let pct_row : Array[@markdown.TableCell] = [cell("割合")]
      for i in 0..<damages.length() {
        let roll = (85 + i).to_string()
        dmg_header.push(cell(roll))
        match damages[i] {
          Number(n, ..) => dmg_row.push(cell(n.to_int().to_string()))
          _ => dmg_row.push(cell("-"))
        }
        if i < percents.length() {
          match percents[i] {
            Number(n, ..) => {
              let pct = n * 100.0
              let pct_int = pct.to_int()
              let frac = ((pct - pct_int.to_double()) * 10.0).to_int()
              pct_row.push(cell("\{pct_int}.\{frac}%"))
            }
            _ => pct_row.push(cell("-"))
          }
        } else {
          pct_row.push(cell("-"))
        }
      }
      blocks.push(
        make_table(dmg_header, none_aligns(damages.length() + 1), [
          dmg_row, pct_row,
        ]),
      )
    }
    let ko = json_string(calc, "ko")
    if ko.length() > 0 {
      let ko_label = "確定数: \{ko}"
      blocks.push(
        @markdown.Block::Paragraph(
          children=[
            @markdown.Inline::Strong(
              marker=@markdown.EmphasisMarker::Asterisk,
              children=[text(ko_label)],
              span=s,
            ),
          ],
          span=s,
          leading_trivia=t,
          trailing_trivia=t,
        ),
      )
    }
  }
  blocks
}

///|
pub fn build_pokemon_document(json : Json, name : String) -> @markdown.Document {
  let blocks : Array[@markdown.Block] = []
  let pokemon = get_nested(json, "pokemon")
  let build = get_nested(json, "build")
  let type1 = json_string(pokemon, "type1")
  let type2 = json_string(pokemon, "type2")
  let types_str = if type2.length() > 0 {
    "\{type1}/\{type2}"
  } else {
    type1
  }
  let nature_name = json_string(build, "nature")
  let nature_up = json_string(build, "nature_up")
  let nature_down = json_string(build, "nature_down")
  let nature_str = "\{nature_name} (\{nature_up}↑ \{nature_down}↓)"
  let ability = json_string(build, "ability")
  let item = json_string(build, "item")

  blocks.push(heading(1, "\{name} 育成データ"))
  blocks.push(heading(2, "基本情報"))
  let info_header = [cell("項目"), cell("値")]
  let info_rows : Array[Array[@markdown.TableCell]] = [
    [cell("ポケモン"), cell(name)],
    [cell("タイプ"), cell(types_str)],
    [cell("性格"), cell(nature_str)],
    [cell("特性"), cell(ability)],
    [cell("持ち物"), cell(item)],
  ]
  blocks.push(make_table(info_header, none_aligns(2), info_rows))
  blocks.push(heading(2, "実数値 (Lv50, 6V)"))
  blocks.push(format_stat_table(json))
  blocks.push(heading(2, "技構成"))
  blocks.push(format_move_table(json))
  blocks.push_iter(format_damage_calcs(json).iter())
  blocks.push(heading(2, "ダメージ計算用コマンド"))
  let a_val = nested_int(json, "build", "actual_stats", "atk").to_string()
  let b_val = nested_int(json, "build", "actual_stats", "def").to_string()
  let hp_val = nested_int(json, "build", "actual_stats", "hp").to_string()
  let atk_cmd = "bin/pkdx damage \"\{name}\" \"<相手>\" \"<技>\" --atk-stat \{a_val} --atk-ability \"\{ability}\" --atk-item \"\{item}\""
  let def_cmd = "bin/pkdx damage \"<相手>\" \"\{name}\" \"<技>\" --def-stat \{b_val} --def-hp \{hp_val}"
  blocks.push(
    @markdown.Block::Paragraph(
      children=[text("攻撃側として:")],
      span=s,
      leading_trivia=t,
      trailing_trivia=t,
    ),
  )
  blocks.push(
    @markdown.Block::FencedCode(
      fence_marker=@markdown.FenceMarker::Backtick,
      fence_length=3,
      info="bash",
      code=atk_cmd + "\n",
      indent=0,
      span=s,
      leading_trivia=t,
      trailing_trivia=t,
    ),
  )
  blocks.push(
    @markdown.Block::Paragraph(
      children=[text("防御側として:")],
      span=s,
      leading_trivia=t,
      trailing_trivia=t,
    ),
  )
  blocks.push(
    @markdown.Block::FencedCode(
      fence_marker=@markdown.FenceMarker::Backtick,
      fence_length=3,
      info="bash",
      code=def_cmd + "\n",
      indent=0,
      span=s,
      leading_trivia=t,
      trailing_trivia=t,
    ),
  )

  { frontmatter: None, children: blocks, span: s }
}
