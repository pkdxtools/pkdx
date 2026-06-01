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
fn fixed_array_to_json(arr : FixedArray[Int]) -> String {
  let mut s = "["
  for i = 0; i < arr.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    s = s + arr[i].to_string()
  }
  s + "]"
}

///|
fn variant_to_json(v : @model.DamageVariant) -> String {
  let mut hits_arr = "["
  for h = 0; h < v.hits.length(); h = h + 1 {
    if h > 0 {
      hits_arr = hits_arr + ","
    }
    let step = v.hits[h]
    hits_arr = hits_arr +
      "{\"damage_per_roll\":" +
      fixed_array_to_json(step.damage_per_roll) +
      ",\"def_stage_after\":" +
      step.def_stage_after.to_string() +
      ",\"contact\":" +
      (if step.contact { "true" } else { "false" }) +
      "}"
  }
  hits_arr = hits_arr + "]"
  "{\"probability\":" +
  format_probability(v.probability) +
  ",\"hits_count\":" +
  v.hits_count.to_string() +
  ",\"hits\":" +
  hits_arr +
  ",\"total_damages\":" +
  fixed_array_to_json(v.total_damages) +
  ",\"min\":" +
  v.min.to_string() +
  ",\"max\":" +
  v.max.to_string() +
  ",\"ko\":\"" +
  v.ko_text +
  "\"}"
}

///|
/// LLM が damages/percents/ko だけを見て前提を取り違えないよう、ダメ計に渡した
/// 入力 (両側のポケモン・特性・持ち物・性格・ランク・天候・各種フラグ等) を
/// JSON output の `input` フィールドに丸ごと echo back する。実数値再計算は
/// せず、override が指定されていれば数値で、未指定 (engine デフォルト) なら 0
/// を返す — 解釈は呼び出し側 (SKILL.md) に委ねる。
fn damage_input_to_json(input : @model.DamageCalcInput) -> String {
  let mv = input.move_
  "{\"attacker\":" +
  damage_input_attacker_to_json(input) +
  ",\"defender\":" +
  damage_input_defender_to_json(input) +
  ",\"move\":{\"name\":\"" +
  mv.name +
  "\",\"type\":\"" +
  mv.type_ +
  "\",\"category\":\"" +
  @model.category_to_jp(mv.category) +
  "\",\"power\":" +
  mv.power.to_string() +
  ",\"accuracy\":" +
  mv.accuracy.to_string() +
  "}" +
  ",\"tera_type\":\"" +
  input.tera_type +
  "\",\"weather\":\"" +
  weather_to_canonical(input.weather) +
  "\",\"field\":\"" +
  field_to_canonical(input.field) +
  "\",\"critical\":" +
  bool_to_json(input.critical) +
  ",\"wall\":\"" +
  wall_to_canonical(input.wall) +
  "\",\"screen_pierce\":" +
  bool_to_json(input.screen_pierce) +
  ",\"fainted_count\":" +
  input.fainted_count.to_string() +
  ",\"is_double\":" +
  bool_to_json(input.is_double) +
  ",\"stat_system\":\"" +
  stat_system_to_canonical(input.stat_system) +
  "\",\"multi_hit_mode\":\"" +
  multi_hit_to_canonical(input.multi_hit_mode) +
  "\",\"disguise_active\":" +
  bool_to_json(input.disguise_active) +
  ",\"protean_consumed\":" +
  bool_to_json(input.protean_consumed) +
  reflect_section_or_empty(input) +
  "}"
}

