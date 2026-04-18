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
  "}"
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
  })
}

///|
/// Output a Pokemon query result.
pub fn format_pokemon(p : @model.Pokemon, fmt : OutputFormat) -> String {
  match fmt {
    Json => pokemon_to_json(p)
    Table => pokemon_to_table(p)
  }
}

///|
/// Format moves as JSON array. Includes `priority` and `stat_effects`
/// (payoff-layer metadata populated from `move_meta` via `query_moves`);
/// skills consuming this output can forward it to `pkdx select` without
/// a separate DB query.
fn moves_to_json(moves : Array[@model.Move]) -> String {
  let mut s = "["
  for i = 0; i < moves.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    let m = moves[i]
    let cat_str = @model.category_to_jp(m.category)
    s = s +
      "{\"name\":\"" +
      m.name +
      "\",\"type\":\"" +
      m.type_ +
      "\",\"category\":\"" +
      cat_str +
      "\",\"power\":" +
      m.power.to_string() +
      ",\"accuracy\":" +
      m.accuracy.to_string() +
      ",\"pp\":" +
      m.pp.to_string() +
      ",\"learn_method\":\"" +
      m.learn_method +
      "\",\"priority\":" +
      m.priority.to_string() +
      ",\"stat_effects\":" +
      stat_effects_to_json(m.stat_effects) +
      "}"
  }
  s + "]"
}

///|
/// Format `stat_effects` as a JSON array of 3-element tuples
/// `[[stat, delta, target], ...]`. `target` is `0` = self, `1` = opp.
/// Phase 3 contract used by `pkdx select` (which also accepts the legacy
/// 2-element form for tests / older pipelines).
fn stat_effects_to_json(effs : Array[@model.StatEffect]) -> String {
  let mut s = "["
  for i = 0; i < effs.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    let e = effs[i]
    s = s +
      "[" +
      e.stat.to_string() +
      "," +
      e.delta.to_string() +
      "," +
      e.target.to_string() +
      "]"
  }
  s + "]"
}

///|
/// Format moves as a table.
fn moves_to_table(moves : Array[@model.Move]) -> String {
  let mut s = pad_right("Move", 16) +
    pad_right("Type", 10) +
    pad_right("Cat", 6) +
    pad_right("Pow", 5) +
    pad_right("Acc", 5) +
    pad_right("PP", 4) +
    "Method\n"
  s = s + "─".to_string().repeat(60) + "\n"
  for i = 0; i < moves.length(); i = i + 1 {
    let m = moves[i]
    let cat_str = @model.category_to_jp(m.category)
    s = s +
      pad_right(m.name, 16) +
      pad_right(m.type_, 10) +
      pad_right(cat_str, 6) +
      pad_right(m.power.to_string(), 5) +
      pad_right(m.accuracy.to_string(), 5) +
      pad_right(m.pp.to_string(), 4) +
      m.learn_method +
      "\n"
  }
  s
}

///|
/// Output move list.
pub fn format_moves(moves : Array[@model.Move], fmt : OutputFormat) -> String {
  match fmt {
    Json => moves_to_json(moves)
    Table => moves_to_table(moves)
  }
}

///|
/// Format search results as JSON.
fn search_to_json(results : Array[@db.SearchResult]) -> String {
  let mut s = "["
  for i = 0; i < results.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    let r = results[i]
    let t2 = if r.type2.length() > 0 { "\"" + r.type2 + "\"" } else { "null" }
    s = s +
      "{\"globalNo\":\"" +
      r.global_no +
      "\",\"name_ja\":\"" +
      r.name_ja +
      "\",\"type1\":\"" +
      r.type1 +
      "\",\"type2\":" +
      t2 +
      ",\"hp\":" +
      r.hp.to_string() +
      ",\"atk\":" +
      r.atk.to_string() +
      ",\"def\":" +
      r.def_.to_string() +
      ",\"spa\":" +
      r.spa.to_string() +
      ",\"spd\":" +
      r.spd.to_string() +
      ",\"spe\":" +
      r.spe.to_string() +
      ",\"bst\":" +
      r.bst.to_string() +
      "}"
  }
  s + "]"
}

