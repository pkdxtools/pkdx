///|
/// もらいび状態 (champout `50e7233` `BTR_STATE_SYN_121_02`: ほのお技の威力 1.5 倍)。
/// 未発動の炎技は 1.5 倍せず、吸収した slot だけ交代まで 1.5 倍する。
/// 炎以外ともらいび以外はフラグが違っても同じダメージ。

///|
fn ff_fire() -> @model.Move {
  mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)
}

///|
fn ff_ranks() -> Array[Int] {
  [0, 0, 0, 0, 0]
}

///|
fn ff_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.5
}

///|
fn ff_mean(
  cache : DamageCache,
  atk : Combatant,
  dfn : Combatant,
  mv_idx : Int,
  lit : Bool,
) -> Int {
  mean_damage_cached(
    cache,
    true,
    0,
    ff_ranks(),
    0,
    ff_ranks(),
    mv_idx,
    [atk],
    [dfn],
    atk_flash_fire=lit,
  )
}

///|
test "もらいび: 未発動の炎技は等倍、発動後だけ 1.5、非炎はフラグに依らない" {
  let fire = ff_fire()
  let tackle = im_tackle()
  let holder = crash_mon("FF", [tackle, fire], 300, ability="もらいび")
  let plain = crash_mon("Plain", [fire], 300)
  let foe = crash_mon("Foe", [tackle], 300)
  let cache = new_damage_cache()
  let unlit = ff_mean(cache, holder, foe, 1, false)
  let lit = ff_mean(cache, holder, foe, 1, true)
  let plain_fire = ff_mean(cache, plain, foe, 0, false)
  let plain_flag = ff_mean(cache, plain, foe, 0, true)
  @debug.assert_eq(unlit, plain_fire)
  @debug.assert_eq(plain_flag, plain_fire)
  assert_true(lit > unlit)
  let tackle_off = ff_mean(cache, holder, foe, 0, false)
  let tackle_on = ff_mean(cache, holder, foe, 0, true)
  @debug.assert_eq(tackle_off, tackle_on)
  // 逆順でも L1 が混ざらない。
  let cache2 = new_damage_cache()
  @debug.assert_eq(ff_mean(cache2, holder, foe, 1, true), lit)
  @debug.assert_eq(ff_mean(cache2, holder, foe, 1, false), unlit)
}

///|
test "もらいび: 同速では先に吸収した側の後攻炎技だけ 1.5 になる" {
  let fire = ff_fire()
  let mine = crash_mon("FF", [fire], 400, spe=100, ability="もらいび")
  let foe = crash_mon("Foe", [fire], 400, type1="くさ", spe=100)
  let cache = new_damage_cache()
  let unlit = ff_mean(cache, mine, foe, 0, false)
  let lit = ff_mean(cache, mine, foe, 0, true)
  assert_true(lit > unlit)
  let outs = attempt_turn_with_cache(
    im_state(my_hps=[400], opp_hps=[400]),
    UseMove(0),
    UseMove(0),
    [mine],
    [foe],
    new_damage_cache(),
  )
  let mut expected_hp = 0.0
  let mut lo = 400
  let mut hi = 0
  for o in outs {
    @debug.assert_eq(o.1.my_hps[0], 400)
    @debug.assert_eq(flash_fire_lit(o.1.opp_flash_fire, 0), false)
    @debug.assert_eq(flash_fire_lit(o.1.my_flash_fire, 0), true)
    let hp = o.1.opp_hps[0]
    if hp < lo {
      lo = hp
    }
    if hp > hi {
      hi = hp
    }
    expected_hp = expected_hp + o.0 * hp.to_double()
  }
  assert_true(hi > lo)
  let mid = 400.0 - 0.5 * unlit.to_double() - 0.5 * lit.to_double()
  assert_true(ff_close(expected_hp, mid))
}

///|
test "もらいび: 交代で出ていく slot だけ解除し、技を撃っただけでは残る" {
  let mv = im_tackle()
  let plain = im_combatant(im_pokemon("plain"), [mv])
  let team = [plain, plain, plain]
  let switched = transition_with_cache(
    { ..im_state(), my_flash_fire: [true, false, false] },
    Switch(1),
    UseMove(0),
    team,
    team,
    new_damage_cache(),
  )
  assert_true(switched.length() > 0)
  for o in switched {
    @debug.assert_eq(o.1.my_active, 1)
    @debug.assert_eq(flash_fire_lit(o.1.my_flash_fire, 0), false)
    @debug.assert_eq(flash_fire_lit(o.1.my_flash_fire, 1), false)
  }
  let stayed = attempt_turn_with_cache(
    { ..im_state(my_hps=[250], opp_hps=[250]), my_flash_fire: [true] },
    UseMove(0),
    UseMove(0),
    [crash_mon("A", [mv], 250)],
    [crash_mon("B", [mv], 250)],
    new_damage_cache(),
  )
  for o in stayed {
    @debug.assert_eq(flash_fire_lit(o.1.my_flash_fire, 0), true)
  }
}

///|
test "もらいび: こおりのまま発動し、瀕死とにほんばれでは状態にならない" {
  let fire = ff_fire()
  let frozen = {
    ..im_state(my_hps=[200], opp_hps=[100]),
    opp_status: [@model.Freeze(2), @model.None, @model.None],
  }
  let outs = apply_damage_variants_fanout(
    frozen,
    [{ probability: 1.0, mean_damage: 80, hits_count: 1, hit_steps: [] }],
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=fire,
    attacker_team=[crash_mon("A", [fire], 200)],
    defender_team=[crash_mon("H", [im_tackle()], 200, ability="もらいび")],
    pre_dmg_defender_hp=100,
  )
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_hps[0], 100)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.Freeze(2))
  @debug.assert_eq(flash_fire_lit(outs[0].1.opp_flash_fire, 0), true)
  let fainted = apply_damage_variants_fanout(
    im_state(my_hps=[200], opp_hps=[0]),
    [{ probability: 1.0, mean_damage: 80, hits_count: 1, hit_steps: [] }],
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=fire,
    attacker_team=[crash_mon("A", [fire], 200)],
    defender_team=[crash_mon("H", [im_tackle()], 200, ability="もらいび")],
    pre_dmg_defender_hp=0,
  )
  @debug.assert_eq(fainted[0].1.opp_hps[0], 0)
  @debug.assert_eq(flash_fire_lit(fainted[0].1.opp_flash_fire, 0), false)
  let sun = {
    ..mk_move("にほんばれ", "ほのお", @model.Status, 0),
    weather_set: Some(@model.Sun),
  }
  let weather = apply_damage_variants_fanout(
    im_state(my_hps=[200], opp_hps=[100]),
    [{ probability: 1.0, mean_damage: 0, hits_count: 1, hit_steps: [] }],
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=sun,
    attacker_team=[crash_mon("A", [sun], 200)],
    defender_team=[crash_mon("H", [im_tackle()], 200, ability="もらいび")],
    pre_dmg_defender_hp=100,
  )
  @debug.assert_eq(weather[0].1.weather, @model.Sun)
  @debug.assert_eq(flash_fire_lit(weather[0].1.opp_flash_fire, 0), false)
}
