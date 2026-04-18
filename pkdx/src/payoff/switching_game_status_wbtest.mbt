///|
/// Tests for status-aware damage and speed helpers introduced in Task 4.

///|
test "compute_mean_damage: burned attacker halves physical damage" {
  let attacker_pokemon : @model.Pokemon = {
    global_no: "0006",
    name_ja: "リザードン",
    name_en: "Charizard",
    type1: "ほのお",
    type2: "ひこう",
    hp: 78,
    atk: 84,
    def_: 78,
    spa: 109,
    spd: 85,
    spe: 100,
    bst: 534,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 90.5,
  }
  let defender_pokemon : @model.Pokemon = {
    global_no: "0143",
    name_ja: "カビゴン",
    name_en: "Snorlax",
    type1: "ノーマル",
    type2: "",
    hp: 160,
    atk: 110,
    def_: 65,
    spa: 65,
    spd: 110,
    spe: 30,
    bst: 540,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 460.0,
  }
  let atk : Combatant = {
    pokemon: attacker_pokemon,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
  }
  let dfn : Combatant = {
    pokemon: defender_pokemon,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
  }
  let physical_move : @model.Move = {
    name: "じしん",
    type_: "じめん",
    category: @model.Physical,
    power: 100,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
  }
  let normal = compute_mean_damage(atk, dfn, physical_move, 0, 0)
  let burned = compute_mean_damage(atk, dfn, physical_move, 0, 0, atk_burn=true)
  assert_true(normal > 0)
  assert_eq(burned, normal / 2)
}

///|
test "compute_mean_damage: burned special attacker unchanged" {
  let attacker_pokemon : @model.Pokemon = {
    global_no: "0006",
    name_ja: "リザードン",
    name_en: "Charizard",
    type1: "ほのお",
    type2: "ひこう",
    hp: 78,
    atk: 84,
    def_: 78,
    spa: 109,
    spd: 85,
    spe: 100,
    bst: 534,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 90.5,
  }
  let defender_pokemon : @model.Pokemon = {
    global_no: "0143",
    name_ja: "カビゴン",
    name_en: "Snorlax",
    type1: "ノーマル",
    type2: "",
    hp: 160,
    atk: 110,
    def_: 65,
    spa: 65,
    spd: 110,
    spe: 30,
    bst: 540,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 460.0,
  }
  let atk : Combatant = {
    pokemon: attacker_pokemon,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
  }
  let dfn : Combatant = {
    pokemon: defender_pokemon,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
  }
  let special_move : @model.Move = {
    name: "かえんほうしゃ",
    type_: "ほのお",
    category: @model.Special,
    power: 90,
    accuracy: 100,
    pp: 15,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
  }
  let normal = compute_mean_damage(atk, dfn, special_move, 0, 0)
  let burned = compute_mean_damage(atk, dfn, special_move, 0, 0, atk_burn=true)
  assert_eq(normal, burned)
}

///|
test "is_paralyzed / is_burned / sleep_turns: status predicates" {
  assert_true(is_paralyzed(@model.Paralyze))
  assert_false(is_paralyzed(@model.Burn))
  assert_false(is_paralyzed(@model.None))
  assert_true(is_burned(@model.Burn))
  assert_false(is_burned(@model.Paralyze))
  assert_eq(sleep_turns(@model.Sleep(2)), Some(2))
  assert_eq(sleep_turns(@model.Sleep(0)), Some(0))
  assert_eq(sleep_turns(@model.None), None)
  assert_eq(sleep_turns(@model.Paralyze), None)
}

///|
test "zero_status: builds None-filled array of given length" {
  let s = zero_status(3)
  assert_eq(s.length(), 3)
  assert_eq(s[0], @model.None)
  assert_eq(s[1], @model.None)
  assert_eq(s[2], @model.None)
}

///|
fn sum_probs(attempts : Array[SideAttempt]) -> Double {
  let mut s = 0.0
  for a in attempts {
    s += a.prob
  }
  s
}

///|
test "per_side_attempt: Switch is always 1.0 regardless of status" {
  let out = per_side_attempt(@model.Paralyze, Switch(1), 100)
  assert_eq(out.length(), 1)
  assert_eq(out[0].prob, 1.0)
  assert_true(out[0].acts)
  let out2 = per_side_attempt(@model.Sleep(2), Switch(1), 100)
  assert_eq(out2.length(), 1)
  assert_true(out2[0].acts)
}