///|
/// Format search results as a table.
fn search_to_table(results : Array[@db.SearchResult]) -> String {
  let mut s = pad_right("Name", 14) +
    pad_right("Type", 14) +
    pad_right("HP", 5) +
    pad_right("Atk", 5) +
    pad_right("Def", 5) +
    pad_right("SpA", 5) +
    pad_right("SpD", 5) +
    pad_right("Spe", 5) +
    "BST\n"
  s = s + "─".to_string().repeat(62) + "\n"
  for i = 0; i < results.length(); i = i + 1 {
    let r = results[i]
    let type_str = if r.type2.length() > 0 {
      r.type1 + "/" + r.type2
    } else {
      r.type1
    }
    s = s +
      pad_right(r.name_ja, 14) +
      pad_right(type_str, 14) +
      pad_right(r.hp.to_string(), 5) +
      pad_right(r.atk.to_string(), 5) +
      pad_right(r.def_.to_string(), 5) +
      pad_right(r.spa.to_string(), 5) +
      pad_right(r.spd.to_string(), 5) +
      pad_right(r.spe.to_string(), 5) +
      r.bst.to_string() +
      "\n"
  }
  s
}

///|
/// Output search results.
pub fn format_search(
  results : Array[@db.SearchResult],
  fmt : OutputFormat,
) -> String {
  match fmt {
    Json => search_to_json(results)
    Table => search_to_table(results)
  }
}

///|
/// Format damage calculation result.
pub fn format_damage(
  result : @model.DamageCalcResult,
  input : @model.DamageCalcInput,
  fmt : OutputFormat,
) -> String {
  if result.is_immune {
    return "Immune (0 damage)"
  }
  match fmt {
    Json => damage_to_json(result, input)
    Table => damage_to_table(result, input)
  }
}

///|
fn damage_to_json(
  r : @model.DamageCalcResult,
  input : @model.DamageCalcInput,
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
    pct_arr = pct_arr + format_one_decimal(r.percents[i])
  }
  pct_arr = pct_arr + "]"
  let double_field = if input.is_double { ",\"double\":true" } else { "" }
  "{\"attacker\":\"" +
  input.attacker.name_ja +
  "\",\"defender\":\"" +
  input.defender.name_ja +
  "\",\"move\":\"" +
  input.move_.name +
  "\",\"damages\":" +
  dmg_arr +
  ",\"percents\":" +
  pct_arr +
  ",\"min\":" +
  r.min_damage.to_string() +
  ",\"max\":" +
  r.max_damage.to_string() +
  ",\"defender_hp\":" +
  r.defender_hp.to_string() +
  ",\"ko\":\"" +
  r.ko_text +
  "\"" +
  double_field +
  "}"
}

///|
fn damage_to_table(
  r : @model.DamageCalcResult,
  input : @model.DamageCalcInput,
) -> String {
  let atk = input.attacker
  let dfn = input.defender
  let mv = input.move_
  let double_tag = if input.is_double { " [ダブル]" } else { "" }
  let mut s = atk.name_ja + " → " + dfn.name_ja + " (" + mv.name + ")" + double_tag + "\n"
  s = s + "─".to_string().repeat(50) + "\n"
  // Damage range
  s = s +
    "Damage: " +
    r.min_damage.to_string() +
    " ~ " +
    r.max_damage.to_string() +
    " (" +
    format_one_decimal(r.min_percent) +
    "% ~ " +
    format_one_decimal(r.max_percent) +
    "%)\n"
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
    pcts = pcts + sep + format_one_decimal(r.percents[i]) + "%"
  }
  s = s + "Roll:   " + labels + "\n"
  s = s + "Damage: " + damages_str + "\n"
  s = s + "%:      " + pcts + "\n"
  s
}

