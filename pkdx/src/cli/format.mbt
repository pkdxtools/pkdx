/// Format a Pokemon as JSON.
fn pokemon_to_json(p : @model.Pokemon) -> String {
  let t2 = if p.type2.length() > 0 {
    "\"" + p.type2 + "\""
  } else {
    "null"
  }
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
  "{\"globalNo\":\"" + p.global_no + "\",\"name_ja\":\"" + p.name_ja +
  "\",\"name_en\":\"" + p.name_en + "\",\"type1\":\"" + p.type1 + "\",\"type2\":" +
  t2 + ",\"hp\":" + p.hp.to_string() + ",\"atk\":" + p.atk.to_string() + ",\"def\":" +
  p.def_.to_string() + ",\"spa\":" + p.spa.to_string() + ",\"spd\":" + p.spd.to_string() +
  ",\"spe\":" + p.spe.to_string() + ",\"bst\":" + p.bst.to_string() +
  ",\"ability1\":\"" + p.ability1 + "\",\"ability2\":" + a2 + ",\"dream_ability\":" +
  da + "}"
}

/// Format a Pokemon as a table row.
fn pokemon_to_table(p : @model.Pokemon) -> String {
  let type_str = if p.type2.length() > 0 {
    p.type1 + "/" + p.type2
  } else {
    p.type1
  }
  p.name_ja + " (" + p.name_en + ")  No." + p.global_no + "\n" + "Type: " +
  type_str + "\n" + "HP:" + pad_right(p.hp.to_string(), 4) + " Atk:" +
  pad_right(p.atk.to_string(), 4) + " Def:" + pad_right(p.def_.to_string(), 4) +
  " SpA:" + pad_right(p.spa.to_string(), 4) + " SpD:" +
  pad_right(p.spd.to_string(), 4) + " Spe:" + pad_right(p.spe.to_string(), 4) +
  " BST:" + p.bst.to_string() + "\n" + "Abilities: " + p.ability1 +
  (if p.ability2.length() > 0 { " / " + p.ability2 } else { "" }) +
  (if p.dream_ability.length() > 0 {
    " (HA: " + p.dream_ability + ")"
  } else {
    ""
  })
}

/// Output a Pokemon query result.
pub fn format_pokemon(p : @model.Pokemon, fmt : OutputFormat) -> String {
  match fmt {
    Json => pokemon_to_json(p)
    Table => pokemon_to_table(p)
  }
}

/// Format moves as JSON array.
fn moves_to_json(moves : Array[@model.Move]) -> String {
  let mut s = "["
  for i = 0; i < moves.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    let m = moves[i]
    s = s + "{\"name\":\"" + m.name + "\",\"type\":\"" + m.type_ + "\",\"category\":\"" +
      m.category + "\",\"power\":" + m.power.to_string() + ",\"accuracy\":" +
      m.accuracy.to_string() + ",\"pp\":" + m.pp.to_string() + ",\"learn_method\":\"" +
      m.learn_method + "\"}"
  }
  s + "]"
}

/// Format moves as a table.
fn moves_to_table(moves : Array[@model.Move]) -> String {
  let mut s = pad_right("Move", 16) + pad_right("Type", 10) + pad_right(
      "Cat", 6,
    ) + pad_right("Pow", 5) + pad_right("Acc", 5) + pad_right("PP", 4) + "Method\n"
  s = s + "─".to_string().repeat(60) + "\n"
  for i = 0; i < moves.length(); i = i + 1 {
    let m = moves[i]
    s = s + pad_right(m.name, 16) + pad_right(m.type_, 10) + pad_right(
        m.category, 6,
      ) + pad_right(m.power.to_string(), 5) + pad_right(m.accuracy.to_string(), 5) +
      pad_right(m.pp.to_string(), 4) + m.learn_method + "\n"
  }
  s
}

/// Output move list.
pub fn format_moves(moves : Array[@model.Move], fmt : OutputFormat) -> String {
  match fmt {
    Json => moves_to_json(moves)
    Table => moves_to_table(moves)
  }
}

/// Format search results as JSON.
fn search_to_json(results : Array[@db.SearchResult]) -> String {
  let mut s = "["
  for i = 0; i < results.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    let r = results[i]
    let t2 = if r.type2.length() > 0 {
      "\"" + r.type2 + "\""
    } else {
      "null"
    }
    s = s + "{\"globalNo\":\"" + r.global_no + "\",\"name_ja\":\"" + r.name_ja +
      "\",\"type1\":\"" + r.type1 + "\",\"type2\":" + t2 + ",\"hp\":" +
      r.hp.to_string() + ",\"atk\":" + r.atk.to_string() + ",\"def\":" +
      r.def_.to_string() + ",\"spa\":" + r.spa.to_string() + ",\"spd\":" +
      r.spd.to_string() + ",\"spe\":" + r.spe.to_string() + ",\"bst\":" +
      r.bst.to_string() + "}"
  }
  s + "]"
}