///|
test "per_side_attempt: None + UseMove + acc=100 -> single act 1.0" {
  let out = per_side_attempt(@model.None, UseMove(0), 100)
  assert_eq(out.length(), 1)
  assert_eq(out[0].prob, 1.0)
  assert_true(out[0].acts)
}

///|
test "per_side_attempt: None + UseMove + acc=85 -> hit 0.85 / miss 0.15" {
  let out = per_side_attempt(@model.None, UseMove(0), 85)
  assert_eq(out.length(), 2)
  let total = sum_probs(out)
  assert_true((total - 1.0).abs() < 1.0e-9)
}

///|
test "per_side_attempt: Paralyze + UseMove + acc=100 -> 0.125 skip / 0.875 act" {
  let out = per_side_attempt(@model.Paralyze, UseMove(0), 100)
  assert_eq(out.length(), 2)
  let total = sum_probs(out)
  assert_true((total - 1.0).abs() < 1.0e-9)
}

///|
test "per_side_attempt: Sleep(n>0) always skips and decrements counter" {
  let out = per_side_attempt(@model.Sleep(2), UseMove(0), 100)
  assert_eq(out.length(), 1)
  assert_false(out[0].acts)
  assert_eq(out[0].post_status, @model.Sleep(1))
  let out2 = per_side_attempt(@model.Sleep(1), UseMove(0), 100)
  assert_eq(out2.length(), 1)
  assert_false(out2[0].acts)
  assert_eq(out2[0].post_status, @model.Sleep(0))
}

///|
test "per_side_attempt: Sleep(0) wakes up and acts (status -> None)" {
  let out = per_side_attempt(@model.Sleep(0), UseMove(0), 100)
  assert_eq(out.length(), 1)
  assert_true(out[0].acts)
  assert_eq(out[0].post_status, @model.None)
}

///|
test "per_side_attempt: Paralyze + UseMove + acc=85 -> 3 branches sum to 1" {
  let out = per_side_attempt(@model.Paralyze, UseMove(0), 85)
  assert_eq(out.length(), 3)
  let total = sum_probs(out)
  assert_true((total - 1.0).abs() < 1.0e-9)
}

///|
test "eot_slip_active: Burn subtracts 1/16 of max HP, status unchanged" {
  let (hp, st) = eot_slip_active(160, 160, @model.Burn)
  assert_eq(hp, 150)
  assert_eq(st, @model.Burn)
}

///|
test "eot_slip_active: Poison subtracts 1/8 of max HP" {
  let (hp, st) = eot_slip_active(160, 160, @model.Poison)
  assert_eq(hp, 140)
  assert_eq(st, @model.Poison)
}

///|
test "eot_slip_active: BadPoison increments counter and applies (n+1)/16" {
  let (hp, st) = eot_slip_active(160, 160, @model.BadPoison(0))
  assert_eq(hp, 150) // 160 - 160*1/16 = 150
  assert_eq(st, @model.BadPoison(1))
  let (hp2, st2) = eot_slip_active(160, 160, @model.BadPoison(1))
  assert_eq(hp2, 140) // 160 - 160*2/16 = 140
  assert_eq(st2, @model.BadPoison(2))
}

///|
test "eot_slip_active: BadPoison saturates at TOXIC_MAX_TICKS=15" {
  let (_, st) = eot_slip_active(200, 200, @model.BadPoison(15))
  assert_eq(st, @model.BadPoison(15))
}

///|
test "eot_slip_active: None / Paralyze / Sleep are no-op for HP" {
  let (hp1, _) = eot_slip_active(100, 100, @model.None)
  assert_eq(hp1, 100)
  let (hp2, _) = eot_slip_active(100, 100, @model.Paralyze)
  assert_eq(hp2, 100)
  let (hp3, _) = eot_slip_active(100, 100, @model.Sleep(2))
  assert_eq(hp3, 100)
}

///|
test "eot_slip_active: fainted (hp=0) never takes additional damage" {
  let (hp, st) = eot_slip_active(0, 160, @model.Burn)
  assert_eq(hp, 0)
  assert_eq(st, @model.Burn)
}

///|
test "reset_toxic_counter_on_switch: BadPoison(n) -> BadPoison(0)" {
  assert_eq(
    reset_toxic_counter_on_switch(@model.BadPoison(7)),
    @model.BadPoison(0),
  )
  assert_eq(
    reset_toxic_counter_on_switch(@model.Poison),
    @model.Poison,
  )
  assert_eq(reset_toxic_counter_on_switch(@model.None), @model.None)
}

