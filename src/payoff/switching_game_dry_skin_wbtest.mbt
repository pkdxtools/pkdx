///|
/// かんそうはだのターン終了。Champions `TOKUSEIINFO_SYN_087`
/// (champout `50e7233`): あめは最大 HP の 1/8 回復、にほんばれは 1/8 減少。
/// 砂チップと同じ天候 residual で、たべのこしより前。分母は `effective_hp`。
/// 特性が無い側と、雨・日照以外の天候は HP を変えない。

///|
fn ds_mon(ability : String, max_hp : Int, item? : String = "") -> Combatant {
  let base = mk_seed_combatant(ability~)
  let p = { ..base.pokemon, hp: max_hp }
  {
    ..base,
    pokemon: p,
    item,
    actual_stats: Some([max_hp, 100, 100, 100, 100, 100]),
  }
}

///|
fn ds_bench() -> Combatant {
  mk_seed_combatant()
}

///|
fn ds_apply(
  weather : @model.Weather,
  my : Combatant,
  opp : Combatant,
  my_hp : Int,
  opp_hp : Int,
) -> SwitchingGameState {
  let state = {
    ..mk_seed_state(),
    weather,
    weather_turns_left: 5,
    my_hps: [my_hp, 100],
    opp_hps: [opp_hp, 100],
  }
  apply_eot(state, [my, ds_bench()], [opp, ds_bench()])
}

///|
fn ds_near(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-12
}

///|
test "かんそうはだ: 雨は最大HPの1/8を回復し、満タンと瀕死は動かない" {
  let dry = ds_mon("かんそうはだ", 100)
  let plain = ds_mon("", 100)
  let healed = ds_apply(@model.Rain, dry, plain, 50, 50)
  // 100/8 = 12。相手は特性が違うので 50 のまま。
  @debug.assert_eq(healed.my_hps[0], 62)
  @debug.assert_eq(healed.opp_hps[0], 50)
  @debug.assert_eq(healed.my_hps[1], 100)
  @debug.assert_eq(healed.weather_turns_left, 4)
  let capped = ds_apply(@model.Rain, dry, plain, 100, 90)
  @debug.assert_eq(capped.my_hps[0], 100)
  @debug.assert_eq(capped.opp_hps[0], 90)
  let fainted = ds_apply(@model.Rain, dry, dry, 0, 0)
  @debug.assert_eq(fainted.my_hps[0], 0)
  @debug.assert_eq(fainted.opp_hps[0], 0)
}

///|
test "かんそうはだ: 日照は最大HPの1/8を減らし、瀕死は動かない" {
  let dry = ds_mon("かんそうはだ", 100)
  let plain = ds_mon("", 100)
  let burned = ds_apply(@model.Sun, dry, plain, 50, 50)
  @debug.assert_eq(burned.my_hps[0], 38)
  @debug.assert_eq(burned.opp_hps[0], 50)
  let ko = ds_apply(@model.Sun, dry, plain, 12, 40)
  @debug.assert_eq(ko.my_hps[0], 0)
  @debug.assert_eq(ko.opp_hps[0], 40)
  let fainted = ds_apply(@model.Sun, dry, plain, 0, 20)
  @debug.assert_eq(fainted.my_hps[0], 0)
  @debug.assert_eq(fainted.opp_hps[0], 20)
}

///|
test "かんそうはだ: 雨と日照以外、特性が違う側は従来のEOTのまま" {
  let dry = ds_mon("かんそうはだ", 160)
  let plain = ds_mon("", 160)
  // 砂は max/16 だけ。1/8 は足さない。160/16 = 10。
  let sand = ds_apply(@model.Sand, dry, plain, 160, 160)
  @debug.assert_eq(sand.my_hps[0], 150)
  @debug.assert_eq(sand.opp_hps[0], 150)
  let snow = ds_apply(@model.Snow, dry, plain, 80, 80)
  @debug.assert_eq(snow.my_hps[0], 80)
  @debug.assert_eq(snow.opp_hps[0], 80)
  let clear = ds_apply(@model.Weather::None, dry, plain, 80, 80)
  @debug.assert_eq(clear.my_hps[0], 80)
  @debug.assert_eq(clear.opp_hps[0], 80)
  // 雨でも特性が違う側は回復しない。
  let rain_plain = ds_apply(@model.Rain, plain, plain, 50, 50)
  @debug.assert_eq(rain_plain.my_hps[0], 50)
  @debug.assert_eq(rain_plain.opp_hps[0], 50)
  let sun_plain = ds_apply(@model.Sun, plain, plain, 50, 50)
  @debug.assert_eq(sun_plain.my_hps[0], 50)
  @debug.assert_eq(sun_plain.opp_hps[0], 50)
  // 最大 HP が 8 未満なら 1/8 は 0。下限 1 は掛けない。
  let tiny = ds_mon("かんそうはだ", 7)
  let tiny_rain = ds_apply(@model.Rain, tiny, plain, 5, 5)
  @debug.assert_eq(tiny_rain.my_hps[0], 5)
  let tiny_sun = ds_apply(@model.Sun, tiny, plain, 5, 5)
  @debug.assert_eq(tiny_sun.my_hps[0], 5)
}

