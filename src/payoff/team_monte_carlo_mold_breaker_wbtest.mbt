///|
/// MC のかたやぶり。ダメージは `build_input_with_ranks`、状態とランクと
/// ばけのかわは team MC の技解決が DP と同じ条件で特性を外す。

///|
fn mbmc_quake() -> @model.Move {
  mk_move("じしん", "じめん", @model.Physical, 100)
}

///|
fn mbmc_holder(ability : String, type1 : String) -> Combatant {
  pl_cmb(mk_pokemon("MbmcOpp", type1, "", 200, 80, 80, 80, 80, 40), [mk_move("はねる", "ノーマル", @model.Status, 0)], ability=ability)
}

///|
fn mbmc_attacker(mv : @model.Move, ability : String) -> Combatant {
  pl_cmb(mk_pokemon("MbmcOwn", "ノーマル", "", 200, 100, 80, 100, 80, 80), [mv], ability=ability)
}

///|
test "MC: ふゆうはじしんを無効にし、かたやぶりは通す" {
  let mv = mbmc_quake()
  let opp = mbmc_holder("ふゆう", "ノーマル")
  let (_, _, _, immune) = team_perform_attack(
    mbmc_attacker(mv, ""),
    opp,
    200,
    mv,
    seeded_rng(3UL),
    [0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0],
  )
  assert_true(immune)
  let (hp, _, _, broken_immune) = team_perform_attack(
    mbmc_attacker(mv, "かたやぶり"),
    opp,
    200,
    mv,
    seeded_rng(3UL),
    [0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0],
  )
  assert_true(!broken_immune)
  assert_true(hp < 200)
}

///|
test "MC: クリアボディはなきごえを止め、かたやぶりは A-1 にする" {
  let mv = mk_move("なきごえ", "ノーマル", @model.Status, 0, stat_effects=[
    @model.StatEffect::{ stat: 0, delta: -1, target: 1 },
  ])
  fn ranks_after(ability : String) -> Int {
    let opp_ranks = [0, 0, 0, 0, 0]
    team_apply_post_hit(
      [200],
      0,
      [0, 0, 0, 0, 0],
      [false],
      [@model.None],
      [-1],
      [mbmc_attacker(mv, ability)],
      [200],
      0,
      opp_ranks,
      [false],
      [mbmc_holder("クリアボディ", "ノーマル")],
      [false],
      [@model.Weather::None],
      [0],
      [@model.Field::None],
      [0],
      mv,
      0,
    )
    opp_ranks[0]
  }
  @debug.assert_eq(ranks_after(""), 0)
  @debug.assert_eq(ranks_after("かたやぶり"), -1)
}

///|
test "MC: じゅうなんのでんじはをかたやぶりは付与する" {
  let mv = mk_move(
    "でんじは",
    "でんき",
    @model.Status,
    0,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
  let opp = mbmc_holder("じゅうなん", "ノーマル")
  let blocked = [@model.StatusCondition::None]
  mc_try_apply_status(
    seeded_rng(1UL), mv, [opp], [200], blocked, 0,
  )
  @debug.assert_eq(blocked[0], @model.StatusCondition::None)
  let broken = [@model.StatusCondition::None]
  mc_try_apply_status(
    seeded_rng(1UL),
    mv,
    [opp],
    [200],
    broken,
    0,
    attacker_ability="かたやぶり",
  )
  @debug.assert_eq(broken[0], @model.Paralyze)
}

///|
test "MC: ぼうじんはねむりごなを止め、かたやぶりは止めない" {
  let mv = mk_move(
    "ねむりごな",
    "くさ",
    @model.Status,
    0,
    status_effect=Some((@model.SleepKind, 100)),
  )
  let opp = mbmc_holder("ぼうじん", "ノーマル")
  assert_true(
    mc_status_fail_before_hit(
      mv, None, mbmc_attacker(mv, ""), 200, opp, 200, @model.Field::None, @model.Weather::None, "",
    ),
  )
  assert_true(
    !mc_status_fail_before_hit(
      mv,
      None,
      mbmc_attacker(mv, "かたやぶり"),
      200,
      opp,
      200,
      @model.Field::None,
      @model.Weather::None,
      "",
    ),
  )
}

///|
test "MC: ばけのかわはかたやぶりで割れず、ダメージが通る" {
  let mv = mbmc_quake()
  let opp = mbmc_holder("ばけのかわ", "ノーマル")
  let chip = effective_hp(opp) / 8
  let intact = disguise_intact_mc([opp], 0, [false])
  assert_true(intact)
  let (hp, _, bust, immune) = team_perform_attack(
    mbmc_attacker(mv, ""),
    opp,
    200,
    mv,
    seeded_rng(4UL),
    [0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0],
    def_disguise_intact=intact,
  )
  assert_true(!immune)
  assert_true(bust)
  @debug.assert_eq(hp, 200 - chip)
  let broken_intact = disguise_intact_mc(
    [opp], 0, [false], attacker_ability="かたやぶり",
  )
  assert_true(!broken_intact)
  let (broken_hp, _, broken_bust, broken_immune) = team_perform_attack(
    mbmc_attacker(mv, "かたやぶり"),
    opp,
    200,
    mv,
    seeded_rng(4UL),
    [0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0],
    def_disguise_intact=broken_intact,
  )
  assert_true(!broken_immune)
  assert_true(!broken_bust)
  assert_true(broken_hp < 200 - chip)
}