///|
/// Format a double with exactly one decimal digit (no %/unit suffix).
/// Used for damage percentages and HBD scores.
fn format_one_decimal(v : Double) -> String {
  let int_part = v.to_int()
  let frac = ((v - int_part.to_double()) * 10.0).to_int().abs()
  int_part.to_string() + "." + frac.to_string()
}

///|
/// Format stat-calc result.
pub fn format_stat_calc(
  pokemon : @model.Pokemon,
  stats : FixedArray[Int],
  nature : @model.Nature,
  ivs : FixedArray[Int],
  evs : FixedArray[Int],
  fmt : OutputFormat,
  is_champions? : Bool = false,
) -> String {
  match fmt {
    Json => stat_calc_to_json(pokemon, stats, nature, ivs, evs, is_champions)
    Table => stat_calc_to_table(pokemon, stats, nature, ivs, evs, is_champions)
  }
}

///|
fn stat_calc_to_json(
  pokemon : @model.Pokemon,
  stats : FixedArray[Int],
  nature : @model.Nature,
  _ivs : FixedArray[Int],
  _evs : FixedArray[Int],
  is_champions : Bool,
) -> String {
  let sys = if is_champions {
    ",\"stat_system\":\"champions\""
  } else {
    ""
  }
  "{\"name\":\"" +
  pokemon.name_ja +
  "\",\"nature\":\"" +
  nature.name_ja +
  "\"" +
  sys +
  ",\"hp\":" +
  stats[0].to_string() +
  ",\"atk\":" +
  stats[1].to_string() +
  ",\"def\":" +
  stats[2].to_string() +
  ",\"spa\":" +
  stats[3].to_string() +
  ",\"spd\":" +
  stats[4].to_string() +
  ",\"spe\":" +
  stats[5].to_string() +
  "}"
}

///|
fn nature_label(nature : @model.Nature) -> String {
  match (nature.up, nature.down) {
    (Some(up), Some(down)) =>
      nature.name_ja +
      " (" +
      stat_index_label(up) +
      "↑ " +
      stat_index_label(down) +
      "↓)"
    _ => nature.name_ja
  }
}

///|
fn stat_index_label(s : @model.StatIndex) -> String {
  match s {
    HP => "HP"
    Atk => "Atk"
    Def => "Def"
    SpA => "SpA"
    SpD => "SpD"
    Spe => "Spe"
  }
}

///|
fn stat_calc_to_table(
  pokemon : @model.Pokemon,
  stats : FixedArray[Int],
  nature : @model.Nature,
  ivs : FixedArray[Int],
  evs : FixedArray[Int],
  is_champions : Bool,
) -> String {
  let mut s = pokemon.name_ja +
    " (" +
    pokemon.name_en +
    ") Lv50 " +
    nature_label(nature) +
    "\n"
  s = s + "─".to_string().repeat(50) + "\n"
  let labels = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
  let bases = [
    pokemon.hp, pokemon.atk, pokemon.def_, pokemon.spa, pokemon.spd,
    pokemon.spe,
  ]
  // Header
  s = s + pad_right("", 6)
  for i = 0; i < 6; i = i + 1 {
    s = s + pad_right(labels[i], 6)
  }
  s = s + "\n"
  // Base
  s = s + pad_right("Base", 6)
  for i = 0; i < 6; i = i + 1 {
    s = s + pad_right(bases[i].to_string(), 6)
  }
  s = s + "\n"
  if is_champions {
    // SP row (Champions has no IV)
    s = s + pad_right("SP", 6)
    for i = 0; i < 6; i = i + 1 {
      s = s + pad_right(evs[i].to_string(), 6)
    }
    s = s + "\n"
  } else {
    // IV
    s = s + pad_right("IV", 6)
    for i = 0; i < 6; i = i + 1 {
      s = s + pad_right(ivs[i].to_string(), 6)
    }
    s = s + "\n"
    // EV
    s = s + pad_right("EV", 6)
    for i = 0; i < 6; i = i + 1 {
      s = s + pad_right(evs[i].to_string(), 6)
    }
    s = s + "\n"
  }
  s = s + "─".to_string().repeat(50) + "\n"
  // Stat
  s = s + pad_right("Stat", 6)
  for i = 0; i < 6; i = i + 1 {
    s = s + pad_right(stats[i].to_string(), 6)
  }
  s = s + "\n"
  s
}