///|
test "かんそうはだ: 日照ダメージはたべのこしより前" {
  let dry = ds_mon("かんそうはだ", 160, item="たべのこし")
  let plain = ds_mon("", 160, item="たべのこし")
  // 155 - 20 = 135、その後 +10 = 145。たべのこしが先なら 160 - 20 = 140。
  let ordered = ds_apply(@model.Sun, dry, plain, 155, 155)
  @debug.assert_eq(ordered.my_hps[0], 145)
  // 特性が無い側はたべのこしだけ。155 + 10 = 165 → 160。
  @debug.assert_eq(ordered.opp_hps[0], 160)
  // 15 - 20 でひんし。たべのこしは瀕死では回復しない。先なら 15+10-20 = 5。
  let ko = ds_apply(@model.Sun, dry, plain, 15, 15)
  @debug.assert_eq(ko.my_hps[0], 0)
  @debug.assert_eq(ko.opp_hps[0], 25)
}

///|
test "かんそうはだ: 控えは回復せず、メガ後の実効特性で判定する" {
  let dry = ds_mon("かんそうはだ", 100)
  let plain = ds_mon("", 100)
  let mut benched = mk_seed_state()
  benched = {
    ..benched,
    weather: @model.Rain,
    weather_turns_left: 5,
    my_hps: [40, 40],
    opp_hps: [40, 40],
  }
  let sat = apply_eot(benched, [dry, dry], [plain, plain])
  @debug.assert_eq(sat.my_hps[0], 52)
  @debug.assert_eq(sat.my_hps[1], 40)
  let on_bench = { ..benched, my_active: 1 }
  let idle = apply_eot(on_bench, [dry, plain], [plain, plain])
  @debug.assert_eq(idle.my_hps[0], 40)
  @debug.assert_eq(idle.my_hps[1], 40)
  let mega_form : @model.MegaForm = {
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    type1: "ノーマル",
    type2: "",
    ability: "かんそうはだ",
    name_ja: "テストM",
  }
  let mega = { ..plain, mega_form: Some(mega_form) }
  let mut mega_state = benched
  mega_state = { ..mega_state, my_megaed: [true, false], my_hps: [50, 100] }
  let gained = apply_eot(mega_state, [mega, plain], [plain, plain])
  @debug.assert_eq(gained.my_hps[0], 62)
  let mut pre = benched
  pre = { ..pre, my_hps: [50, 100] }
  let before = apply_eot(pre, [mega, plain], [plain, plain])
  @debug.assert_eq(before.my_hps[0], 50)
}

///|
fn ds_splash(ability : String, pool : Int, realized : Int) -> Combatant {
  let base = ds_mon(ability, realized)
  let p = { ..base.pokemon, hp: pool }
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  { ..base, pokemon: p, moves: [splash] }
}

///|
test "かんそうはだ: はねる1ターンの日照はDPとMCで最大HPの1/8減る" {
  let own = [ds_splash("かんそうはだ", 100, 100)]
  let opp = [ds_splash("", 100, 100)]
  let state = h1_state_from_weather_field(
    @model.Sun, @model.Field::None, own, opp,
  )
  let outs = attempt_turn_with_cache(
    state, UseMove(0), UseMove(0), own, opp, new_damage_cache(),
  )
  assert_true(outs.length() >= 1)
  let mut mass = 0.0
  for o in outs {
    mass = mass + o.0
    @debug.assert_eq(o.1.my_hps[0], 88)
    @debug.assert_eq(o.1.opp_hps[0], 100)
  }
  assert_true(ds_near(mass, 1.0))
  let mc = team_monte_carlo_value(
    own, opp, 1, 1UL, turn_limit=1, weather=@model.Sun,
  )
  let expect = (88.0 / 100.0 - 1.0) / 2.0
  assert_true(ds_near(mc, expect))
  let plain = [ds_splash("", 100, 100)]
  let mc_plain = team_monte_carlo_value(
    plain, opp, 1, 1UL, turn_limit=1, weather=@model.Sun,
  )
  assert_true(ds_near(mc_plain, 0.0))
}

///|
test "かんそうはだ: MCの雨回復は特性がある側だけ" {
  // 初期 HP は pokemon.hp、回復分母は effective_hp。プール 50 に対し
  // 実数 160 なら 160/8 = 20 回復して 70 になり、満タン開始でも観測できる。
  let own = [ds_splash("かんそうはだ", 50, 160)]
  let opp = [ds_splash("", 160, 160)]
  let mc = team_monte_carlo_value(
    own, opp, 1, 3UL, turn_limit=1, weather=@model.Rain,
  )
  let expect = (70.0 / 50.0 - 1.0) / 2.0
  assert_true(ds_near(mc, expect))
  let plain = [ds_splash("", 50, 160)]
  let mc_plain = team_monte_carlo_value(
    plain, opp, 1, 3UL, turn_limit=1, weather=@model.Rain,
  )
  assert_true(ds_near(mc_plain, 0.0))
}
