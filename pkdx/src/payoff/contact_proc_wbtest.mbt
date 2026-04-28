///|
/// Whitebox tests for apply_contact_proc_fanout (issue #93 / P4).

///|
fn cp_pokemon(name : String, type1 : String, type2 : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2,
    hp: 200,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 700,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
}

///|
fn cp_combatant(
  pokemon : @model.Pokemon,
  ability~ : String = "",
  item~ : String = "",
) -> Combatant {
  {
    pokemon,
    moves: [],
    ability,
    item,
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
fn cp_state() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100, 100],
    opp_hps: [100, 100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false, false],
    opp_megaed: [false, false, false],
    my_status: [@model.None, @model.None, @model.None],
    opp_status: [@model.None, @model.None, @model.None],
    my_must_recharge: [false, false, false],
    opp_must_recharge: [false, false, false],
    turn: 0,
  }
}

///|
fn cp_move(name : String) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
    power: 60,
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
test "contact_proc_fanout: ほのおのからだ vs contact move → 30% Burn" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり") // contact move
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // Expect 2 leaves: (0.7, no status) + (0.3, attacker burned)
  inspect(outcomes.length(), content="2")
  let mut p_sum = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    p_sum = p_sum + outcomes[i].0
  }
  let drift = if p_sum > 1.0 { p_sum - 1.0 } else { 1.0 - p_sum }
  inspect(drift < 1.0e-9, content="true")
}

///|
test "contact_proc_fanout: non-contact move → no fanout" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  // みずでっぽう is non-contact in the global table
  let mv = cp_move("みずでっぽう")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="1")
}

///|
test "contact_proc_fanout: defender has とびだすハバネロ → 100% Burn (single leaf)" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), item="とびだすハバネロ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="1")
  let drift = if outcomes[0].0 > 1.0 { outcomes[0].0 - 1.0 } else { 1.0 - outcomes[0].0 }
  inspect(drift < 1.0e-9, content="true")
}

///|
test "contact_proc_fanout: fire-type attacker is immune to burn proc" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ほのお", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // Fire types ignore Burn → no fanout, just (1.0, state)
  inspect(outcomes.length(), content="1")
}

///|
test "contact_proc_fanout: defender has no proc ability/item → no fanout" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(cp_pokemon("defender", "ノーマル", ""))
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="1")
}

///|
fn cp_multihit_move(name : String) -> @model.Move {
  // mhv_move と同じ shape だが、Skill Link 等で hit 数が確定する技に
  // なるよう name のみ差し替える。base power は contact-proc fanout の
  // 確率計算には影響しない。
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
    power: 25,
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
fn approx_eq_cp(a : Double, b : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < 1.0e-9
}

///|
test "contact_proc_fanout: skill-link 5-hit contact move → P(burn)=1-0.7^5" {
  // #100: 多段技の各 contact 着弾で独立に proc 判定。スキルリンクで みだれづき
  // が確定 5 ヒットになる場合、ほのおのからだ の発火確率は 1 - 0.7^5 ≈ 0.832。
  let attacker = cp_combatant(
    cp_pokemon("attacker", "ノーマル", ""), ability="スキルリンク",
  )
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_multihit_move("みだれづき")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="2")
  // outcomes[0] は no-proc, outcomes[1] が burn 状態。
  let q5 = 0.7 * 0.7 * 0.7 * 0.7 * 0.7
  let expected_burn = 1.0 - q5
  let p_sum = outcomes[0].0 + outcomes[1].0
  assert_true(approx_eq_cp(p_sum, 1.0))
  assert_true(approx_eq_cp(outcomes[0].0, q5))
  assert_true(approx_eq_cp(outcomes[1].0, expected_burn))
}

///|
test "contact_proc_fanout: ほうし produces 4 leaves (no-status / poison / paralyze / sleep)" {
  // #100: ほうし は per-hit で 11% どく / 10% まひ / 9% ねむり (合計 30%) を
  // 独立試行扱いする。タイプ耐性のないノーマル攻撃側に対しては、3 種すべての
  // 状態異常 leaf が得られるはず。
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほうし",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // [no-status, poison, paralyze, sleep] = 4 leaves
  inspect(outcomes.length(), content="4")
  let mut p_sum = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    p_sum = p_sum + outcomes[i].0
  }
  assert_true(approx_eq_cp(p_sum, 1.0))
  // no-status mass = 0.7 (1 - p_total per hit)
  assert_true(approx_eq_cp(outcomes[0].0, 0.7))
}

///|
test "contact_proc_fanout: ほうし vs poison-immune attacker keeps paralyze and sleep" {
  // #100: どくタイプ攻撃側は どく proc に耐性があるが、まひ / ねむり は
  // そのまま残るべき。MVP の単一 proc 折り畳みでは丸ごと無効化される
  // 退行を防ぐ。
  let attacker = cp_combatant(cp_pokemon("attacker", "どく", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほうし",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // poison が immune fizzle するので [no-status, paralyze, sleep] の 3 leaves。
  inspect(outcomes.length(), content="3")
  let mut p_sum = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    p_sum = p_sum + outcomes[i].0
  }
  assert_true(approx_eq_cp(p_sum, 1.0))
  // viable_chance = 19 (10 まひ + 9 ねむり)、total_chance = 30
  // p_any_proc = 0.30、 p_viable = 0.30 × 19/30 = 0.19
  // no-status = 1 - 0.19 = 0.81
  assert_true(approx_eq_cp(outcomes[0].0, 0.81))
}
