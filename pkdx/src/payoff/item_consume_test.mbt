///|
/// Whitebox tests for apply_item_pre_damage_proc_fanout and
/// apply_item_post_damage_proc_fanout (issue #97 / P5).
///
/// Step 0 Red Phase: tests reference identifiers that do not yet exist:
///   - SwitchingGameState.{my,opp}_item_consumed (T3)
///   - apply_item_pre_damage_proc_fanout (T5, resist berry post-damage refund)
///   - apply_item_post_damage_proc_fanout (T4, きあいのタスキ / フィラのみ)
/// Compile will fail until those land. Tests are then expected to pass.

///|
fn ic_pokemon(name : String, type1 : String, type2 : String) -> @model.Pokemon {
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
fn ic_combatant(
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
fn ic_state(
  my_hps~ : Array[Int] = [200, 200, 200],
  opp_hps~ : Array[Int] = [200, 200, 200],
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
    my_megaed: [false, false, false],
    opp_megaed: [false, false, false],
    my_status: [@model.None, @model.None, @model.None],
    opp_status: [@model.None, @model.None, @model.None],
    my_must_recharge: [false, false, false],
    opp_must_recharge: [false, false, false],
    my_item_consumed: [false, false, false],
    opp_item_consumed: [false, false, false],
    turn: 0,
  }
}

///|
fn ic_move(name : String, type_ : String) -> @model.Move {
  {
    name,
    type_,
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

// ─── resist berry: オッカのみ (ほのお type halve on SE) ─────────────────────

///|
test "resist_berry: オッカのみ vs ほのお SE → consume (HP unchanged)" {
  // defender: くさ type, holds オッカのみ. Attacker: ほのお SE move.
  // The damage engine has already halved the SE hit, so `state.opp_hps[0]`
  // reflects the post-halving HP. The fanout's job is only to flip
  // opp_item_consumed[0] = true so a follow-up hit doesn't get halved a
  // second time (engine wiring lives in T7 follow-up).
  let defender = ic_combatant(ic_pokemon("d", "くさ", ""), item="オッカのみ")
  let attacker = ic_combatant(ic_pokemon("a", "ほのお", ""))
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let post_dmg_state = ic_state(opp_hps=[150, 200, 200])
  let pre_dmg_hp = 200
  let mv = ic_move("ひのこ", "ほのお")
  let outcomes = apply_item_pre_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, attacker_team, pre_dmg_hp, mv,
  )
  inspect(outcomes.length(), content="1")
  let (p, s) = outcomes[0]
  let drift = if p > 1.0 { p - 1.0 } else { 1.0 - p }
  inspect(drift < 1.0e-9, content="true")
  inspect(s.opp_hps[0], content="150")
  inspect(s.opp_item_consumed[0], content="true")
}

///|
test "resist_berry: オッカのみ vs ほのお non-SE (くさ resists) → no trigger" {
  // ノーマル type defender takes ほのお neutral hit; berry only triggers on SE.
  let defender = ic_combatant(ic_pokemon("d", "ノーマル", ""), item="オッカのみ")
  let attacker = ic_combatant(ic_pokemon("a", "ほのお", ""))
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let post_dmg_state = ic_state(opp_hps=[100, 200, 200])
  let mv = ic_move("ひのこ", "ほのお")
  let outcomes = apply_item_pre_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, attacker_team, 200, mv,
  )
  inspect(outcomes.length(), content="1")
  let (_, s) = outcomes[0]
  inspect(s.opp_hps[0], content="100")
  inspect(s.opp_item_consumed[0], content="false")
}

///|
test "resist_berry: オッカのみ already consumed → no refund" {
  let defender = ic_combatant(ic_pokemon("d", "くさ", ""), item="オッカのみ")
  let attacker = ic_combatant(ic_pokemon("a", "ほのお", ""))
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mut state = ic_state(opp_hps=[100, 200, 200])
  state = { ..state, opp_item_consumed: [true, false, false] }
  let mv = ic_move("ひのこ", "ほのお")
  let outcomes = apply_item_pre_damage_proc_fanout(
    state, false, 0, defender_team, attacker_team, 200, mv,
  )
  inspect(outcomes.length(), content="1")
  let (_, s) = outcomes[0]
  inspect(s.opp_hps[0], content="100")
}

///|
test "resist_berry: defender holds no resist berry → no trigger" {
  let defender = ic_combatant(ic_pokemon("d", "くさ", ""))
  let attacker = ic_combatant(ic_pokemon("a", "ほのお", ""))
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let post_dmg_state = ic_state(opp_hps=[100, 200, 200])
  let mv = ic_move("ひのこ", "ほのお")
  let outcomes = apply_item_pre_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, attacker_team, 200, mv,
  )
  inspect(outcomes.length(), content="1")
  let (_, s) = outcomes[0]
  inspect(s.opp_hps[0], content="100")
}

// ─── consume_on_hit: きあいのタスキ ──────────────────────────────────────

///|
test "focus_sash: full HP → KO 級 → HP=1 + consume" {
  // Defender at full HP 200. OHKO-level hit reduces HP to 0.
  // Sash should kick in: HP=1, consumed.
  let defender = ic_combatant(ic_pokemon("d", "ノーマル", ""), item="きあいのタスキ")
  let defender_team = [defender, defender, defender]
  let post_dmg_state = ic_state(opp_hps=[0, 200, 200])
  let pre_dmg_hp = 200
  let mv = ic_move("はかいこうせん", "ノーマル")
  let outcomes = apply_item_post_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, pre_dmg_hp, mv,
  )
  inspect(outcomes.length(), content="1")
  let (_, s) = outcomes[0]
  inspect(s.opp_hps[0], content="1")
  inspect(s.opp_item_consumed[0], content="true")
}