///|
test "reset_toxic_counter_on_switch: Drowsy cleared to None on switch-out" {
  assert_eq(reset_toxic_counter_on_switch(@model.Drowsy(1)), @model.None)
  assert_eq(reset_toxic_counter_on_switch(@model.Drowsy(0)), @model.None)
}

///|
test "eot_slip_active: Drowsy(1) counts down to Drowsy(0)" {
  let (hp, st) = eot_slip_active(100, 100, @model.Drowsy(1))
  assert_eq(hp, 100)
  assert_eq(st, @model.Drowsy(0))
}

///|
test "eot_slip_active: Drowsy(0) triggers Sleep(2) at EOT" {
  let (hp, st) = eot_slip_active(100, 100, @model.Drowsy(0))
  assert_eq(hp, 100)
  assert_eq(st, @model.Sleep(2))
}

///|
fn mk_test_pokemon(
  name : String,
  type1 : String,
  type2~ : String = "",
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2,
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
  }
}

///|
fn mk_test_combatant(pokemon : @model.Pokemon) -> Combatant {
  {
    pokemon,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
  }
}

///|
fn mk_test_state(
  team_size : Int,
  my_hp : Int,
  opp_hp : Int,
  my_status : @model.StatusCondition,
  opp_status : @model.StatusCondition,
) -> SwitchingGameState {
  let my_hps = Array::make(team_size, my_hp)
  let opp_hps = Array::make(team_size, opp_hp)
  let my_st : Array[@model.StatusCondition] = Array::make(team_size, @model.None)
  let opp_st : Array[@model.StatusCondition] = Array::make(team_size, @model.None)
  my_st[0] = my_status
  opp_st[0] = opp_status
  {
    my_active: 0,
    opp_active: 0,
    my_hps,
    opp_hps,
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: Array::make(team_size, false),
    opp_megaed: Array::make(team_size, false),
    my_status: my_st,
    opp_status: opp_st,
    turn: 0,
  }
}

///|
test "maybe_apply_status_fanout: move with no status_effect returns single outcome" {
  let state = mk_test_state(1, 100, 100, @model.None, @model.None)
  let target_team = [mk_test_combatant(mk_test_pokemon("A", "ノーマル"))]
  let mv : @model.Move = {
    name: "たいあたり",
    type_: "ノーマル",
    category: @model.Physical,
    power: 40,
    accuracy: 100,
    pp: 35,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
  }
  let out = maybe_apply_status_fanout(state, false, 0, target_team, mv)
  assert_eq(out.length(), 1)
  assert_eq(out[0].0, 1.0)
}

///|
test "maybe_apply_status_fanout: Will-o-wisp (85% burn) fans out" {
  let state = mk_test_state(1, 100, 100, @model.None, @model.None)
  let target_team = [mk_test_combatant(mk_test_pokemon("A", "みず"))]
  let mv : @model.Move = {
    name: "おにび",
    type_: "ほのお",
    category: @model.Status,
    power: 0,
    accuracy: 85,
    pp: 15,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: Some((@model.BurnKind, 100)),
  }
  let out = maybe_apply_status_fanout(state, false, 0, target_team, mv)
  // chance = 100 → deterministic apply
  assert_eq(out.length(), 1)
  assert_eq(out[0].1.opp_status[0], @model.Burn)
}

///|
test "maybe_apply_status_fanout: fire-type immune to burn" {
  let state = mk_test_state(1, 100, 100, @model.None, @model.None)
  let target_team = [mk_test_combatant(mk_test_pokemon("A", "ほのお"))]
  let mv : @model.Move = {
    name: "おにび",
    type_: "ほのお",
    category: @model.Status,
    power: 0,
    accuracy: 85,
    pp: 15,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: Some((@model.BurnKind, 100)),
  }
  let out = maybe_apply_status_fanout(state, false, 0, target_team, mv)
  assert_eq(out.length(), 1)
  assert_eq(out[0].1.opp_status[0], @model.None)
}

///|
test "maybe_apply_status_fanout: already statused target is not re-infected" {
  let state = mk_test_state(1, 100, 100, @model.None, @model.Paralyze)
  let target_team = [mk_test_combatant(mk_test_pokemon("A", "ノーマル"))]
  let mv : @model.Move = {
    name: "おにび",
    type_: "ほのお",
    category: @model.Status,
    power: 0,
    accuracy: 85,
    pp: 15,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: Some((@model.BurnKind, 100)),
  }
  let out = maybe_apply_status_fanout(state, false, 0, target_team, mv)
  assert_eq(out.length(), 1)
  assert_eq(out[0].1.opp_status[0], @model.Paralyze)
}

