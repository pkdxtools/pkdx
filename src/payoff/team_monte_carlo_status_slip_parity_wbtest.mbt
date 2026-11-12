///|
/// やけど / どく / もうどく のターン終了ダメージ。
/// DP (`apply_eot`) と MC (`team_rollout`) は同じ `eot_slip_active` を、
/// バトルの HP プール (`status_slip_max_hp` = `pokemon.hp`) で呼ぶ。
/// `effective_hp` を分母にするとプールより大きい chip になり、瀕死の閾値で
/// 平均ダメージ (DP) と 16 乱数の 1 つ (MC) が割れる。

///|
fn slip_move(
  name : String,
  category : @model.MoveCategory,
  power : Int,
  status_effect : (@model.StatusKind, Int)?,
) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category,
    power,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
    flinch_chance: 0,
  }
}

///|
fn slip_poke(name : String, hp : Int, spe : Int) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1: "ノーマル",
    type2: "",
    hp,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe,
    bst: hp + 400 + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
}

///|
fn slip_cmb(p : @model.Pokemon, moves : Array[@model.Move]) -> Combatant {
  {
    pokemon: p,
    moves,
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
}

///|
/// `actual_stats` が無いので `effective_hp` は種族値 160 から Lv50 の投資込み
/// HP (267) を返す。プールは 160。誤った分母ならやけどは 267/16 = 16 で
/// 160 → 144 になる。プールなら 160/16 = 10 で 150。
test "apply_eot status slip uses the battle HP pool, not invested effective HP" {
  let poke = slip_poke("s", 160, 100)
  let c = slip_cmb(poke, [])
  assert_true(status_slip_max_hp(c) == 160)
  assert_true(effective_hp(c) != 160)
  let team = [c]
  let burned = apply_eot(
    mk_test_state(1, 160, 160, @model.Burn, @model.None),
    team,
    team,
  )
  @debug.assert_eq(burned.my_hps[0], 150)
  let poisoned = apply_eot(
    mk_test_state(1, 160, 160, @model.Poison, @model.None),
    team,
    team,
  )
  @debug.assert_eq(poisoned.my_hps[0], 140)
  let toxic = apply_eot(
    mk_test_state(1, 160, 160, @model.BadPoison(0), @model.None),
    team,
    team,
  )
  @debug.assert_eq(toxic.my_hps[0], 150)
  match toxic.my_status[0] {
    @model.BadPoison(n) => @debug.assert_eq(n, 1)
    _ => assert_true(false)
  }
  // 2 段目は 160 * 2 / 16 = 20。floor(160/16) * 2 = 20 と同じ。
  let toxic2 = apply_eot(
    mk_test_state(1, 150, 160, @model.BadPoison(1), @model.None),
    team,
    team,
  )
  @debug.assert_eq(toxic2.my_hps[0], 130)
  // ダメージが残り HP 以上なら 0。すでに 0 なら追加ダメージもカウンタ進行も無い。
  let faint = apply_eot(
    mk_test_state(1, 8, 160, @model.Burn, @model.None),
    team,
    team,
  )
  @debug.assert_eq(faint.my_hps[0], 0)
  let dead = apply_eot(
    mk_test_state(1, 0, 160, @model.BadPoison(2), @model.None),
    team,
    team,
  )
  @debug.assert_eq(dead.my_hps[0], 0)
  match dead.my_status[0] {
    @model.BadPoison(n) => @debug.assert_eq(n, 2)
    _ => assert_true(false)
  }
  // Champions でも分母はプール。SP 込みの effective_hp にはしない。
  let ch = { ..c, stat_system: @model.Champions }
  assert_true(effective_hp(ch) != 160)
  let ch_burn = apply_eot(
    mk_test_state(1, 160, 160, @model.Burn, @model.None),
    [ch],
    [ch],
  )
  @debug.assert_eq(ch_burn.my_hps[0], 150)
}

///|
fn slip_values(
  own_moves : Array[@model.Move],
  opp_moves : Array[@model.Move],
  hp : Int,
  trials : Int,
  seed : UInt64,
) -> (Double, Double) {
  let own = [slip_cmb(slip_poke("me", hp, 120), own_moves)]
  let opp = [slip_cmb(slip_poke("opp", hp, 60), opp_moves)]
  let dp = switching_game_winrate(own, opp, 4)
  let mc = team_monte_carlo_value(own, opp, trials, seed, turn_limit=4)
  (dp, mc)
}

///|
/// 変化技 100% はダメージ乱数が無い。4 ターン、HP 160。
/// やけど 10*4=40 → 0.125、どく 20*4=80 → 0.25、
/// もうどく 10+20+30+40=100 → 0.3125。
/// `effective_hp` 分母 (267) だと 0.2 / 0.4125 / 1.0 になり、この値と一致しない。
test "DP/MC parity: 100% burn, poison, and toxic vs Splash use the pool fraction" {
  let splash = [slip_move("はねる", @model.Status, 0, None)]
  let (dp_splash, mc_splash) = slip_values(splash, splash, 160, 32, 11UL)
  assert_true(dp_splash.abs() < 1.0e-9)
  assert_true((dp_splash - mc_splash).abs() < 1.0e-9)
  let burn = [slip_move("おにび", @model.Status, 0, Some((@model.BurnKind, 100)))]
  let (dp_burn, mc_burn) = slip_values(burn, splash, 160, 32, 11UL)
  assert_true((dp_burn - 0.125).abs() < 1.0e-9)
  assert_true((dp_burn - mc_burn).abs() < 1.0e-9)
  let poison = [
    slip_move("どくのこな", @model.Status, 0, Some((@model.PoisonKind, 100))),
  ]
  let (dp_psn, mc_psn) = slip_values(poison, splash, 160, 32, 11UL)
  assert_true((dp_psn - 0.25).abs() < 1.0e-9)
  assert_true((dp_psn - mc_psn).abs() < 1.0e-9)
  let toxic = [
    slip_move("どくどく", @model.Status, 0, Some((@model.BadPoisonKind, 100))),
  ]
  let (dp_tox, mc_tox) = slip_values(toxic, splash, 160, 32, 11UL)
  assert_true((dp_tox - 0.3125).abs() < 1.0e-9)
  assert_true((dp_tox - mc_tox).abs() < 1.0e-9)
}

///|
/// 特殊 威力 70 の乱数は 55..66。4 発の最大は 264。HP 360 なら、プール分母の
/// やけど (360/16 = 22) と どく (360/8 = 45) を足しても、DP と MC の差は
/// 0.02 未満。`effective_hp` 分母 (467) だと やけど約 0.08、どく約 0.04 で
/// しきい値を超える。HP 240 は 4*60 でちょうど瀕死、HP 260 の 30% やけどの差は
/// プール分母でも約 0.03 なので、どちらもここには置かない。
test "DP/MC parity: 30% burn and poison at HP 360 stay within 0.02" {
  let burn = [
    slip_move("とくこう", @model.Special, 70, Some((@model.BurnKind, 30))),
  ]
  let poison = [
    slip_move("とくこう", @model.Special, 70, Some((@model.PoisonKind, 30))),
  ]
  let plain = [slip_move("とくこう", @model.Special, 70, None)]
  let (dp_plain, mc_plain) = slip_values(plain, plain, 360, 8192, 7UL)
  let (dp_burn, mc_burn) = slip_values(burn, plain, 360, 8192, 7UL)
  let (dp_psn, mc_psn) = slip_values(poison, plain, 360, 8192, 7UL)
  assert_true((dp_burn - dp_plain).abs() > 0.005)
  assert_true((dp_psn - dp_plain).abs() > 0.005)
  assert_true((dp_burn - mc_burn).abs() < 0.02)
  assert_true((dp_psn - mc_psn).abs() < 0.02)
  assert_true((dp_plain - mc_plain).abs() < 0.02)
}
