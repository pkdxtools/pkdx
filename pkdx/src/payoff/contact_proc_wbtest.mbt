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