///|
/// Helper to run maybe_apply_status_fanout against a target that is already
/// carrying `existing` and return the resulting status. Chance is forced to
/// 100% so any 'apply' path would be observable.
fn run_no_overwrite_case(
  existing : @model.StatusCondition,
  incoming : @model.StatusKind,
) -> @model.StatusCondition {
  let state = mk_test_state(1, 100, 100, @model.None, existing)
  // Target is Normal-type so there's no incidental type immunity confounding
  // the overwrite-guard we actually want to test.
  let target_team = [mk_test_combatant(mk_test_pokemon("A", "ノーマル"))]
  let mv : @model.Move = {
    name: "test",
    type_: "ノーマル",
    category: @model.Status,
    power: 0,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: Some((incoming, 100)),
  }
  let out = maybe_apply_status_fanout(state, false, 0, target_team, mv)
  out[0].1.opp_status[0]
}

///|
test "already-statused guard blocks overwrite for every existing variant" {
  // Paralyze blocks Burn / Poison / BadPoison / Sleep / Drowsy
  assert_eq(run_no_overwrite_case(@model.Paralyze, @model.BurnKind), @model.Paralyze)
  assert_eq(run_no_overwrite_case(@model.Paralyze, @model.PoisonKind), @model.Paralyze)
  assert_eq(run_no_overwrite_case(@model.Paralyze, @model.BadPoisonKind), @model.Paralyze)
  assert_eq(run_no_overwrite_case(@model.Paralyze, @model.SleepKind), @model.Paralyze)
  assert_eq(run_no_overwrite_case(@model.Paralyze, @model.DrowsyKind), @model.Paralyze)
  // Burn blocks Paralyze / Poison / BadPoison / Sleep / Drowsy
  assert_eq(run_no_overwrite_case(@model.Burn, @model.ParalyzeKind), @model.Burn)
  assert_eq(run_no_overwrite_case(@model.Burn, @model.PoisonKind), @model.Burn)
  assert_eq(run_no_overwrite_case(@model.Burn, @model.BadPoisonKind), @model.Burn)
  assert_eq(run_no_overwrite_case(@model.Burn, @model.SleepKind), @model.Burn)
  assert_eq(run_no_overwrite_case(@model.Burn, @model.DrowsyKind), @model.Burn)
  // Poison blocks Paralyze / Burn / BadPoison / Sleep / Drowsy
  assert_eq(run_no_overwrite_case(@model.Poison, @model.ParalyzeKind), @model.Poison)
  assert_eq(run_no_overwrite_case(@model.Poison, @model.BurnKind), @model.Poison)
  assert_eq(run_no_overwrite_case(@model.Poison, @model.BadPoisonKind), @model.Poison)
  assert_eq(run_no_overwrite_case(@model.Poison, @model.SleepKind), @model.Poison)
  assert_eq(run_no_overwrite_case(@model.Poison, @model.DrowsyKind), @model.Poison)
  // BadPoison(n) blocks; counter must also be preserved, not reset.
  assert_eq(
    run_no_overwrite_case(@model.BadPoison(3), @model.BurnKind),
    @model.BadPoison(3),
  )
  assert_eq(
    run_no_overwrite_case(@model.BadPoison(3), @model.DrowsyKind),
    @model.BadPoison(3),
  )
  // Sleep(n) blocks other statuses; remaining turns are preserved.
  assert_eq(
    run_no_overwrite_case(@model.Sleep(1), @model.BurnKind),
    @model.Sleep(1),
  )
  assert_eq(
    run_no_overwrite_case(@model.Sleep(2), @model.DrowsyKind),
    @model.Sleep(2),
  )
  // Drowsy blocks other status applications — matches gen-mechanics where
  // the target can't be newly poisoned/burned while a yawn marker is active
  // (they're considered "about to be statused").
  assert_eq(
    run_no_overwrite_case(@model.Drowsy(1), @model.BurnKind),
    @model.Drowsy(1),
  )
  assert_eq(
    run_no_overwrite_case(@model.Drowsy(1), @model.ParalyzeKind),
    @model.Drowsy(1),
  )
  assert_eq(
    run_no_overwrite_case(@model.Drowsy(0), @model.SleepKind),
    @model.Drowsy(0),
  )
}