///|
/// Format stat-reverse single mode result.
pub fn format_stat_reverse_single(
  actual : Int,
  base : Int,
  iv : Int,
  ev : Int,
  is_hp : Bool,
  nature_mod : String,
  fmt : OutputFormat,
  is_champions? : Bool = false,
) -> String {
  match fmt {
    Json =>
      if is_champions {
        "{\"actual\":" +
        actual.to_string() +
        ",\"base\":" +
        base.to_string() +
        ",\"sp\":" +
        ev.to_string() +
        ",\"is_hp\":" +
        is_hp.to_string() +
        ",\"nature\":\"" +
        nature_mod +
        "\",\"stat_system\":\"champions\"}"
      } else {
        "{\"actual\":" +
        actual.to_string() +
        ",\"base\":" +
        base.to_string() +
        ",\"iv\":" +
        iv.to_string() +
        ",\"ev\":" +
        ev.to_string() +
        ",\"is_hp\":" +
        is_hp.to_string() +
        ",\"nature\":\"" +
        nature_mod +
        "\"}"
      }
    Table => {
      let stat_type = if is_hp { "HP" } else { "Other" }
      if is_champions {
        "Actual: " +
        actual.to_string() +
        " (" +
        stat_type +
        ", SP:" +
        ev.to_string() +
        " Nature:" +
        nature_mod +
        ")\n" +
        "Base stat: " +
        base.to_string() +
        "\n"
      } else {
        "Actual: " +
        actual.to_string() +
        " (" +
        stat_type +
        ", IV:" +
        iv.to_string() +
        " EV:" +
        ev.to_string() +
        " Nature:" +
        nature_mod +
        ")\n" +
        "Base stat: " +
        base.to_string() +
        "\n"
      }
    }
  }
}

///|
/// Format stat-reverse pokemon mode result.
pub fn format_stat_reverse_pokemon(
  pokemon : @model.Pokemon,
  actual_stats : FixedArray[Int],
  results : Array[(@model.Nature, FixedArray[Int])],
  fmt : OutputFormat,
  is_champions? : Bool = false,
) -> String {
  if results.length() == 0 {
    let label = if is_champions { "nature/SP" } else { "nature/EV" }
    return "No valid " + label + " combination found."
  }
  match fmt {
    Json =>
      stat_reverse_pokemon_to_json(pokemon, results, is_champions)
    Table =>
      stat_reverse_pokemon_to_table(
        pokemon, actual_stats, results, is_champions,
      )
  }
}

///|
fn stat_reverse_pokemon_to_json(
  _pokemon : @model.Pokemon,
  results : Array[(@model.Nature, FixedArray[Int])],
  is_champions : Bool,
) -> String {
  let key = if is_champions { "sps" } else { "evs" }
  let mut s = "["
  for i = 0; i < results.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    let (nature, vals) = results[i]
    let mut total = 0
    for j = 0; j < 6; j = j + 1 {
      total = total + vals[j]
    }
    s = s +
      "{\"nature\":\"" +
      nature.name_ja +
      "\",\"" +
      key +
      "\":[" +
      vals[0].to_string() +
      "," +
      vals[1].to_string() +
      "," +
      vals[2].to_string() +
      "," +
      vals[3].to_string() +
      "," +
      vals[4].to_string() +
      "," +
      vals[5].to_string() +
      "],\"total\":" +
      total.to_string() +
      "}"
  }
  s + "]"
}