/// Format search results as a table.
fn search_to_table(results : Array[@db.SearchResult]) -> String {
  let mut s = pad_right("Name", 14) + pad_right("Type", 14) + pad_right(
      "HP", 5,
    ) + pad_right("Atk", 5) + pad_right("Def", 5) + pad_right("SpA", 5) +
    pad_right("SpD", 5) + pad_right("Spe", 5) + "BST\n"
  s = s + "─".to_string().repeat(62) + "\n"
  for i = 0; i < results.length(); i = i + 1 {
    let r = results[i]
    let type_str = if r.type2.length() > 0 {
      r.type1 + "/" + r.type2
    } else {
      r.type1
    }
    s = s + pad_right(r.name_ja, 14) + pad_right(type_str, 14) + pad_right(
        r.hp.to_string(), 5,
      ) + pad_right(r.atk.to_string(), 5) + pad_right(r.def_.to_string(), 5) +
      pad_right(r.spa.to_string(), 5) + pad_right(r.spd.to_string(), 5) +
      pad_right(r.spe.to_string(), 5) + r.bst.to_string() + "\n"
  }
  s
}

/// Output search results.
pub fn format_search(
  results : Array[@db.SearchResult],
  fmt : OutputFormat
) -> String {
  match fmt {
    Json => search_to_json(results)
    Table => search_to_table(results)
  }
}

/// Print help message.
pub fn format_help() -> String {
  #|pkdx - Pokedex CLI tool
  #|
  #|Usage:
  #|  pkdx query <name> [--version V] [--format json|table]
  #|  pkdx moves <name|globalNo> [--version V] [--format json|table]
  #|  pkdx search --type <type> [--type2 <type>] [--min-speed N] [--version V]
  #|  pkdx damage <attacker> <defender> <move> [modifiers...] [--format json|table]
  #|  pkdx type-chart <move_type> <def_type1> [def_type2]
  #|  pkdx coverage <type1,type2,...>
  #|
  #|Options:
  #|  --version V       Game version (default: scarlet_violet)
  #|  --format F        Output format: json or table (default: table)
  #|  --help            Show this help message
}

/// Format damage calculation result.
pub fn format_damage(
  result : @model.DamageCalcResult,
  input : @model.DamageCalcInput,
  fmt : OutputFormat
) -> String {
  if result.is_immune {
    return "Immune (0 damage)"
  }
  match fmt {
    Json => damage_to_json(result, input)
    Table => damage_to_table(result, input)
  }
}

fn damage_to_json(
  r : @model.DamageCalcResult,
  input : @model.DamageCalcInput
) -> String {
  let mut dmg_arr = "["
  for i = 0; i < 16; i = i + 1 {
    if i > 0 {
      dmg_arr = dmg_arr + ","
    }
    dmg_arr = dmg_arr + r.damages[i].to_string()
  }
  dmg_arr = dmg_arr + "]"
  let mut pct_arr = "["
  for i = 0; i < 16; i = i + 1 {
    if i > 0 {
      pct_arr = pct_arr + ","
    }
    pct_arr = pct_arr + format_pct(r.percents[i])
  }
  pct_arr = pct_arr + "]"
  "{\"attacker\":\"" + input.attacker.name_ja + "\",\"defender\":\"" +
  input.defender.name_ja + "\",\"move\":\"" + input.move_.name + "\",\"damages\":" +
  dmg_arr + ",\"percents\":" + pct_arr + ",\"min\":" + r.min_damage.to_string() +
  ",\"max\":" + r.max_damage.to_string() + ",\"defender_hp\":" +
  r.defender_hp.to_string() + ",\"ko\":\"" + r.ko_text + "\"}"
}

fn damage_to_table(
  r : @model.DamageCalcResult,
  input : @model.DamageCalcInput
) -> String {
  let atk = input.attacker
  let dfn = input.defender
  let mv = input.move_
  let mut s = atk.name_ja + " → " + dfn.name_ja + " (" + mv.name + ")\n"
  s = s + "─".to_string().repeat(50) + "\n"
  // Damage range
  s = s + "Damage: " + r.min_damage.to_string() + " ~ " + r.max_damage.to_string() +
    " (" + format_pct(r.min_percent) + "% ~ " + format_pct(r.max_percent) + "%)\n"
  s = s + "HP: " + r.defender_hp.to_string() + "\n"
  s = s + "Result: " + r.ko_text + "\n"
  // Full table
  s = s + "\n"
  let mut labels = ""
  let mut damages_str = ""
  let mut pcts = ""
  for i = 0; i < 16; i = i + 1 {
    let sep = if i > 0 { " | " } else { "" }
    labels = labels + sep + (85 + i).to_string()
    damages_str = damages_str + sep + r.damages[i].to_string()
    pcts = pcts + sep + format_pct(r.percents[i]) + "%"
  }
  s = s + "Roll:   " + labels + "\n"
  s = s + "Damage: " + damages_str + "\n"
  s = s + "%:      " + pcts + "\n"
  s
}

fn format_pct(v : Double) -> String {
  let int_part = v.to_int()
  let frac = ((v - int_part.to_double()) * 10.0).to_int().abs()
  int_part.to_string() + "." + frac.to_string()
}

fn pad_right(s : String, width : Int) -> String {
  let len = s.length()
  if len >= width {
    return s
  }
  let mut result = s
  for i = 0; i < width - len; i = i + 1 {
    result = result + " "
  }
  result
}
