///|
/// ちからずく の威力 1.3 倍は、すでに剥がしている追加効果 (status_effect / flinch_chance)
/// があるダメージ技だけに掛かる。アナライズ は従来どおり全技。DP と MC は同じ
/// ダメージ式を通るので、ブーストあり / なしの両方で値が近い。

///|
fn sfb_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 0.02
}

///|
fn sfb_key(ability : String, mv : @model.Move) -> String raise {
  let atk = ss_cmb(ss_pokemon("atk", "ノーマル", "", 200, 100), [mv], ability)
  let dfn = ss_cmb(ss_pokemon("def", "ノーマル", "", 200, 80), [mv], "")
  let input = combatant_to_cache_key_input(atk, dfn, mv, 0, 0)
  guard @damage_cache.build_cache_key(input) is Ok(k) else {
    fail("build_cache_key failed")
  }
  k
}

///|
/// 剥がす集合と威力ゲートが同じ。能力変化だけの技はどちらも対象外。
test "sheer force: strip and 1.3x share status and flinch on damaging moves" {
  let bite = {
    ..ss_move("かみつく", "あく", @model.Physical, 60, 100, None),
    flinch_chance: 30,
  }
  let punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 100)),
  )
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let stat_only = {
    ..ss_move("インファイト", "かくとう", @model.Physical, 120, 100, None),
    stat_effects: [{ stat: 1, delta: -1, target: 0 }],
  }
  let base = ss_state(200, 200, @model.None, @model.None)
  let sheer_team = [ss_cmb(ss_pokemon("sheer", "ノーマル", "", 200, 120), [bite], "ちからずく")]
  let plain_team = [ss_cmb(ss_pokemon("plain", "ノーマル", "", 200, 120), [bite], "")]
  assert_true(@damage.move_has_sheer_force_effect(bite))
  assert_true(@damage.move_has_sheer_force_effect(punch))
  assert_true(!@damage.move_has_sheer_force_effect(tackle))
  assert_true(!@damage.move_has_sheer_force_effect(stat_only))
  let gated_bite = secondary_gated_move(base, true, 0, sheer_team, bite, 50)
  assert_true(gated_bite.flinch_chance == 0)
  assert_true(!@damage.move_has_sheer_force_effect(gated_bite))
  // 無特性はひるみを残す。威力ゲートも立たない。
  let kept = secondary_gated_move(base, true, 0, plain_team, bite, 50)
  assert_true(kept.flinch_chance == 30)
  assert_true(!@damage.sheer_force_boost_applies("", kept))
  let gated_punch = secondary_gated_move(base, true, 0, sheer_team, punch, 50)
  assert_true(gated_punch.status_effect is None)
  assert_true(!@damage.move_has_sheer_force_effect(gated_punch))
  let gated_stat = secondary_gated_move(base, true, 0, sheer_team, stat_only, 50)
  assert_true(gated_stat.stat_effects.length() == 1)
  assert_true(gated_stat.stat_effects[0].delta == -1)
  // MC も同じゲートで追加効果を落とす。
  let rng = seeded_rng(20261112UL)
  let defender = ss_cmb(ss_pokemon("def", "ノーマル", "", 200, 60), [tackle], "")
  assert_false(mc_flinch_roll(rng, bite, "ちからずく", defender, 200, 170, false))
  let status : Array[@model.StatusCondition] = [@model.StatusCondition::None]
  mc_try_apply_status(
    rng,
    punch,
    [defender],
    [200],
    status,
    0,
    hp_lost=50,
    attacker_ability="ちからずく",
  )
  assert_true(status[0] == @model.StatusCondition::None)
}