///|
fn stat_reverse_pokemon_to_table(
  pokemon : @model.Pokemon,
  actual_stats : FixedArray[Int],
  results : Array[(@model.Nature, FixedArray[Int])],
  is_champions : Bool,
) -> String {
  let label = if is_champions { "SP" } else { "EV" }
  let mut s = pokemon.name_ja +
    "  実数値: " +
    actual_stats[0].to_string() +
    "/" +
    actual_stats[1].to_string() +
    "/" +
    actual_stats[2].to_string() +
    "/" +
    actual_stats[3].to_string() +
    "/" +
    actual_stats[4].to_string() +
    "/" +
    actual_stats[5].to_string() +
    "\n"
  s = s + "─".to_string().repeat(50) + "\n"
  for i = 0; i < results.length(); i = i + 1 {
    let (nature, vals) = results[i]
    let mut total = 0
    for j = 0; j < 6; j = j + 1 {
      total = total + vals[j]
    }
    s = s +
      "候補" +
      (i + 1).to_string() +
      ": " +
      nature_label(nature) +
      "\n"
    s = s +
      "  " +
      label +
      ": " +
      vals[0].to_string() +
      "/" +
      vals[1].to_string() +
      "/" +
      vals[2].to_string() +
      "/" +
      vals[3].to_string() +
      "/" +
      vals[4].to_string() +
      "/" +
      vals[5].to_string() +
      " (合計: " +
      total.to_string() +
      ")\n"
  }
  s
}

///|
fn hp_snap_label(snap : @model.HpSnap) -> String {
  match snap {
    NoSnap => "none"
    Leftovers => "leftovers"
    Residual => "residual"
    Sitrus => "sitrus"
    LifeOrb => "lifeorb"
  }
}

///|
/// Format hbd optimization result.
pub fn format_hbd(
  pokemon : @model.Pokemon,
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : @damage.HbdWeights,
  result : @damage.HbdResult,
  fmt : OutputFormat,
  is_champions? : Bool = false,
) -> String {
  match fmt {
    Json => hbd_to_json(pokemon, nature, snap, weights, result, is_champions)
    Table => hbd_to_table(pokemon, nature, snap, weights, result, is_champions)
  }
}

///|
fn hbd_to_json(
  pokemon : @model.Pokemon,
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : @damage.HbdWeights,
  result : @damage.HbdResult,
  is_champions : Bool,
) -> String {
  let mut cand_arr = "["
  for i = 0; i < result.candidates.length(); i = i + 1 {
    if i > 0 {
      cand_arr = cand_arr + ","
    }
    let c = result.candidates[i]
    let mut evs_arr = "["
    for j = 0; j < 6; j = j + 1 {
      if j > 0 {
        evs_arr = evs_arr + ","
      }
      evs_arr = evs_arr + c.evs[j].to_string()
    }
    evs_arr = evs_arr + "]"
    let evs_key = if is_champions { "sps" } else { "evs" }
    cand_arr = cand_arr +
      "{\"rank\":" +
      (i + 1).to_string() +
      ",\"" +
      evs_key +
      "\":" +
      evs_arr +
      ",\"stats\":{\"hp\":" +
      c.hp.to_string() +
      ",\"def\":" +
      c.def_.to_string() +
      ",\"spd\":" +
      c.spd.to_string() +
      "},\"score\":" +
      format_one_decimal(c.score) +
      "}"
  }
  cand_arr = cand_arr + "]"
  let warning_json = match result.warning {
    Some(msg) => "\"" + msg + "\""
    None => "null"
  }
  let sys = if is_champions {
    ",\"stat_system\":\"champions\""
  } else {
    ""
  }
  "{\"pokemon\":\"" +
  pokemon.name_ja +
  "\",\"nature\":\"" +
  nature.name_ja +
  "\",\"objective\":\"HBD/(s*B+p*D)\",\"weights\":{\"phys\":" +
  weights.phys.to_string() +
  ",\"spec\":" +
  weights.spec.to_string() +
  "},\"hp_snap\":\"" +
  hp_snap_label(snap) +
  "\"" +
  sys +
  ",\"warning\":" +
  warning_json +
  ",\"candidates\":" +
  cand_arr +
  "}"
}

