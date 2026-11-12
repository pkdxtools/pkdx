///|
/// 再生力 (Regenerator) の単体・交代配線テスト。
///
/// - helper: 最大HP/3 切り捨て、上限、ひんし不発、非対象 slot 不変
/// - DP: `transition_with_cache` の 3 Switch arm と `partial_act_outcomes` の
///   2 arm。出ていく側だけ回復し、交代先は変わらない。ひんし交代は不発。
///   メガ後の実効特性で判定する。

///|
fn rg_pokemon(name : String, hp : Int) -> @model.Pokemon {
  mk_pokemon(name, "ノーマル", "", hp, 100, 100, 100, 100, 100)
}

///|
fn rg_tackle() -> @model.Move {
  mk_move("たいあたり", "ノーマル", @model.Physical, 40)
}

///|
fn rg_splash() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
fn rg_combatant(
  pokemon : @model.Pokemon,
  ability? : String = "",
  mega_form? : @model.MegaForm? = None,
) -> Combatant {
  {
    pokemon,
    moves: [rg_tackle()],
    ability,
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
}

///|
fn rg_mega(ability : String) -> @model.MegaForm {
  {
    atk: 130,
    def_: 130,
    spa: 130,
    spd: 130,
    spe: 130,
    type1: "ノーマル",
    type2: "",
    ability,
    name_ja: "メガテスト",
  }
}

///|
fn rg_state(
  my_hps : Array[Int],
  opp_hps : Array[Int],
  my_megaed? : Array[Bool] = [false, false],
) -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps,
    opp_hps,
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed,
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_disguise_busted: [false, false],
    opp_disguise_busted: [false, false],
    my_flinched: false,
    opp_flinched: false,
    my_moves_used: [0, 0],
    opp_moves_used: [0, 0],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    opp_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
fn rg_healed(cur : Int, max_hp : Int) -> Int {
  let amount = max_hp / 3
  let sum = cur + amount
  if sum > max_hp {
    max_hp
  } else {
    sum
  }
}

///|
test "再生力: 交代で最大HP/3を切り捨て回復し、他スロットは不変" {
  let hps = [10, 50]
  apply_regenerator_on_switch_out("再生力", hps, 0, 100)
  // 100/3 = 33。10 + 33 = 43。slot 1 は出ていないので不変。
  @debug.assert_eq(hps[0], 43)
  @debug.assert_eq(hps[1], 50)
}

///|
test "再生力: 端数は切り捨て (10/3=3, 2/3=0)" {
  let hps = [1]
  apply_regenerator_on_switch_out("再生力", hps, 0, 10)
  @debug.assert_eq(hps[0], 4)
  let tiny = [1]
  apply_regenerator_on_switch_out("再生力", tiny, 0, 2)
  @debug.assert_eq(tiny[0], 1)
}

///|
test "再生力: 最大HPを超えない" {
  let hps = [90]
  apply_regenerator_on_switch_out("再生力", hps, 0, 100)
  // 90 + 33 = 123 → 100
  @debug.assert_eq(hps[0], 100)
  let full = [100]
  apply_regenerator_on_switch_out("再生力", full, 0, 100)
  @debug.assert_eq(full[0], 100)
}

///|
test "再生力: ひんし (HP<=0) では不発" {
  let hps = [0, 40]
  apply_regenerator_on_switch_out("再生力", hps, 0, 100)
  @debug.assert_eq(hps[0], 0)
  @debug.assert_eq(hps[1], 40)
}

///|
test "再生力: 特性が再生力でなければ no-op" {
  let hps = [10]
  apply_regenerator_on_switch_out("", hps, 0, 100)
  @debug.assert_eq(hps[0], 10)
  apply_regenerator_on_switch_out("いかく", hps, 0, 100)
  @debug.assert_eq(hps[0], 10)
}

///|
test "再生力: 双方交代で出ていく側だけ回復し、交代先は不変" {
  let mine = rg_pokemon("Regen", 120)
  let yours = rg_pokemon("OppRegen", 90)
  let bench = rg_pokemon("Bench", 150)
  let my_team = [
    rg_combatant(mine, ability="再生力"),
    rg_combatant(bench),
  ]
  let opp_team = [
    rg_combatant(yours, ability="再生力"),
    rg_combatant(bench),
  ]
  let outs = transition_with_cache(
    rg_state([40, 77], [30, 88]),
    ActionKind::Switch(1),
    ActionKind::Switch(1),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  @debug.assert_eq(s.my_active, 1)
  @debug.assert_eq(s.opp_active, 1)
  @debug.assert_eq(s.my_hps[0], rg_healed(40, mine.hp))
  @debug.assert_eq(s.my_hps[1], 77)
  @debug.assert_eq(s.opp_hps[0], rg_healed(30, yours.hp))
  @debug.assert_eq(s.opp_hps[1], 88)
  // 120/3 = 40, 90/3 = 30。端数が出る max でも切り捨て。
  @debug.assert_eq(mine.hp / 3, 40)
  @debug.assert_eq(yours.hp / 3, 30)
}

///|
test "再生力: 片側だけ交代するとき出ていく側だけ回復する" {
  let mine = rg_pokemon("Regen", 100)
  let plain = rg_pokemon("Plain", 100)
  let my_team = [
    rg_combatant(mine, ability="再生力"),
    rg_combatant(plain),
  ]
  // 相手ははねる。交代先にも出ていく相手にもダメージを入れない。
  let opp_splash = [
    { ..rg_combatant(plain), moves: [rg_splash()] },
    rg_combatant(plain),
  ]
  let outs = transition_with_cache(
    rg_state([20, 55], [100, 100]),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_splash,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  @debug.assert_eq(s.my_hps[0], rg_healed(20, 100))
  @debug.assert_eq(s.my_hps[1], 55)
  @debug.assert_eq(s.opp_hps[0], 100)
  // 非再生力の交代は HP 不変。
  let plain_team = [rg_combatant(plain), rg_combatant(plain)]
  let outs_plain = transition_with_cache(
    rg_state([20, 55], [100, 100]),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    plain_team,
    opp_splash,
    new_damage_cache(),
  )
  let (_, sp) = outs_plain[0]
  @debug.assert_eq(sp.my_hps[0], 20)
  @debug.assert_eq(sp.my_hps[1], 55)
}

///|
test "再生力: ひんし交代では回復しない" {
  let mine = rg_pokemon("Regen", 100)
  let plain = rg_pokemon("Plain", 100)
  let my_team = [
    rg_combatant(mine, ability="再生力"),
    rg_combatant(plain),
  ]
  let opp = [
    { ..rg_combatant(plain), moves: [rg_splash()] },
    rg_combatant(plain),
  ]
  let outs = transition_with_cache(
    rg_state([0, 80], [100, 100]),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp,
    new_damage_cache(),
  )
  let (_, s) = outs[0]
  @debug.assert_eq(s.my_active, 1)
  @debug.assert_eq(s.my_hps[0], 0)
  @debug.assert_eq(s.my_hps[1], 80)
}

///|
test "再生力: すでに最大HPなら回復しない" {
  let mine = rg_pokemon("Regen", 99)
  let plain = rg_pokemon("Plain", 99)
  let my_team = [
    rg_combatant(mine, ability="再生力"),
    rg_combatant(plain),
  ]
  let opp = [
    rg_combatant(plain, ability="再生力"),
    rg_combatant(plain),
  ]
  // 99/3 = 33。満タンからの加算は上限で消える。
  let outs = transition_with_cache(
    rg_state([99, 10], [99, 10]),
    ActionKind::Switch(1),
    ActionKind::Switch(1),
    my_team,
    opp,
    new_damage_cache(),
  )
  let (_, s) = outs[0]
  @debug.assert_eq(s.my_hps[0], 99)
  @debug.assert_eq(s.my_hps[1], 10)
  @debug.assert_eq(s.opp_hps[0], 99)
  @debug.assert_eq(s.opp_hps[1], 10)
}

///|
test "再生力: partial_act の交代でも出ていく側だけ回復する" {
  let mine = rg_pokemon("Regen", 100)
  let plain = rg_pokemon("Plain", 100)
  let my_team = [
    rg_combatant(mine, ability="再生力"),
    rg_combatant(plain),
  ]
  let opp_team = [
    rg_combatant(plain, ability="再生力"),
    rg_combatant(plain),
  ]
  let state = rg_state([25, 60], [25, 60])
  let mine_outs = partial_act_outcomes(
    state,
    ActionKind::Switch(1),
    true,
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (_, sm) = mine_outs[0]
  @debug.assert_eq(sm.my_hps[0], rg_healed(25, 100))
  @debug.assert_eq(sm.my_hps[1], 60)
  @debug.assert_eq(sm.opp_hps[0], 25)
  let opp_outs = partial_act_outcomes(
    state,
    ActionKind::Switch(1),
    false,
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (_, so) = opp_outs[0]
  @debug.assert_eq(so.opp_hps[0], rg_healed(25, 100))
  @debug.assert_eq(so.opp_hps[1], 60)
  @debug.assert_eq(so.my_hps[0], 25)
}

///|
test "再生力: メガ後の実効特性で判定する" {
  let base = rg_pokemon("MegaBase", 120)
  let plain = rg_pokemon("Plain", 120)
  let gained = rg_combatant(
    base,
    ability="",
    mega_form=Some(rg_mega("再生力")),
  )
  let lost = rg_combatant(
    base,
    ability="再生力",
    mega_form=Some(rg_mega("いかく")),
  )
  let bench = rg_combatant(plain)
  let splash_opp = [
    { ..bench, moves: [rg_splash()] },
    bench,
  ]
  let healed = transition_with_cache(
    rg_state([30, 40], [120, 120], my_megaed=[true, false]),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    [gained, bench],
    splash_opp,
    new_damage_cache(),
  )
  let (_, sh) = healed[0]
  @debug.assert_eq(sh.my_hps[0], rg_healed(30, base.hp))
  let suppressed = transition_with_cache(
    rg_state([30, 40], [120, 120], my_megaed=[true, false]),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    [lost, bench],
    splash_opp,
    new_damage_cache(),
  )
  let (_, ss) = suppressed[0]
  @debug.assert_eq(ss.my_hps[0], 30)
  // メガ前は base 特性。再生力のままなら回復する。
  let pre = transition_with_cache(
    rg_state([30, 40], [120, 120], my_megaed=[false, false]),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    [lost, bench],
    splash_opp,
    new_damage_cache(),
  )
  let (_, sp) = pre[0]
  @debug.assert_eq(sp.my_hps[0], rg_healed(30, base.hp))
}
