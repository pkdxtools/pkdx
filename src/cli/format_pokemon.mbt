///|
/// Format a Pokemon as JSON.
fn pokemon_to_json(p : @model.Pokemon) -> String {
  let t2 = if p.type2.length() > 0 { "\"" + p.type2 + "\"" } else { "null" }
  let a2 = if p.ability2.length() > 0 {
    "\"" + p.ability2 + "\""
  } else {
    "null"
  }
  let da = if p.dream_ability.length() > 0 {
    "\"" + p.dream_ability + "\""
  } else {
    "null"
  }
  "{\"globalNo\":\"" +
  p.global_no +
  "\",\"name_ja\":\"" +
  p.name_ja +
  "\",\"name_en\":\"" +
  p.name_en +
  "\",\"type1\":\"" +
  p.type1 +
  "\",\"type2\":" +
  t2 +
  ",\"hp\":" +
  p.hp.to_string() +
  ",\"atk\":" +
  p.atk.to_string() +
  ",\"def\":" +
  p.def_.to_string() +
  ",\"spa\":" +
  p.spa.to_string() +
  ",\"spd\":" +
  p.spd.to_string() +
  ",\"spe\":" +
  p.spe.to_string() +
  ",\"bst\":" +
  p.bst.to_string() +
  ",\"ability1\":\"" +
  p.ability1 +
  "\",\"ability2\":" +
  a2 +
  ",\"dream_ability\":" +
  da +
  (if p.forms.length() > 0 {
    ",\"forms\":" + forms_to_json(p.forms)
  } else {
    ""
  }) +
  "}"
}

///|
/// forms[] を JSON 配列文字列に変換する (呼び出し側で空配列判定済み)。
fn forms_to_json(forms : Array[String]) -> String {
  let mut s = "["
  for i = 0; i < forms.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    s = s + "\"" + forms[i] + "\""
  }
  s + "]"
}

///|
/// forms[] を ", " 区切りで連結する (table 表示用)。
fn forms_joined(forms : Array[String]) -> String {
  let mut s = ""
  for i = 0; i < forms.length(); i = i + 1 {
    if i > 0 {
      s = s + ", "
    }
    s = s + forms[i]
  }
  s
}

///|
/// Format a Pokemon as a table row.
fn pokemon_to_table(p : @model.Pokemon) -> String {
  let type_str = if p.type2.length() > 0 {
    p.type1 + "/" + p.type2
  } else {
    p.type1
  }
  p.name_ja +
  " (" +
  p.name_en +
  ")  No." +
  p.global_no +
  "\n" +
  "Type: " +
  type_str +
  "\n" +
  "HP:" +
  pad_right(p.hp.to_string(), 4) +
  " Atk:" +
  pad_right(p.atk.to_string(), 4) +
  " Def:" +
  pad_right(p.def_.to_string(), 4) +
  " SpA:" +
  pad_right(p.spa.to_string(), 4) +
  " SpD:" +
  pad_right(p.spd.to_string(), 4) +
  " Spe:" +
  pad_right(p.spe.to_string(), 4) +
  " BST:" +
  p.bst.to_string() +
  "\n" +
  "Abilities: " +
  p.ability1 +
  (if p.ability2.length() > 0 { " / " + p.ability2 } else { "" }) +
  (if p.dream_ability.length() > 0 {
    " (HA: " + p.dream_ability + ")"
  } else {
    ""
  }) +
  (if p.forms.length() > 0 { "\nForms: " + forms_joined(p.forms) } else { "" })
}

///|
/// Output a Pokemon query result.
pub fn format_pokemon(p : @model.Pokemon, fmt : OutputFormat) -> String {
  match fmt {
    Json => pokemon_to_json(p)
    Table => pokemon_to_table(p)
  }
}