///|
fn hbd_to_table(
  pokemon : @model.Pokemon,
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : @damage.HbdWeights,
  result : @damage.HbdResult,
  is_champions : Bool,
) -> String {
  let mut s = "=== HBD Optimization: " +
    pokemon.name_ja +
    " (" +
    nature_label(nature) +
    ") ===\n"
  s = s +
    "Objective: HBD/(s*B+p*D)  (p=" +
    weights.phys.to_string() +
    ", s=" +
    weights.spec.to_string() +
    ")\n"
  s = s + "HP Snap:   " + hp_snap_label(snap) + "\n"
  match result.warning {
    Some(msg) => s = s + "Warning:   " + msg + "\n"
    None => ()
  }
  s = s + "\n"
  if result.candidates.length() == 0 {
    return s + "(no candidates)\n"
  }
  if result.candidates.length() == 1 {
    // Single-solution detailed view
    let c = result.candidates[0]
    if is_champions {
      s = s +
        pad_right("Stat", 7) +
        pad_right("Base", 6) +
        pad_right("SP", 6) +
        "Value\n"
      s = s +
        pad_right("HP", 7) +
        pad_right(pokemon.hp.to_string(), 6) +
        pad_right(c.evs[0].to_string(), 6) +
        c.hp.to_string() +
        "\n"
      s = s +
        pad_right("Def", 7) +
        pad_right(pokemon.def_.to_string(), 6) +
        pad_right(c.evs[2].to_string(), 6) +
        c.def_.to_string() +
        "\n"
      s = s +
        pad_right("SpD", 7) +
        pad_right(pokemon.spd.to_string(), 6) +
        pad_right(c.evs[4].to_string(), 6) +
        c.spd.to_string() +
        "\n"
    } else {
      s = s +
        pad_right("Stat", 7) +
        pad_right("Base", 6) +
        pad_right("IV", 5) +
        pad_right("EV", 6) +
        "Value\n"
      s = s +
        pad_right("HP", 7) +
        pad_right(pokemon.hp.to_string(), 6) +
        pad_right("31", 5) +
        pad_right(c.evs[0].to_string(), 6) +
        c.hp.to_string() +
        "\n"
      s = s +
        pad_right("Def", 7) +
        pad_right(pokemon.def_.to_string(), 6) +
        pad_right("31", 5) +
        pad_right(c.evs[2].to_string(), 6) +
        c.def_.to_string() +
        "\n"
      s = s +
        pad_right("SpD", 7) +
        pad_right(pokemon.spd.to_string(), 6) +
        pad_right("31", 5) +
        pad_right(c.evs[4].to_string(), 6) +
        c.spd.to_string() +
        "\n"
    }
    s = s + "\nScore: " + format_one_decimal(c.score) + "\n"
    return s
  }
  // Multi-solution ranked table
  let alloc_label = if is_champions { "SP(H/B/D)" } else { "EV(H/B/D)" }
  s = s +
    pad_right("Rank", 6) +
    pad_right(alloc_label, 16) +
    pad_right("HP", 5) +
    pad_right("Def", 5) +
    pad_right("SpD", 5) +
    "Score\n"
  for i = 0; i < result.candidates.length(); i = i + 1 {
    let c = result.candidates[i]
    let ev_cell = c.evs[0].to_string() +
      "/" +
      c.evs[2].to_string() +
      "/" +
      c.evs[4].to_string()
    s = s +
      pad_right((i + 1).to_string(), 6) +
      pad_right(ev_cell, 16) +
      pad_right(c.hp.to_string(), 5) +
      pad_right(c.def_.to_string(), 5) +
      pad_right(c.spd.to_string(), 5) +
      format_one_decimal(c.score) +
      "\n"
  }
  s
}

///|
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