///|
/// 反射技 (カウンター / ミラーコート / メタルバースト / ほうふく) のとき
/// だけ、入力 echo に `reflect` サブオブジェクトを追加する。incoming が
/// None なら空文字を返し、既存 JSON 形状を完全に維持する (後方互換性)。
fn reflect_section_or_empty(input : @model.DamageCalcInput) -> String {
  match input.incoming {
    Some(opts) => {
      let (kind_name, mult_num, mult_den) = match
        @damage.is_reflect_move(input.move_.name) {
        Some(k) => {
          let name = match k {
            @damage.Counter => "counter"
            @damage.MirrorCoat => "mirror_coat"
            @damage.MetalBurst => "metal_burst"
            @damage.Revenge => "revenge"
          }
          let (n, d) = @damage.reflect_multiplier(k)
          (name, n, d)
        }
        None => ("unknown", 1, 1)
      }
      ",\"reflect\":{\"incoming_attacker\":\"" +
      opts.attacker.name_ja +
      "\",\"incoming_move\":\"" +
      opts.move_.name +
      "\",\"kind\":\"" +
      kind_name +
      "\",\"multiplier_num\":" +
      mult_num.to_string() +
      ",\"multiplier_den\":" +
      mult_den.to_string() +
      ",\"incoming_ability\":\"" +
      opts.atk_ability +
      "\",\"incoming_item\":\"" +
      opts.atk_item +
      "\",\"incoming_nature\":\"" +
      nature_name_or_empty(opts.atk_nature) +
      "\",\"incoming_rank\":" +
      opts.atk_rank.to_string() +
      ",\"incoming_stat_override\":" +
      opts.atk_stat_override.to_string() +
      ",\"incoming_status\":\"" +
      status_to_canonical(opts.atk_status_condition) +
      "\",\"incoming_rank_up_count\":" +
      opts.atk_rank_up_count.to_string() +
      ",\"incoming_hp_num\":" +
      opts.atk_hp_num.to_string() +
      ",\"incoming_hp_den\":" +
      opts.atk_hp_den.to_string() +
      ",\"incoming_tera_type\":\"" +
      opts.tera_type +
      "\",\"incoming_critical\":" +
      bool_to_json(opts.critical) +
      "}"
    }
    None => ""
  }
}

///|
fn damage_input_attacker_to_json(input : @model.DamageCalcInput) -> String {
  let p = input.attacker
  "{\"name\":\"" +
  p.name_ja +
  "\",\"types\":" +
  types_to_json(p.type1, p.type2) +
  ",\"base_stats\":" +
  base_stats_to_json(p) +
  ",\"ability\":\"" +
  input.atk_ability +
  "\",\"item\":\"" +
  input.atk_item +
  "\",\"nature\":\"" +
  nature_name_or_empty(input.atk_nature) +
  "\",\"rank\":" +
  input.atk_rank.to_string() +
  ",\"stat_override\":" +
  input.atk_stat_override.to_string() +
  ",\"status\":\"" +
  status_to_canonical(input.atk_status_condition) +
  "\",\"rank_up_count\":" +
  input.atk_rank_up_count.to_string() +
  ",\"hp_num\":" +
  input.atk_hp_num.to_string() +
  ",\"hp_den\":" +
  input.atk_hp_den.to_string() +
  "}"
}

///|
fn damage_input_defender_to_json(input : @model.DamageCalcInput) -> String {
  let p = input.defender
  "{\"name\":\"" +
  p.name_ja +
  "\",\"types\":" +
  types_to_json(p.type1, p.type2) +
  ",\"base_stats\":" +
  base_stats_to_json(p) +
  ",\"ability\":\"" +
  input.def_ability +
  "\",\"item\":\"" +
  input.def_item +
  "\",\"nature\":\"" +
  nature_name_or_empty(input.def_nature) +
  "\",\"rank\":" +
  input.def_rank.to_string() +
  ",\"stat_override\":" +
  input.def_stat_override.to_string() +
  ",\"hp_override\":" +
  input.def_hp_override.to_string() +
  ",\"status\":\"" +
  status_to_canonical(input.def_status_condition) +
  "\",\"rank_up_count\":" +
  input.def_rank_up_count.to_string() +
  ",\"item_removable\":" +
  bool_to_json(input.def_item_removable) +
  "}"
}

///|
fn types_to_json(type1 : String, type2 : String) -> String {
  if type2.length() > 0 {
    "[\"" + type1 + "\",\"" + type2 + "\"]"
  } else {
    "[\"" + type1 + "\"]"
  }
}

///|
fn base_stats_to_json(p : @model.Pokemon) -> String {
  "{\"hp\":" +
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
  "}"
}

///|
fn nature_name_or_empty(n : @model.Nature?) -> String {
  match n {
    Some(nat) => nat.name_ja
    None => ""
  }
}