///|
test "focus_sash: not at full HP → no trigger (still KO)" {
  // Defender at 150/200. KO hit: no sash because pre_hit wasn't full.
  let defender = ic_combatant(ic_pokemon("d", "ノーマル", ""), item="きあいのタスキ")
  let defender_team = [defender, defender, defender]
  let post_dmg_state = ic_state(opp_hps=[0, 200, 200])
  let pre_dmg_hp = 150
  let mv = ic_move("はかいこうせん", "ノーマル")
  let outcomes = apply_item_post_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, pre_dmg_hp, mv,
  )
  inspect(outcomes.length(), content="1")
  let (_, s) = outcomes[0]
  inspect(s.opp_hps[0], content="0")
  inspect(s.opp_item_consumed[0], content="false")
}

///|
test "focus_sash: already consumed → no trigger" {
  let defender = ic_combatant(ic_pokemon("d", "ノーマル", ""), item="きあいのタスキ")
  let defender_team = [defender, defender, defender]
  let mut state = ic_state(opp_hps=[0, 200, 200])
  state = { ..state, opp_item_consumed: [true, false, false] }
  let mv = ic_move("はかいこうせん", "ノーマル")
  let outcomes = apply_item_post_damage_proc_fanout(
    state, false, 0, defender_team, 200, mv,
  )
  inspect(outcomes.length(), content="1")
  let (_, s) = outcomes[0]
  inspect(s.opp_hps[0], content="0")
}

// ─── hp_threshold: フィラのみ ──────────────────────────────────────────────

///|
test "fila_berry: post HP <= max/2 → +max/3 heal + consume" {
  // Defender max=200, pre=120 → post=80 (which is <= 100 = max/2).
  // Heal: 80 + 200/3 = 80 + 66 = 146.
  let defender = ic_combatant(ic_pokemon("d", "ノーマル", ""), item="フィラのみ")
  let defender_team = [defender, defender, defender]
  let post_dmg_state = ic_state(opp_hps=[80, 200, 200])
  let pre_dmg_hp = 120
  let mv = ic_move("たいあたり", "ノーマル")
  let outcomes = apply_item_post_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, pre_dmg_hp, mv,
  )
  inspect(outcomes.length(), content="1")
  let (_, s) = outcomes[0]
  inspect(s.opp_hps[0], content="146")
  inspect(s.opp_item_consumed[0], content="true")
}

///|
test "fila_berry: post HP > max/2 → no trigger" {
  // Defender max=200, post=120 (above 100 threshold). No heal.
  let defender = ic_combatant(ic_pokemon("d", "ノーマル", ""), item="フィラのみ")
  let defender_team = [defender, defender, defender]
  let post_dmg_state = ic_state(opp_hps=[120, 200, 200])
  let mv = ic_move("たいあたり", "ノーマル")
  let outcomes = apply_item_post_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, 180, mv,
  )
  inspect(outcomes.length(), content="1")
  let (_, s) = outcomes[0]
  inspect(s.opp_hps[0], content="120")
  inspect(s.opp_item_consumed[0], content="false")
}

///|
test "fila_berry: KO hit (HP=0) → no trigger" {
  // Healing berries don't revive. HP reaches 0 first → no heal.
  let defender = ic_combatant(ic_pokemon("d", "ノーマル", ""), item="フィラのみ")
  let defender_team = [defender, defender, defender]
  let post_dmg_state = ic_state(opp_hps=[0, 200, 200])
  let mv = ic_move("はかいこうせん", "ノーマル")
  let outcomes = apply_item_post_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, 200, mv,
  )
  inspect(outcomes.length(), content="1")
  let (_, s) = outcomes[0]
  inspect(s.opp_hps[0], content="0")
  inspect(s.opp_item_consumed[0], content="false")
}

// ─── probability mass conservation ─────────────────────────────────────────

///|
test "probability mass: pre + post fanouts both sum to 1.0" {
  // Both helpers must always return Σp ≈ 1.0 (currently single-leaf, but the
  // invariant must hold under future probabilistic extensions).
  let defender = ic_combatant(ic_pokemon("d", "くさ", ""), item="オッカのみ")
  let attacker = ic_combatant(ic_pokemon("a", "ほのお", ""))
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let post_dmg_state = ic_state(opp_hps=[100, 200, 200])
  let mv = ic_move("ひのこ", "ほのお")
  let pre_outs = apply_item_pre_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, attacker_team, 200, mv,
  )
  let mut pre_sum = 0.0
  for i = 0; i < pre_outs.length(); i = i + 1 {
    pre_sum = pre_sum + pre_outs[i].0
  }
  let pre_drift = if pre_sum > 1.0 { pre_sum - 1.0 } else { 1.0 - pre_sum }
  inspect(pre_drift < 1.0e-9, content="true")
  let post_outs = apply_item_post_damage_proc_fanout(
    post_dmg_state, false, 0, defender_team, 200, mv,
  )
  let mut post_sum = 0.0
  for i = 0; i < post_outs.length(); i = i + 1 {
    post_sum = post_sum + post_outs[i].0
  }
  let post_drift = if post_sum > 1.0 { post_sum - 1.0 } else { 1.0 - post_sum }
  inspect(post_drift < 1.0e-9, content="true")
}
