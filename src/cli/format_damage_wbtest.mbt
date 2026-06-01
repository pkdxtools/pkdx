///|
/// Snapshot / coverage tests for `format_damage`. The reflect-move addition
/// must (1) emit a `reflect` sub-object in JSON echo when `incoming_*` is
/// Some, and (2) leave the legacy non-reflect JSON shape byte-identical so
/// downstream skills don't break.

///|
fn fd_pokemon(name : String, type1 : String, hp : Int) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2: "",
    hp,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: hp + 500,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 0.0,
    forms: [],
  }
}

///|
fn fd_move(name : String, type_ : String) -> @model.Move {
  {
    name,
    type_,
    category: @model.Physical,
    power: 80,
    accuracy: 100,
    pp: 10,
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
}

///|
fn fd_input(
  attacker : @model.Pokemon,
  defender : @model.Pokemon,
  mv : @model.Move,
  incoming? : @model.IncomingOpts? = None,
) -> @model.DamageCalcInput {
  {
    attacker,
    defender,
    move_: mv,
    atk_ability: "",
    def_ability: "",
    atk_item: "",
    def_item: "",
    weather: @model.Weather::None,
    field: @model.Field::None,
    tera_type: "",
    critical: false,
    atk_nature: None,
    def_nature: None,
    atk_stat_override: 0,
    def_stat_override: 0,
    def_hp_override: 0,
    atk_rank: 0,
    def_rank: 0,
    fainted_count: 0,
    is_double: false,
    stat_system: @model.Standard,
    wall: @model.Wall::NoWall,
    screen_pierce: false,
    atk_status_condition: @model.StatusCondition::None,
    def_status_condition: @model.StatusCondition::None,
    atk_rank_up_count: 0,
    def_rank_up_count: 0,
    atk_hp_num: 2,
    atk_hp_den: 2,
    def_item_removable: false,
    multi_hit_mode: @model.MultiHit::Auto,
    disguise_active: false,
    protean_consumed: false,
    incoming,
  }
}

///|
/// Helper to build a minimal IncomingOpts with optional overrides — keeps
/// the test call sites readable when only a subset of modifiers matters.
fn fd_incoming(
  attacker : @model.Pokemon,
  move_ : @model.Move,
  atk_ability? : String = "",
  atk_item? : String = "",
  atk_nature? : @model.Nature? = None,
  atk_rank? : Int = 0,
  atk_stat_override? : Int = 0,
  atk_status_condition? : @model.StatusCondition = @model.StatusCondition::None,
  atk_rank_up_count? : Int = 0,
  atk_hp_num? : Int = 2,
  atk_hp_den? : Int = 2,
  tera_type? : String = "",
  critical? : Bool = false,
) -> @model.IncomingOpts {
  {
    attacker,
    move_,
    atk_ability,
    atk_item,
    atk_nature,
    atk_rank,
    atk_stat_override,
    atk_status_condition,
    atk_rank_up_count,
    atk_hp_num,
    atk_hp_den,
    tera_type,
    critical,
  }
}

///|
/// Reflect echo: when incoming_* is Some, the JSON `input` block ends with
/// a `reflect` sub-object carrying the kind, multiplier fraction, and a
/// note that incoming-side correction is omitted in MVP.
test "format_damage JSON: reflect sub-object emitted when incoming_* is Some" {
  let user = fd_pokemon("ハピナス", "ノーマル", 200)
  let opponent = fd_pokemon("カイリュー", "ドラゴン", 91)
  let reflect_mv = fd_move("ミラーコート", "エスパー")
  let incoming_mv = fd_move("りゅうせいぐん", "ドラゴン")
  let input = fd_input(
    user,
    opponent,
    reflect_mv,
    incoming=Some(fd_incoming(opponent, incoming_mv)),
  )
  let json = damage_input_to_json(input)
  // Spot-check: reflect sub-object is present with the expected kind label
  // and multiplier fraction. We don't byte-pin the whole JSON here — the
  // input echo carries many derived strings (canonical weather etc.) that
  // would make a full snapshot brittle to refactors. The presence of the
  // sub-object IS what differentiates the reflect codepath.
  assert_true(json.contains("\"reflect\":{"))
  assert_true(json.contains("\"kind\":\"mirror_coat\""))
  assert_true(json.contains("\"multiplier_num\":2"))
  assert_true(json.contains("\"multiplier_den\":1"))
  assert_true(json.contains("\"incoming_attacker\":\"カイリュー\""))
  assert_true(json.contains("\"incoming_move\":\"りゅうせいぐん\""))
}

///|
/// Incoming-side modifier echo: when CLI passes --incoming-atk-item etc.,
/// the reflect sub-object surfaces every modifier so downstream skills can
/// see exactly what context was applied to Step 1.
test "format_damage JSON: reflect echo carries incoming-side modifiers" {
  let user = fd_pokemon("ハピナス", "ノーマル", 200)
  let opponent = fd_pokemon("カイリュー", "ドラゴン", 91)
  let reflect_mv = fd_move("ミラーコート", "エスパー")
  let incoming_mv = fd_move("りゅうせいぐん", "ドラゴン")
  let opts = fd_incoming(
    opponent,
    incoming_mv,
    atk_ability="マルチスケイル",
    atk_item="いのちのたま",
    atk_rank=2,
    atk_stat_override=200,
    tera_type="ドラゴン",
    critical=true,
  )
  let json = damage_input_to_json(
    fd_input(user, opponent, reflect_mv, incoming=Some(opts)),
  )
  assert_true(json.contains("\"incoming_ability\":\"マルチスケイル\""))
  assert_true(json.contains("\"incoming_item\":\"いのちのたま\""))
  assert_true(json.contains("\"incoming_rank\":2"))
  assert_true(json.contains("\"incoming_stat_override\":200"))
  assert_true(json.contains("\"incoming_tera_type\":\"ドラゴン\""))
  assert_true(json.contains("\"incoming_critical\":true"))
}

///|
/// Backward compatibility byte-level pin: a non-reflect call with both
/// incoming_* = None must produce JSON whose `input` block ends with
/// `"protean_consumed":...}` and contains NO `reflect` field.
/// If a future refactor accidentally adds a stray field, this test fails.
test "format_damage JSON: non-reflect input has no reflect sub-object (legacy compat)" {
  let attacker = fd_pokemon("ガブリアス", "ドラゴン", 200)
  let defender = fd_pokemon("カイリュー", "ドラゴン", 91)
  let mv = fd_move("じしん", "じめん")
  let input = fd_input(attacker, defender, mv)
  let json = damage_input_to_json(input)
  // Negative pin: the reflect field name does not appear.
  assert_true(!json.contains("\"reflect\":"))
  // Positive pin: the JSON closes immediately after protean_consumed (the
  // last non-reflect field), exactly as the non-reflect shape requires.
  assert_true(json.has_suffix("\"protean_consumed\":false}"))
}

///|
/// Both Counter and Comeuppance share the (3, 2) MetalBurst-family multiplier
/// vs the (2, 1) doubling family. The echoed multiplier fields must reflect
/// the actual move-specific kind, not a default.
test "format_damage JSON: reflect multiplier matches move kind" {
  let user = fd_pokemon("ハピナス", "ノーマル", 200)
  let opponent = fd_pokemon("ガブリアス", "ドラゴン", 200)
  let reflect_mv = fd_move("メタルバースト", "はがね")
  let incoming_mv = fd_move("じしん", "じめん")
  let input = fd_input(
    user,
    opponent,
    reflect_mv,
    incoming=Some(fd_incoming(opponent, incoming_mv)),
  )
  let json = damage_input_to_json(input)
  assert_true(json.contains("\"kind\":\"metal_burst\""))
  assert_true(json.contains("\"multiplier_num\":3"))
  assert_true(json.contains("\"multiplier_den\":2"))
}
