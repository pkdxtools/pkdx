///|
/// Whitebox tests for `avg_damage`. Covers:
///   - standard mean over the 16-roll array
///   - immune matchups short-circuit to 0
///
/// payoff レイヤは build_input_with_ranks で disguise_active=false 固定なので
/// disguise_blocked 経路はそもそも発生しない。仮に立っても engine が chip を
/// total_damages に加算済みなので avg_damage は通常パスでそのまま正しい値を
/// 返す。
///
/// `avg_damage` is package-private, so the test lives next to it.

///|
fn mk_result(
  damages : FixedArray[Int],
  def_hp : Int,
  is_immune? : Bool = false,
) -> @model.DamageCalcResult {
  let percents : FixedArray[Double] = FixedArray::make(16, 0.0)
  for i = 0; i < 16; i = i + 1 {
    percents[i] = damages[i].to_double() / def_hp.to_double() * 100.0
  }
  // Synthesize a single chance-node entry so `expected_damage_variants`
  // (called by the new `avg_damage` delegate) sees the same 16-roll table.
  let single_variant : @model.DamageVariant = {
    probability: 1.0,
    hits: [],
    hits_count: 1,
    total_damages: damages,
    min: damages[0],
    max: damages[15],
    ko_text: "",
  }
  {
    damages,
    percents,
    min_damage: damages[0],
    max_damage: damages[15],
    min_percent: percents[0],
    max_percent: percents[15],
    ko_text: "",
    defender_hp: def_hp,
    is_immune,
    disguise_blocked: false,
    disguise_chip: 0,
    hits_dealt: 1,
    variants: [single_variant],
  }
}

///|
test "avg_damage: standard mean over 16 rolls" {
  // Uniform 48 damage → mean 48.
  let d : FixedArray[Int] = FixedArray::make(16, 48)
  let r = mk_result(d, 160)
  let avg = avg_damage(r)
  // Double equality on integers is safe here.
  @debug.debug_inspect(avg, content="48")
}

///|
test "avg_damage: immune matchup returns 0" {
  let d : FixedArray[Int] = FixedArray::make(16, 0)
  let r = mk_result(d, 160, is_immune=true)
  @debug.debug_inspect(avg_damage(r), content="0")
}

///|
/// Stage B (healing-moves plan): build_input_with_ranks must accept a
/// `weather~` keyword argument and thread it verbatim into the resulting
/// DamageCalcInput.weather field. Without this wiring, state.weather set
/// inside SwitchingGame cannot reach @damage.calc_damage and Sun /
/// Rain / Sand / Snow weather multipliers (and WeatherBall typing) silently
/// degrade to Weather::None.
///
/// Red→Green minimum: assert that each variant of Weather flows through.
test "build_input_with_ranks: weather~ argument threads into DamageCalcInput.weather" {
  let p : @model.Pokemon = {
    global_no: "0006",
    name_ja: "テスト",
    name_en: "Test",
    type1: "ほのお",
    type2: "",
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  let c : Combatant = {
    pokemon: p,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
  let mv : @model.Move = {
    name: "かえんほうしゃ",
    type_: "ほのお",
    category: @model.Special,
    power: 90,
    accuracy: 100,
    pp: 15,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
  }
  // Default (no weather~) must remain Weather::None so the existing 13
  // fixtures and 1078-test baseline stay green without churn.
  let input_default = build_input_with_ranks(c, c, mv, 0, 0)
  @debug.assert_eq(input_default.weather, @model.Weather::None)
  // Each Weather variant must reach DamageCalcInput.weather verbatim.
  let input_sun = build_input_with_ranks(
    c,
    c,
    mv,
    0,
    0,
    weather=@model.Weather::Sun,
  )
  @debug.assert_eq(input_sun.weather, @model.Weather::Sun)
  let input_rain = build_input_with_ranks(
    c,
    c,
    mv,
    0,
    0,
    weather=@model.Weather::Rain,
  )
  @debug.assert_eq(input_rain.weather, @model.Weather::Rain)
  let input_sand = build_input_with_ranks(
    c,
    c,
    mv,
    0,
    0,
    weather=@model.Weather::Sand,
  )
  @debug.assert_eq(input_sand.weather, @model.Weather::Sand)
  let input_snow = build_input_with_ranks(
    c,
    c,
    mv,
    0,
    0,
    weather=@model.Weather::Snow,
  )
  @debug.assert_eq(input_snow.weather, @model.Weather::Snow)
}

///|
/// Stage F-3: build_input_with_ranks must accept a `field~` keyword argument
/// and thread it verbatim into the resulting DamageCalcInput.field field.
/// Without this wiring, state.field set inside SwitchingGame cannot reach
/// @damage.calc_damage and Electric / Grassy / Misty / Psychic terrain
/// multipliers silently degrade to Field::None.
test "build_input_with_ranks: field~ argument threads into DamageCalcInput.field" {
  let p : @model.Pokemon = {
    global_no: "0006",
    name_ja: "テスト",
    name_en: "Test",
    type1: "ほのお",
    type2: "",
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  let c : Combatant = {
    pokemon: p,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
  let mv : @model.Move = {
    name: "10まんボルト",
    type_: "でんき",
    category: @model.Special,
    power: 90,
    accuracy: 100,
    pp: 15,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
  }
  // Default (no field~) must remain Field::None so existing fixtures stay
  // green without per-call churn.
  let input_default = build_input_with_ranks(c, c, mv, 0, 0)
  @debug.assert_eq(input_default.field, @model.Field::None)
  let input_electric = build_input_with_ranks(
    c,
    c,
    mv,
    0,
    0,
    field=@model.Field::Electric,
  )
  @debug.assert_eq(input_electric.field, @model.Field::Electric)
  let input_grassy = build_input_with_ranks(
    c,
    c,
    mv,
    0,
    0,
    field=@model.Field::Grassy,
  )
  @debug.assert_eq(input_grassy.field, @model.Field::Grassy)
  let input_misty = build_input_with_ranks(
    c,
    c,
    mv,
    0,
    0,
    field=@model.Field::Misty,
  )
  @debug.assert_eq(input_misty.field, @model.Field::Misty)
  let input_psychic = build_input_with_ranks(
    c,
    c,
    mv,
    0,
    0,
    field=@model.Field::Psychic,
  )
  @debug.assert_eq(input_psychic.field, @model.Field::Psychic)
}