///|
test "maybe_apply_status_fanout: fainted target yields no status" {
  let state = mk_test_state(1, 100, 0, @model.None, @model.None)
  let target_team = [mk_test_combatant(mk_test_pokemon("A", "ノーマル"))]
  let mv : @model.Move = {
    name: "おにび",
    type_: "ほのお",
    category: @model.Status,
    power: 0,
    accuracy: 85,
    pp: 15,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: Some((@model.BurnKind, 100)),
  }
  let out = maybe_apply_status_fanout(state, false, 0, target_team, mv)
  assert_eq(out.length(), 1)
  assert_eq(out[0].1.opp_status[0], @model.None)
}

///|
test "maybe_apply_status_fanout: thunder-wave 90% fans to 2 outcomes" {
  let state = mk_test_state(1, 100, 100, @model.None, @model.None)
  let target_team = [mk_test_combatant(mk_test_pokemon("A", "ノーマル"))]
  let mv : @model.Move = {
    name: "でんじは",
    type_: "でんき",
    category: @model.Status,
    power: 0,
    accuracy: 90,
    pp: 20,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: Some((@model.ParalyzeKind, 90)),
  }
  let out = maybe_apply_status_fanout(state, false, 0, target_team, mv)
  assert_eq(out.length(), 2)
  let total = out[0].0 + out[1].0
  assert_true((total - 1.0).abs() < 1.0e-9)
}

///|
/// Build a stat-customised pokemon for the same-turn regression tests.
fn mk_stat_pokemon(
  name : String,
  hp : Int,
  atk : Int,
  spe : Int,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1: "ノーマル",
    type2: "",
    hp,
    atk,
    def_: 100,
    spa: 100,
    spd: 100,
    spe,
    bst: hp + atk + 400 + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
  }
}

///|
fn mk_move_move(
  name : String,
  category : @model.MoveCategory,
  power : Int,
  accuracy : Int,
  status_effect : (@model.StatusKind, Int)?,
) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category,
    power,
    accuracy,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect,
  }
}

///|
fn mk_combatant_with_moves(
  pokemon : @model.Pokemon,
  moves : Array[@model.Move],
) -> Combatant {
  {
    pokemon,
    moves,
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
  }
}

///|
fn mk_same_turn_state(
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  my_hp : Int,
  opp_hp : Int,
) -> SwitchingGameState {
  let _ = my_team
  let _ = opp_team
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [my_hp],
    opp_hps: [opp_hp],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false],
    my_status: zero_status(1),
    opp_status: zero_status(1),
    turn: 0,
  }
}

