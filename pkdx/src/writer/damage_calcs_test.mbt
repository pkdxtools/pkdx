///|
fn mk_pokemon_for_test(name : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1: "",
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
    weight: 0.0,
  }
}

///|
fn mk_move_for_test(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
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
  }
}

///|
fn mk_input_for_test(
  attacker : @model.Pokemon,
  defender : @model.Pokemon,
  move_ : @model.Move,
  atk_rank : Int,
  def_rank : Int,
  critical : Bool,
) -> @model.DamageCalcInput {
  {
    attacker,
    defender,
    move_,
    atk_ability: "",
    def_ability: "",
    atk_item: "",
    def_item: "",
    weather: @model.Weather::None,
    field: @model.Field::None,
    tera_type: "",
    critical,
    atk_nature: None,
    def_nature: None,
    atk_stat_override: 0,
    def_stat_override: 0,
    def_hp_override: 0,
    atk_rank,
    def_rank,
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
  }
}

///|
fn mk_result_for_test(
  ko_text : String,
  min_pct : Double,
  max_pct : Double,
) -> @model.DamageCalcResult {
  let damages : FixedArray[Int] = FixedArray::make(16, 100)
  let percents : FixedArray[Double] = FixedArray::make(16, 50.0)
  for i = 0; i < 16; i = i + 1 {
    let pct = min_pct + (max_pct - min_pct) * i.to_double() / 15.0
    percents[i] = pct
  }
  {
    damages,
    percents,
    min_damage: 100,
    max_damage: 120,
    min_percent: min_pct,
    max_percent: max_pct,
    ko_text,
    defender_hp: 175,
    is_immune: false,
    disguise_blocked: false,
    hits_dealt: 1,
  }
}

///|
test "append_damage_calc: creates array when missing" {
  let meta : Json = { "members": [] }
  let entry : Json = { "title": "sample" }
  let result = append_damage_calc(meta, entry)
  guard result is Object(r) else { fail("expected object") }
  guard r.get("damage_calcs") is Some(Array(arr)) else {
    fail("expected damage_calcs array")
  }
  inspect(arr.length(), content="1")
}

///|
test "append_damage_calc: appends to existing array" {
  let meta : Json = {
    "members": [],
    "damage_calcs": [{ "title": "first" }, { "title": "second" }],
  }
  let entry : Json = { "title": "third" }
  let result = append_damage_calc(meta, entry)
  guard result is Object(r) else { fail("expected object") }
  guard r.get("damage_calcs") is Some(Array(arr)) else {
    fail("expected damage_calcs array")
  }
  inspect(arr.length(), content="3")
}

///|
test "append_damage_calc: preserves other keys" {
  let meta : Json = { "battle_format": "singles", "members": [1, 2, 3] }
  let entry : Json = { "title": "probe" }
  let result = append_damage_calc(meta, entry)
  guard result is Object(r) else { fail("expected object") }
  inspect(r.get("battle_format") is Some(String("singles")), content="true")
  guard r.get("members") is Some(Array(m)) else { fail("members lost") }
  inspect(m.length(), content="3")
}

///|
test "append_damage_calc: non-object top-level returns as-is" {
  let meta : Json = [1, 2, 3]
  let entry : Json = { "title": "x" }
  let result = append_damage_calc(meta, entry)
  guard result is Array(arr) else { fail("expected array pass-through") }
  inspect(arr.length(), content="3")
}

///|
test "build_damage_calc_entry: physical move populates atk rank key" {
  let atk = mk_pokemon_for_test("\u{30AC}\u{30D6}\u{30EA}\u{30A2}\u{30B9}") // ガブリアス
  let def = mk_pokemon_for_test("\u{30B5}\u{30FC}\u{30D5}\u{30B4}\u{30FC}") // サーフゴー
  let move_ = mk_move_for_test(
    "\u{3058}\u{3057}\u{3093}", // じしん
    "\u{3058}\u{3081}\u{3093}", // じめん
    Physical,
    100,
  )
  let input = mk_input_for_test(atk, def, move_, 2, 0, false)
  let result = mk_result_for_test("\u{78BA}\u{5B9A}2\u{767A}", 52.0, 61.7)
  let entry = build_damage_calc_entry(input, result, "1:1 short", "")
  guard entry is Object(e) else { fail("entry must be object") }
  guard e.get("guaranteed_hits") is Some(Number(n, ..)) else {
    fail("guaranteed_hits missing for kakutei 2")
  }
  inspect(n.to_int(), content="2")
  guard e.get("attacker") is Some(Object(a)) else { fail("attacker missing") }
  guard a.get("ranks") is Some(Object(rm)) else { fail("ranks missing") }
  inspect(rm.get("atk") is Some(Number(_)), content="true")
  inspect(rm.get("spa"), content="None")
  guard e.get("move") is Some(Object(m)) else { fail("move missing") }
  inspect(
    m.get("category") is Some(String("\u{7269}\u{7406}")),
    content="true",
  )
}

