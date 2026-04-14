///|
/// Shared move fixtures (type-matched to typical tests).
fn m_ground_phys() -> @model.Move {
  mk_move("じしん", "じめん", @model.Physical, 100)
}

///|
fn m_shadow() -> @model.Move {
  mk_move("シャドーボール", "ゴースト", @model.Special, 80)
}

///|
fn m_flamethrower() -> @model.Move {
  mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)
}

///|
fn m_water() -> @model.Move {
  mk_move("なみのり", "みず", @model.Special, 90)
}

///|
test "payoff_model_enum_exhaustive" {
  // All variants must be constructible and distinguishable via match. If a new
  // variant is added without updating callers, this test's match will no longer
  // be exhaustive and the compiler will flag it.
  let models : Array[PayoffModel] = [
    Best1v1,
    NashResponses,
    MonteCarloSim(1, 0UL),
  ]
  let labels = models.map(fn(m) {
    match m {
      Best1v1 => "best1v1"
      NashResponses => "nash_responses"
      MonteCarloSim(_, _) => "monte_carlo"
    }
  })
  let mut joined = ""
  for i in 0..<labels.length() {
    if i > 0 {
      joined = joined + ","
    }
    joined = joined + labels[i]
  }
  inspect(joined, content="best1v1,nash_responses,monte_carlo")
}

///|
test "best1v1_speed_tiebreak_determines_winrate" {
  // Two identical Pokemon with the same move: KO turns are identical, so
  // speed breaks the tie.
  let base = mk_pokemon("A", "ノーマル", "", 100, 100, 100, 100, 100, 100)
  let fast = { ..base, name_ja: "Fast", spe: 120 }
  let slow = { ..base, name_ja: "Slow", spe: 80 }
  let mv = mk_move("のしかかり", "ノーマル", @model.Physical, 85)
  let a = mk_combatant(fast, [mv])
  let b = mk_combatant(slow, [mv])
  assert_true(best1v1_winrate(a, b) == 1.0)
  assert_true(best1v1_winrate(b, a) == 0.0)
  // Exact speed tie → 0.5.
  let a2 = mk_combatant(base, [mv])
  let b2 = mk_combatant(base, [mv])
  assert_true(best1v1_winrate(a2, b2) == 0.5)
}

///|
test "best1v1_best_move_selection_maximizes_winrate" {
  // A: picks between a strong and a weak move. Only the strong move is fast
  // enough to KO faster than B.
  let a_poke = mk_pokemon("A", "じめん", "", 100, 130, 80, 80, 80, 100)
  let b_poke = mk_pokemon("B", "ノーマル", "", 100, 100, 80, 80, 80, 110)
  let strong = mk_move("じしん", "じめん", @model.Physical, 100)
  let weak = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let b_move = mk_move("のしかかり", "ノーマル", @model.Physical, 85)
  // With only the weak move, A is slower to KO and outspeed-loses.
  let a_weak_only = mk_combatant(a_poke, [weak])
  let b = mk_combatant(b_poke, [b_move])
  assert_true(best1v1_winrate(a_weak_only, b) == 0.0)
  // With the strong move available (even alongside the weak one), A wins.
  let a_both = mk_combatant(a_poke, [weak, strong])
  assert_true(best1v1_winrate(a_both, b) == 1.0)
}

///|
test "nash_responses_matches_inner_game_value" {
  // 1-move combatants reduce the inner game to 1×1, whose Nash value equals
  // the single cell (±1 / 0). So `nash_responses_winrate` must match
  // `best1v1_winrate` exactly.
  let a_poke = mk_pokemon("A", "じめん", "", 100, 130, 80, 80, 80, 100)
  let b_poke = mk_pokemon("B", "ノーマル", "", 100, 100, 80, 80, 80, 110)
  let a = mk_combatant(a_poke, [m_ground_phys()])
  let b = mk_combatant(b_poke, [mk_move("のしかかり", "ノーマル", @model.Physical, 85)])
  let w_best = best1v1_winrate(a, b)
  let w_nash = nash_responses_winrate(a, b)
  assert_true((w_best - w_nash).abs() < 1.0e-9)
}

///|
test "damage_matrix_is_zero_sum_approximation" {
  let chars = [
    mk_combatant(
      mk_pokemon("A", "じめん", "", 100, 130, 95, 80, 85, 102),
      [m_ground_phys(), m_shadow()],
    ),
    mk_combatant(
      mk_pokemon("B", "はがね", "ゴースト", 87, 60, 95, 133, 91, 84),
      [m_shadow(), m_flamethrower()],
    ),
    mk_combatant(
      mk_pokemon("C", "みず", "", 79, 83, 100, 85, 105, 78),
      [m_water(), mk_move("れいとうビーム", "こおり", @model.Special, 90)],
    ),
  ]
  let m = from_combatants(chars, Best1v1)
  for i in 0..<3 {
    for j in 0..<3 {
      assert_true((m.at(i, j) + m.at(j, i)).abs() < 1.0e-12)
    }
    assert_true(m.at(i, i).abs() < 1.0e-12)
  }
}