///|
fn bool_to_json(b : Bool) -> String {
  if b {
    "true"
  } else {
    "false"
  }
}

///|
/// Canonical short forms used in `input.*` echo. CLI flag side accepts both
/// English and Japanese spellings; the echoed value picks one canonical form
/// (Japanese for weather/field to match `weather_from_jp` / `field_from_jp`,
/// English for wall/status/multi_hit because they have counter-bearing
/// variants that don't translate to the JP CLI shorthand).
fn weather_to_canonical(w : @model.Weather) -> String {
  match w {
    None => "none"
    Sun => "はれ"
    Rain => "あめ"
    Sand => "すなあらし"
    Snow => "ゆき"
  }
}

///|
fn field_to_canonical(f : @model.Field) -> String {
  match f {
    None => "none"
    Electric => "エレキ"
    Grassy => "グラス"
    Psychic => "サイコ"
    Misty => "ミスト"
  }
}

///|
fn status_to_canonical(s : @model.StatusCondition) -> String {
  match s {
    None => "none"
    Paralyze => "paralyze"
    Burn => "burn"
    Poison => "poison"
    BadPoison(_) => "badpoison"
    Sleep(_) => "sleep"
    Drowsy(_) => "drowsy"
  }
}

///|
fn wall_to_canonical(w : @model.Wall) -> String {
  match w {
    NoWall => "none"
    Reflect => "reflect"
    LightScreen => "light-screen"
    AuroraVeil => "aurora-veil"
  }
}

///|
fn multi_hit_to_canonical(m : @model.MultiHit) -> String {
  match m {
    Auto => "auto"
    Fixed(n) => "fixed:" + n.to_string()
    Expected => "expected"
  }
}

///|
fn stat_system_to_canonical(s : @model.StatSystem) -> String {
  match s {
    Champions => "champions"
    Standard => "standard"
  }
}

///|
fn damage_to_json(
  r : @model.DamageCalcResult,
  input : @model.DamageCalcInput,
) -> String {
  let dmg_arr = fixed_array_to_json(r.damages)
  let mut pct_arr = "["
  for i = 0; i < 16; i = i + 1 {
    if i > 0 {
      pct_arr = pct_arr + ","
    }
    pct_arr = pct_arr + format_one_decimal(r.percents[i])
  }
  pct_arr = pct_arr + "]"
  let double_field = if input.is_double { ",\"double\":true" } else { "" }
  let mut variants_arr = "["
  for i = 0; i < r.variants.length(); i = i + 1 {
    if i > 0 {
      variants_arr = variants_arr + ","
    }
    variants_arr = variants_arr + variant_to_json(r.variants[i])
  }
  variants_arr = variants_arr + "]"
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
  ",\"hits_dealt\":" +
  r.hits_dealt.to_string() +
  ",\"ko\":\"" +
  r.ko_text +
  "\"" +
  ",\"disguise_blocked\":" +
  bool_to_json(r.disguise_blocked) +
  ",\"disguise_chip\":" +
  r.disguise_chip.to_string() +
  double_field +
  ",\"variants\":" +
  variants_arr +
  ",\"input\":" +
  damage_input_to_json(input) +
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
  let mut s = atk.name_ja +
    " → " +
    dfn.name_ja +
    " (" +
    mv.name +
    ")" +
    double_tag +
    "\n"
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
  if r.disguise_blocked {
    s = s +
      "ばけのかわ chip: " +
      r.disguise_chip.to_string() +
      " (各乱数値に加算済み)\n"
  }
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
  // Per-variant breakdown for probabilistic multi-hit moves (Random2to5,
  // Triple Axel/Kick). Single-variant results skip this section.
  if r.variants.length() > 1 {
    s = s + "\nVariants:\n"
    for vi = 0; vi < r.variants.length(); vi = vi + 1 {
      let v = r.variants[vi]
      s = s +
        "  " +
        v.hits_count.to_string() +
        " hit (p=" +
        format_probability(v.probability) +
        "): " +
        v.min.to_string() +
        " ~ " +
        v.max.to_string() +
        " | " +
        v.ko_text +
        "\n"
    }
  }
  s
}
