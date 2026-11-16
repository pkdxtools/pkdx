///|
/// 吸収特性の MC 経路。DP の `with_absorb_effects` と同じく、
/// `team_apply_post_hit` がランク上昇と 1/4 回復だけを行い、
/// `mc_try_apply_status` は状態を付けず、`mc_attempt_accuracy` は命中 100 にする。

///|
fn abmc_post(
  ability : String,
  mv : @model.Move,
  defender_hp : Int,
  max_hp : Int,
) -> (Array[Int], Array[Int], Array[Int]) {
  let attacker_hps = [200]
  let defender_hps = [defender_hp]
  let defender_ranks = [0, 0, 0, 0, 0]
  let holder = crash_mon("Holder", [im_tackle()], max_hp, ability=ability)
  team_apply_post_hit(
    attacker_hps,
    0,
    [0, 0, 0, 0, 0],
    [false],
    [@model.None],
    [-1],
    [crash_mon("Atk", [mv], 200)],
    defender_hps,
    0,
    defender_ranks,
    [false],
    [holder],
    [false],
    [@model.Weather::None],
    [0],
    [@model.Field::None],
    [0],
    mv,
    60,
  )
  (attacker_hps, defender_hps, defender_ranks)
}

///|
test "MC: ちょすいはみず技で1/4回復し、反動もダメージも起こさない" {
  let surf = mk_move(
    "なみのり", "みず", @model.Special, 90, recoil_num=1, recoil_den=3,
  )
  let (atk_hp, def_hp, ranks) = abmc_post("ちょすい", surf, 100, 200)
  @debug.assert_eq(atk_hp[0], 200)
  @debug.assert_eq(def_hp[0], 150)
  @debug.assert_eq(ranks[0], 0)
}

///|
test "MC: でんきエンジンは素早さ+1だけでHPは変わらない" {
  let bolt = mk_move("１０まんボルト", "でんき", @model.Special, 90)
  let (atk_hp, def_hp, ranks) = abmc_post("でんきエンジン", bolt, 100, 200)
  @debug.assert_eq(atk_hp[0], 200)
  @debug.assert_eq(def_hp[0], 100)
  @debug.assert_eq(ranks[4], 1)
}

///|
test "MC: ひらいしんは特攻+1、もらいびはランクもHPも変えない" {
  let bolt = mk_move("１０まんボルト", "でんき", @model.Special, 90)
  let (_, _, rod) = abmc_post("ひらいしん", bolt, 100, 200)
  @debug.assert_eq(rod[2], 1)
  let fire = mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)
  let (_, ff_hp, ff_ranks) = abmc_post("もらいび", fire, 100, 200)
  @debug.assert_eq(ff_hp[0], 100)
  @debug.assert_eq(ff_ranks[2], 0)
}

///|
test "MC: 瀕死のちくでんは回復しない" {
  let bolt = mk_move("１０まんボルト", "でんき", @model.Special, 90)
  let (_, def_hp, _) = abmc_post("ちくでん", bolt, 0, 200)
  @debug.assert_eq(def_hp[0], 0)
}

///|
test "MC: 吸収されたでんじはは麻痺を付けない" {
  let wave = mk_move(
    "でんじは",
    "でんき",
    @model.Status,
    0,
    accuracy=90,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
  let rng = seeded_rng(1UL)
  let status : Array[@model.StatusCondition] = [@model.None]
  let holder = crash_mon("Volt", [im_tackle()], 200, ability="ちくでん")
  mc_try_apply_status(rng, wave, [holder], [100], status, 0)
  @debug.assert_eq(status[0], @model.None)
  let plain : Array[@model.StatusCondition] = [@model.None]
  mc_try_apply_status(
    rng, wave, [crash_mon("Plain", [im_tackle()], 200)], [100], plain, 0,
  )
  @debug.assert_eq(plain[0], @model.Paralyze)
}

///|
test "MC: 吸収の変化技は命中100、非吸収は技の命中率" {
  let wave = mk_move(
    "でんじは", "でんき", @model.Status, 0, accuracy=90,
  )
  let atk = crash_mon("Atk", [wave], 200)
  let none = @model.Weather::None
  @debug.assert_eq(
    mc_attempt_accuracy(
      atk, wave, crash_mon("Volt", [im_tackle()], 200, ability="ちくでん"), none,
    ),
    100,
  )
  @debug.assert_eq(
    mc_attempt_accuracy(atk, wave, crash_mon("Plain", [im_tackle()], 200), none),
    90,
  )
}

///|
test "MC: あまごいはちょすいに吸収されず天候を張る" {
  let rain = {
    ..mk_move("あまごい", "みず", @model.Status, 0),
    weather_set: Some(@model.Rain),
  }
  let weather = [@model.Weather::None]
  let turns = [0]
  let defender_hps = [100]
  team_apply_post_hit(
    [200],
    0,
    [0, 0, 0, 0, 0],
    [false],
    [@model.None],
    [-1],
    [crash_mon("Atk", [rain], 200)],
    defender_hps,
    0,
    [0, 0, 0, 0, 0],
    [false],
    [crash_mon("Water", [im_tackle()], 200, ability="ちょすい")],
    [false],
    weather,
    turns,
    [@model.Field::None],
    [0],
    rain,
    0,
  )
  @debug.assert_eq(weather[0], @model.Rain)
  @debug.assert_eq(defender_hps[0], 100)
}

///|
fn abmc_mon(name : String, ability : String, mv : @model.Move, spe : Int) -> Combatant {
  let p = mk_pokemon(name, "ノーマル", "", 200, 100, 100, 100, 100, spe)
  pl_cmb(p, [mv], ability=ability)
}

///|
test "select DP/MC parity: Water Absorb heals and takes no damage roll" {
  let surf = mk_move("なみのり", "みず", @model.Special, 90)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let own = [abmc_mon("Surf", "", surf, 100)]
  let opp_abs = [abmc_mon("Abs", "ちょすい", splash, 60)]
  let opp_plain = [abmc_mon("Plain", "", splash, 60)]
  let dp_abs = switching_game_winrate(own, opp_abs, 2)
  let mc_abs = team_rollout(own, opp_abs, seeded_rng(74011UL), turn_limit=2, epsilon=0.0)
  assert_true((dp_abs - mc_abs).abs() < 0.001)
  let dp_plain = switching_game_winrate(own, opp_plain, 2)
  assert_true((dp_abs - dp_plain).abs() > 0.03)
}