///|
test "build_damage_calc_entry: ransuu omits guaranteed_hits" {
  let atk = mk_pokemon_for_test("atk")
  let def = mk_pokemon_for_test("def")
  let move_ = mk_move_for_test("mv", "fire", Special, 80)
  let input = mk_input_for_test(atk, def, move_, 0, 0, false)
  let result = mk_result_for_test(
    "\u{4E71}\u{6570}1\u{767A}(12/16)",
    87.0,
    102.0,
  )
  let entry = build_damage_calc_entry(input, result, "", "")
  guard entry is Object(e) else { fail("entry must be object") }
  inspect(e.get("guaranteed_hits"), content="None")
  // Special は spa ranks key を使う (= 0 なのでランクは空だが key 選択だけ確認)
  guard e.get("attacker") is Some(Object(a)) else { fail("attacker missing") }
  guard a.get("ranks") is Some(Object(rm)) else { fail("ranks missing") }
  inspect(rm.is_empty(), content="true")
  // 空 optional は key ごと省略する (FE schema の z.string().optional() 準拠)。
  inspect(e.get("title"), content="None")
  inspect(e.get("note"), content="None")
  guard e.get("attacker") is Some(Object(att)) else { fail("attacker missing") }
  inspect(att.get("ability"), content="None")
  inspect(att.get("item"), content="None")
  inspect(att.get("nature"), content="None")
  inspect(att.get("tera_type"), content="None")
  guard e.get("defender") is Some(Object(defn)) else { fail("defender missing") }
  inspect(defn.get("tera_type"), content="None")
}

///|
test "build_damage_calc_entry: 16 rolls populated" {
  let atk = mk_pokemon_for_test("a")
  let def = mk_pokemon_for_test("b")
  let move_ = mk_move_for_test("m", "normal", Physical, 60)
  let input = mk_input_for_test(atk, def, move_, 0, 0, false)
  let result = mk_result_for_test("\u{78BA}\u{5B9A}3\u{767A}", 34.0, 40.0)
  let entry = build_damage_calc_entry(input, result, "t", "n")
  guard entry is Object(e) else { fail("entry must be object") }
  guard e.get("rolls_percent") is Some(Array(rolls)) else {
    fail("rolls_percent missing")
  }
  inspect(rolls.length(), content="16")
}

///|
test "validate_attach_team_path: accepts canonical path" {
  inspect(
    validate_attach_team_path("box/teams/garchomp-build-2026-04-20.meta.json"),
    content="Ok(())",
  )
  inspect(
    validate_attach_team_path("./box/teams/x.meta.json"),
    content="Ok(())",
  )
}

///|
test "validate_attach_team_path: rejects traversal" {
  guard validate_attach_team_path("box/teams/../etc/passwd.meta.json") is Err(_) else {
    fail("traversal via .. must be rejected")
  }
  guard validate_attach_team_path("box/teams/sub/../../.ssh/id.meta.json") is Err(_) else {
    fail("nested traversal must be rejected")
  }
}

///|
test "validate_attach_team_path: rejects absolute / home" {
  guard validate_attach_team_path("/etc/passwd") is Err(_) else {
    fail("absolute path must be rejected")
  }
  guard validate_attach_team_path("~/box/teams/x.meta.json") is Err(_) else {
    fail("~ expansion must be rejected")
  }
}

///|
test "validate_attach_team_path: rejects outside box/teams" {
  guard validate_attach_team_path("box/pokemons/x.meta.json") is Err(_) else {
    fail("outside box/teams must be rejected")
  }
  guard validate_attach_team_path("other/teams/x.meta.json") is Err(_) else {
    fail("non-box root must be rejected")
  }
}

///|
test "validate_attach_team_path: rejects wrong suffix" {
  guard validate_attach_team_path("box/teams/x.json") is Err(_) else {
    fail(".json without .meta must be rejected")
  }
  guard validate_attach_team_path("box/teams/x.md") is Err(_) else {
    fail(".md must be rejected")
  }
  guard validate_attach_team_path("") is Err(_) else {
    fail("empty must be rejected")
  }
}

///|
test "build_damage_calc_entry: conditions propagated" {
  let atk = mk_pokemon_for_test("a")
  let def = mk_pokemon_for_test("b")
  let move_ = mk_move_for_test("m", "water", Special, 90)
  let input : @model.DamageCalcInput = {
    ..mk_input_for_test(atk, def, move_, 0, 0, true),
    weather: @model.Weather::Rain,
    field: @model.Field::Grassy,
  }
  let result = mk_result_for_test("\u{78BA}\u{5B9A}1\u{767A}", 101.0, 119.0)
  let entry = build_damage_calc_entry(input, result, "rain crit", "")
  guard entry is Object(e) else { fail("entry must be object") }
  guard e.get("conditions") is Some(Object(c)) else { fail("conditions") }
  inspect(c.get("weather") is Some(String("\u{3042}\u{3081}")), content="true")
  inspect(
    c.get("field") is Some(String("\u{30B0}\u{30E9}\u{30B9}")),
    content="true",
  )
  inspect(c.get("crit") is Some(True), content="true")
  guard e.get("guaranteed_hits") is Some(Number(n, ..)) else {
    fail("guaranteed_hits missing")
  }
  inspect(n.to_int(), content="1")
}
