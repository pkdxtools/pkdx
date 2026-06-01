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
  let sys = if is_champions { ",\"stat_system\":\"champions\"" } else { "" }
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