///|
/// 威力。追加効果のある技だけ ちからずく が無特性より高く、追加効果の無い技は同値。
/// アナライズ はどちらも上がり、追加効果のある技では ちからずく と同値 (同じ 5325)。
test "sheer force damage: 1.3x only with a secondary; Analytic stays on every move" {
  let bite = {
    ..ss_move("かみつく", "あく", @model.Physical, 60, 100, None),
    flinch_chance: 30,
  }
  let punch = ss_move(
    "ほのおのパンチ",
    "ほのお",
    @model.Physical,
    75,
    100,
    Some((@model.BurnKind, 10)),
  )
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let stat_only = {
    ..ss_move("インファイト", "かくとう", @model.Physical, 120, 100, None),
    stat_effects: [{ stat: 1, delta: -1, target: 0 }],
  }
  let atk_p = ss_pokemon("atk", "ノーマル", "", 200, 100)
  let def_p = ss_pokemon("def", "ノーマル", "", 200, 80)
  let sheer = ss_cmb(atk_p, [], "ちからずく")
  let plain = ss_cmb(atk_p, [], "")
  let analytic = ss_cmb(atk_p, [], "アナライズ")
  let defender = ss_cmb(def_p, [], "")
  let dmg = fn(atk, mv) { compute_mean_damage(atk, defender, mv, 0, 0) }
  let plain_bite = dmg(plain, bite)
  let sheer_bite = dmg(sheer, bite)
  let analytic_bite = dmg(analytic, bite)
  assert_true(sheer_bite > plain_bite)
  @debug.assert_eq(sheer_bite, analytic_bite)
  let plain_punch = dmg(plain, punch)
  assert_true(dmg(sheer, punch) > plain_punch)
  @debug.assert_eq(dmg(sheer, punch), dmg(analytic, punch))
  @debug.assert_eq(dmg(sheer, tackle), dmg(plain, tackle))
  assert_true(dmg(analytic, tackle) > dmg(plain, tackle))
  @debug.assert_eq(dmg(sheer, stat_only), dmg(plain, stat_only))
}

///|
/// 同じ技名でも追加効果の有無で L2 キーが分かれる。ちからずく 以外は分かれていない
/// (追加効果はダメージを変えない)。
test "sheer force cache key: boosted and unboosted copies of one move name do not alias" {
  let plain = ss_move("かみつく", "あく", @model.Physical, 60, 100, None)
  let flinch = { ..plain, flinch_chance: 30 }
  let burn = {
    ..plain,
    status_effect: Some((@model.BurnKind, 10)),
  }
  assert_true(sfb_key("ちからずく", plain) != sfb_key("ちからずく", flinch))
  assert_true(sfb_key("ちからずく", plain) != sfb_key("ちからずく", burn))
  // どちらも 1.3 倍なので、技名が同じならキーは同じでよい。
  @debug.assert_eq(sfb_key("ちからずく", flinch), sfb_key("ちからずく", burn))
  @debug.assert_eq(sfb_key("", plain), sfb_key("", flinch))
  @debug.assert_eq(sfb_key("アナライズ", plain), sfb_key("アナライズ", flinch))
  assert_true(sfb_key("ちからずく", flinch) != sfb_key("アナライズ", flinch))
}

///|
/// DP / MC。ひるみ 100% を剥がして 1.3 倍だけが残るケースと、追加効果の無い
/// たいあたり (1.0 倍) の両方で差が小さい。HP 1000 は KO 閾値を跨がないため。
test "sheer force DP/MC parity: boosted flinch move and unboosted tackle" {
  let bite = {
    ..ss_move("かみつく", "あく", @model.Physical, 60, 100, None),
    flinch_chance: 100,
  }
  let tackle = ss_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None)
  let target = [ss_cmb(ss_pokemon("target", "ノーマル", "", 1000, 60), [tackle], "")]
  let boosted = [ss_cmb(ss_pokemon("boosted", "ノーマル", "", 1000, 120), [bite], "ちからずく")]
  let unboosted = [
    ss_cmb(ss_pokemon("unboosted", "ノーマル", "", 1000, 120), [tackle], "ちからずく"),
  ]
  let dp_boosted = switching_game_winrate(boosted, target, 4)
  let mc_boosted = team_monte_carlo_value(
    boosted,
    target,
    8192,
    20261112UL,
    turn_limit=4,
  )
  let dp_plain = switching_game_winrate(unboosted, target, 4)
  let mc_plain = team_monte_carlo_value(
    unboosted,
    target,
    8192,
    20261112UL,
    turn_limit=4,
  )
  assert_true(sfb_close(dp_boosted, mc_boosted))
  assert_true(sfb_close(dp_plain, mc_plain))
  // ひるみを残す無特性とは値が分かれる (剥がしが勝率に効いている)。
  let keeps_flinch = [ss_cmb(ss_pokemon("plain", "ノーマル", "", 1000, 120), [bite], "")]
  let dp_flinch = switching_game_winrate(keeps_flinch, target, 4)
  assert_true((dp_boosted - dp_flinch).abs() > 0.005)
}
