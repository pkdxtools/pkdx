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