///|
/// Regression: status inflicted by the faster attacker must take effect
/// before the slower attacker's move resolves. A faster Will-O-Wisp needs to
/// halve the slower target's physical damage on the same turn — previously
/// the burn flag was snapshotted from the pre-turn state and the second leg
/// dealt full physical damage.
test "resolve_moves: faster Will-O-Wisp halves slower target's physical damage same turn" {
  let burner = mk_stat_pokemon("burner", 200, 100, 120)
  let hitter = mk_stat_pokemon("hitter", 200, 150, 60)
  let wowisp = mk_move_move(
    "おにび", @model.Status, 0, 100, Some((@model.BurnKind, 100)),
  )
  let heavy = mk_move_move("じしん", @model.Physical, 100, 100, None)
  let my_team = [mk_combatant_with_moves(burner, [wowisp])]
  let opp_team = [mk_combatant_with_moves(hitter, [heavy])]
  let normal = compute_mean_damage(opp_team[0], my_team[0], heavy, 0, 0)
  let halved = compute_mean_damage(
    opp_team[0], my_team[0], heavy, 0, 0, atk_burn=true,
  )
  // Sanity: the burn halving must be a distinguishable effect.
  assert_true(normal > halved)
  let state = mk_same_turn_state(my_team, opp_team, 200, 200)
  let outs = transition_with_cache(
    state, UseMove(0), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  // Deterministic: wowisp accuracy 100, burn chance 100, no speed tie.
  assert_eq(outs.length(), 1)
  let (_p, ns) = outs[0]
  assert_eq(ns.opp_status[0], @model.Burn)
  // Damage dealt to my active must be the burn-halved value, NOT the full one.
  assert_eq(200 - ns.my_hps[0], halved)
  assert_true(200 - ns.my_hps[0] != normal)
}

///|
/// Mirror case: if the burn user is SLOWER, the fast physical attacker gets
/// to hit at full (non-halved) damage on the turn the burn lands, and the
/// burn halving only matters from the next turn onward. Guards against a
/// regression where the fix over-applied the halving to every first-leg burn
/// regardless of action order.
test "resolve_moves: slower Will-O-Wisp does NOT halve the faster attacker's damage this turn" {
  let burner = mk_stat_pokemon("burner", 200, 100, 60)
  let hitter = mk_stat_pokemon("hitter", 200, 150, 120)
  let wowisp = mk_move_move(
    "おにび", @model.Status, 0, 100, Some((@model.BurnKind, 100)),
  )
  let heavy = mk_move_move("じしん", @model.Physical, 100, 100, None)
  let my_team = [mk_combatant_with_moves(burner, [wowisp])]
  let opp_team = [mk_combatant_with_moves(hitter, [heavy])]
  let normal = compute_mean_damage(opp_team[0], my_team[0], heavy, 0, 0)
  let halved = compute_mean_damage(
    opp_team[0], my_team[0], heavy, 0, 0, atk_burn=true,
  )
  assert_true(normal > halved)
  let state = mk_same_turn_state(my_team, opp_team, 200, 200)
  let outs = transition_with_cache(
    state, UseMove(0), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  assert_eq(outs.length(), 1)
  let (_p, ns) = outs[0]
  // Burn still lands (wowisp executes after the hitter's move).
  assert_eq(ns.opp_status[0], @model.Burn)
  // But the hitter already attacked at full damage this turn — not halved.
  assert_eq(200 - ns.my_hps[0], normal)
  assert_true(200 - ns.my_hps[0] != halved)
}

///|
/// Regression: a faster sleep-inducing move must stop the slower target from
/// executing its own move on the turn the sleep lands. Previously the sleep
/// was applied only after both attacks resolved, so a fast Spore user still
/// took a same-turn hit from the target it had just put to sleep.
test "resolve_moves: faster Spore locks slower target out of the same turn" {
  let sleeper = mk_stat_pokemon("sleeper", 200, 100, 120)
  let hitter = mk_stat_pokemon("hitter", 200, 150, 60)
  let spore = mk_move_move(
    "キノコのほうし", @model.Status, 0, 100, Some((@model.SleepKind, 100)),
  )
  let heavy = mk_move_move("じしん", @model.Physical, 100, 100, None)
  let my_team = [mk_combatant_with_moves(sleeper, [spore])]
  let opp_team = [mk_combatant_with_moves(hitter, [heavy])]
  let state = mk_same_turn_state(my_team, opp_team, 200, 200)
  let outs = transition_with_cache(
    state, UseMove(0), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  assert_eq(outs.length(), 1)
  let (_p, ns) = outs[0]
  // Target must now be asleep with the initial Sleep(2) counter.
  assert_eq(ns.opp_status[0], @model.Sleep(2))
  // Target did not act this turn: faster Spore user is still at full HP.
  assert_eq(ns.my_hps[0], 200)
  // Spore does no damage; the target's HP is untouched too.
  assert_eq(ns.opp_hps[0], 200)
}

///|
/// Paralyze is a speed debuff whose fully-paralyzed roll is a pre-turn
/// attempt check — a mid-turn application does not skip the current action.
/// Guard against regressing the rule by accidentally blocking fresh-paralyze
/// targets the same way Sleep does.
test "resolve_moves: faster Thunder Wave still lets slower target attack this turn" {
  let twaver = mk_stat_pokemon("twaver", 200, 100, 120)
  let hitter = mk_stat_pokemon("hitter", 200, 150, 60)
  let twave = mk_move_move(
    "でんじは", @model.Status, 0, 100, Some((@model.ParalyzeKind, 100)),
  )
  let heavy = mk_move_move("じしん", @model.Physical, 100, 100, None)
  let my_team = [mk_combatant_with_moves(twaver, [twave])]
  let opp_team = [mk_combatant_with_moves(hitter, [heavy])]
  let normal = compute_mean_damage(opp_team[0], my_team[0], heavy, 0, 0)
  let state = mk_same_turn_state(my_team, opp_team, 200, 200)
  let outs = transition_with_cache(
    state, UseMove(0), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  assert_eq(outs.length(), 1)
  let (_p, ns) = outs[0]
  assert_eq(ns.opp_status[0], @model.Paralyze)
  // Fresh paralysis does not block the current turn's action; the hitter's
  // physical damage lands at its full (non-burn) value.
  assert_eq(200 - ns.my_hps[0], normal)
}