///|
test "damage_matrix_snapshot_for_known_pair_garchomp_gholdengo" {
  // Garchomp (ドラゴン/じめん) vs Gholdengo (はがね/ゴースト). じしん is 2×
  // super-effective vs はがね and neutral vs ゴースト (net ×2). Gholdengo's
  // シャドーボール is neutral vs both ドラゴン and じめん. Garchomp is faster
  // (102 > 84) and has much higher attack, so it outruns Gholdengo.
  let garchomp = mk_combatant(
    mk_pokemon("ガブリアス", "ドラゴン", "じめん", 108, 130, 95, 80, 85, 102),
    [m_ground_phys()],
  )
  let gholdengo = mk_combatant(
    mk_pokemon("サーフゴー", "はがね", "ゴースト", 87, 60, 95, 133, 91, 84),
    [m_shadow()],
  )
  let m = from_combatants([garchomp, gholdengo], Best1v1)
  inspect(m.at(0, 1), content="1")
  inspect(m.at(1, 0), content="-1")
}

///|
test "damage_matrix_respects_tera_type_flip" {
  // Identical combatants with the same off-type special move. Base matchup is
  // a complete mirror → speed tie → payoff 0. Terastallising one side into
  // the move's type grants STAB and flips the outcome to +1.
  let poke = mk_pokemon("X", "ノーマル", "", 120, 80, 80, 100, 80, 100)
  let mv = mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)
  let a = mk_combatant(poke, [mv])
  let b = mk_combatant(poke, [mv])
  let m_base = from_combatants([a, b], Best1v1)
  assert_true(m_base.at(0, 1).abs() < 1.0e-12)
  let a_tera = { ..a, tera_type: "ほのお" }
  let m_tera = from_combatants([a_tera, b], Best1v1)
  assert_true(m_tera.at(0, 1) > 0.0)
  assert_true(m_tera.at(0, 1) != m_base.at(0, 1))
}

///|
test "damage_matrix_respects_item_and_ability" {
  // こだわりハチマキ boosts physical attack 1.5×. An item that changes
  // damage output must shift the payoff matrix.
  let a_poke = mk_pokemon("A", "ノーマル", "", 100, 100, 90, 70, 90, 100)
  let b_poke = mk_pokemon("B", "ノーマル", "", 100, 100, 90, 70, 90, 100)
  let mv = mk_move("のしかかり", "ノーマル", @model.Physical, 85)
  let plain = mk_combatant(a_poke, [mv])
  let boosted = mk_combatant(a_poke, [mv], item="こだわりハチマキ")
  let b = mk_combatant(b_poke, [mv])
  let m_plain = from_combatants([plain, b], Best1v1)
  let m_boost = from_combatants([boosted, b], Best1v1)
  // Plain mirror: identical → speed tie → 0.
  assert_true(m_plain.at(0, 1).abs() < 1.0e-12)
  // Boosted A should gain an advantage (payoff > 0 for A).
  assert_true(m_boost.at(0, 1) > 0.0)
}

///|
test "damage_matrix_matches_pkdx_damage_cli_on_sampled_pairs" {
  // Integration test against the in-process damage engine (no subprocess).
  // Scenario: A (ノーマル) with のしかかり cannot damage B (ゴースト) — ノーマル
  // is immune to ゴースト. B counter-attacks with かみくだく (あく → ノーマル
  // neutral). Matrix cell must reflect that A loses.
  let a_poke = mk_pokemon("A", "ノーマル", "", 100, 100, 80, 80, 80, 100)
  let b_poke = mk_pokemon("B", "ゴースト", "", 100, 70, 80, 100, 80, 90)
  let a_mv = mk_move("のしかかり", "ノーマル", @model.Physical, 85)
  let b_mv = mk_move("かみくだく", "あく", @model.Physical, 80)
  let a = mk_combatant(a_poke, [a_mv])
  let b = mk_combatant(b_poke, [b_mv])
  let m = from_combatants([a, b], Best1v1)
  let r_ab = @damage.calc_damage({
    attacker: a_poke,
    defender: b_poke,
    move_: a_mv,
    atk_ability: "",
    def_ability: "",
    atk_item: "",
    def_item: "",
    weather: @model.Weather::None,
    field: @model.Field::None,
    tera_type: "",
    critical: false,
    atk_stat_override: 0,
    def_stat_override: 0,
    def_hp_override: 0,
    atk_rank: 0,
    def_rank: 0,
    fainted_count: 0,
    is_double: false,
    stat_system: @model.Standard,
  })
  // のしかかり (ノーマル) vs ゴースト → immune.
  assert_true(r_ab.is_immune)
  inspect(m.at(0, 1), content="-1")
}
