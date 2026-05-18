///|
/// Priority-aware, rank-aware turn order sign between the two actives for the
/// given moves. Returns `+1` if my active acts first, `-1` if opp acts first,
/// `0` on full ties. Reads priority directly from `@model.Move.priority`
/// (populated by `query_moves` via the `move_meta` DB JOIN).
///
/// When either side is currently running on mega-form stats (`me_mega` /
/// `opp_mega`), the post-mega speed base is used for the tie-breaker. Priority
/// is never affected by mega evolution, so it reads straight from the move.
fn move_turn_sign(
  me : Combatant,
  me_ranks : Array[Int],
  mv_me : @model.Move,
  me_mega : Bool,
  me_para : Bool,
  opp : Combatant,
  opp_ranks : Array[Int],
  mv_opp : @model.Move,
  opp_mega : Bool,
  opp_para : Bool,
) -> Int {
  let me_eff = effective_combatant(me, me_mega)
  let opp_eff = effective_combatant(opp, opp_mega)
  let base_me = effective_speed(me_eff.pokemon.spe, me_ranks[4])
  let base_opp = effective_speed(opp_eff.pokemon.spe, opp_ranks[4])
  // まひは最終素早さを 1/2 (gen7+ ルール)。ランク補正と重複して反映。
  let eff_me = if me_para { base_me / 2 } else { base_me }
  let eff_opp = if opp_para { base_opp / 2 } else { base_opp }
  turn_order_sign(
    me_eff, mv_me.priority, eff_me, opp_eff, mv_opp.priority, eff_opp,
  )
}

///|
/// Does a status condition that was freshly inflicted on the second actor this
/// turn prevent them from executing their move? Canonical rule: a Pokemon put
/// to sleep mid-turn cannot act on the turn the sleep lands. Fresh burn,
/// poison, and paralysis do not skip the current action (burn only re-shapes
/// damage; paralysis speed halving is moot since action order is already
/// decided, and the fully-paralyzed roll is a pre-turn attempt that was
/// already resolved).
fn action_blocked_by_fresh_status(
  pre : @model.StatusCondition,
  now : @model.StatusCondition,
) -> Bool {
  match (pre, now) {
    (@model.None, @model.Sleep(_)) => true
    _ => false
  }
}

///|
/// Snapshot of the mutable per-turn buffers handed off between the first and
/// second attacker. All arrays are defensively copied on entry; callers treat
/// `advance_turn` as the only way to freeze this snapshot into a `SwitchingGameState`.
priv struct TurnWorkspace {
  my_active : Int
  opp_active : Int
  my_hps : Array[Int]
  opp_hps : Array[Int]
  my_ranks : Array[Int]
  opp_ranks : Array[Int]
  my_megaed : Array[Bool]
  opp_megaed : Array[Bool]
  my_mega_used : Bool
  opp_mega_used : Bool
  my_status : Array[@model.StatusCondition]
  opp_status : Array[@model.StatusCondition]
  my_must_recharge : Array[Bool]
  opp_must_recharge : Array[Bool]
  my_item_consumed : Array[Bool]
  opp_item_consumed : Array[Bool]
  my_moves_used : Array[Int]
  opp_moves_used : Array[Int]
  turn : Int
}

///|
fn ws_from_state(state : SwitchingGameState) -> TurnWorkspace {
  {
    my_active: state.my_active,
    opp_active: state.opp_active,
    my_hps: state.my_hps.copy(),
    opp_hps: state.opp_hps.copy(),
    my_ranks: state.my_ranks.copy(),
    opp_ranks: state.opp_ranks.copy(),
    my_megaed: state.my_megaed.copy(),
    opp_megaed: state.opp_megaed.copy(),
    my_mega_used: state.my_mega_used,
    opp_mega_used: state.opp_mega_used,
    my_status: state.my_status.copy(),
    opp_status: state.opp_status.copy(),
    my_must_recharge: state.my_must_recharge.copy(),
    opp_must_recharge: state.opp_must_recharge.copy(),
    my_item_consumed: state.my_item_consumed.copy(),
    opp_item_consumed: state.opp_item_consumed.copy(),
    my_moves_used: state.my_moves_used.copy(),
    opp_moves_used: state.opp_moves_used.copy(),
    turn: state.turn,
  }
}

///|
fn ws_to_state(ws : TurnWorkspace, bump_turn~ : Bool) -> SwitchingGameState {
  {
    my_active: ws.my_active,
    opp_active: ws.opp_active,
    my_hps: ws.my_hps.copy(),
    opp_hps: ws.opp_hps.copy(),
    my_ranks: ws.my_ranks.copy(),
    opp_ranks: ws.opp_ranks.copy(),
    my_mega_used: ws.my_mega_used,
    opp_mega_used: ws.opp_mega_used,
    my_megaed: ws.my_megaed.copy(),
    opp_megaed: ws.opp_megaed.copy(),
    my_status: ws.my_status.copy(),
    opp_status: ws.opp_status.copy(),
    my_must_recharge: ws.my_must_recharge.copy(),
    opp_must_recharge: ws.opp_must_recharge.copy(),
    my_item_consumed: ws.my_item_consumed.copy(),
    opp_item_consumed: ws.opp_item_consumed.copy(),
    my_moves_used: ws.my_moves_used.copy(),
    opp_moves_used: ws.opp_moves_used.copy(),
    turn: if bump_turn { ws.turn + 1 } else { ws.turn },
  }
}

///|
/// Resolve one attacker's move leg: apply damage, update ranks, fan out the
/// attacker's status effect onto the target. Mutates the caller's workspace
/// for damage / rank changes but produces the status branches as new states
/// (turn unchanged — caller advances the turn when finalising).
fn resolve_attacker_leg(
  ws : TurnWorkspace,
  attacker_is_me : Bool,
  attacker_move : @model.Move,
  attacker_mv_idx : Int,
  attacker_mega_now : Bool,
  defender_mega_now : Bool,
  attacker_burn : Bool,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
) -> Array[(Double, SwitchingGameState)] {
  // Phase 2-E (#91): damage application + post-hit effects + 4 fanout は
  // apply_damage_variants_fanout に統合され、variant ごとに chance-node leaf
  // を生成する。workspace は damage 適用前の状態で state にスナップショット
  // する (apply_damage_variants_fanout が per-variant に HP/recoil を扱う)。
  let attacker_active = if attacker_is_me { ws.my_active } else { ws.opp_active }
  let defender_active = if attacker_is_me { ws.opp_active } else { ws.my_active }
  let attacker_ranks = if attacker_is_me { ws.my_ranks } else { ws.opp_ranks }
  let defender_ranks = if attacker_is_me { ws.opp_ranks } else { ws.my_ranks }
  let defender_hps = if attacker_is_me { ws.opp_hps } else { ws.my_hps }
  let atk_consumed_arr = if attacker_is_me { ws.my_item_consumed } else { ws.opp_item_consumed }
  let def_consumed_arr = if attacker_is_me { ws.opp_item_consumed } else { ws.my_item_consumed }
  let atk_consumed = if attacker_active < atk_consumed_arr.length() {
    atk_consumed_arr[attacker_active]
  } else {
    false
  }
  let def_consumed = if defender_active < def_consumed_arr.length() {
    def_consumed_arr[defender_active]
  } else {
    false
  }
  let pre_dmg_defender_hp = defender_hps[defender_active]
  let pre_damage_state = ws_to_state(ws, bump_turn=false)
  let attacker_team = if attacker_is_me { my_team } else { opp_team }
  let defender_team_eff = if attacker_is_me { opp_team } else { my_team }
  let outcomes = damage_variants_cached(
    dmg_cache,
    attacker_is_me,
    attacker_active,
    attacker_ranks,
    defender_active,
    defender_ranks,
    attacker_mv_idx,
    my_team,
    opp_team,
    atk_mega=attacker_mega_now,
    def_mega=defender_mega_now,
    atk_burn=attacker_burn,
    atk_item_consumed=atk_consumed,
    def_item_consumed=def_consumed,
  )
  apply_damage_variants_fanout(
    pre_damage_state,
    outcomes,
    attacker_is_me=attacker_is_me,
    attacker_active=attacker_active,
    defender_active=defender_active,
    attacker_move=attacker_move,
    attacker_team=attacker_team,
    defender_team=defender_team_eff,
    pre_dmg_defender_hp=pre_dmg_defender_hp,
  )
}

///|
/// Resolve a turn where both sides use a move, with proper damage recomputation
/// after the first actor's stat boosts. `my_first` determines action order.
///
/// Status effects inflicted by the faster attacker are applied **before** the
/// slower attacker's move resolves, so same-turn effects are honoured:
/// - A faster Will-O-Wisp halves the slower target's physical attack on the
///   same turn (the second-leg damage calc reads the post-fanout burn flag).
/// - A faster Spore / Hypnosis prevents the slower target from acting on the
///   turn the sleep lands.
///
/// `my_mega_now` / `opp_mega_now` capture whether each side is **currently
/// running on mega stats** this turn. This is the union of "was already megaed
/// going into the turn" and "chose a Mega action this turn". Mega state is
/// carried on the returned state via `my_megaed` / `opp_megaed`, with the
/// side-level `*_mega_used` flag handled upstream in `transition_with_cache`.
fn resolve_moves(
  state : SwitchingGameState,
  mi : Int,
  mj : Int,
  my_first : Bool,
  my_mega_now : Bool,
  opp_mega_now : Bool,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
) -> Array[(Double, SwitchingGameState)] {
  let ws = ws_from_state(state)
  if my_mega_now {
    ws.my_megaed[state.my_active] = true
  }
  if opp_mega_now {
    ws.opp_megaed[state.opp_active] = true
  }
  let ws : TurnWorkspace = {
    ..ws,
    my_mega_used: ws.my_mega_used || my_mega_now,
    opp_mega_used: ws.opp_mega_used || opp_mega_now,
  }
  let mv_me = my_team[state.my_active].moves[mi]
  let mv_opp = opp_team[state.opp_active].moves[mj]
  let pre_my_burn = is_burned(state.my_status[state.my_active])
  let pre_opp_burn = is_burned(state.opp_status[state.opp_active])
  let (
    first_is_me,
    first_move,
    first_mv_idx,
    first_pre_burn,
    first_mega_now,
    first_def_mega_now,
    second_is_me,
    second_move,
    second_mv_idx,
    second_mega_now,
    second_def_mega_now,
  ) = if my_first {
    (
      true,
      mv_me,
      mi,
      pre_my_burn,
      my_mega_now,
      opp_mega_now,
      false,
      mv_opp,
      mj,
      opp_mega_now,
      my_mega_now,
    )
  } else {
    (
      false,
      mv_opp,
      mj,
      pre_opp_burn,
      opp_mega_now,
      my_mega_now,
      true,
      mv_me,
      mi,
      my_mega_now,
      opp_mega_now,
    )
  }
  let second_pre_status = if second_is_me {
    state.my_status[state.my_active]
  } else {
    state.opp_status[state.opp_active]
  }
  // Step 1: first attacker acts. Damage + stat boost applied, then the
  // attacker's status move (if any) fans out onto the second actor.
  let after_first = resolve_attacker_leg(
    ws,
    first_is_me,
    first_move,
    first_mv_idx,
    first_mega_now,
    first_def_mega_now,
    first_pre_burn,
    my_team,
    opp_team,
    dmg_cache,
  )
  // Step 2: for each branch, resolve the second attacker with the potentially
  // updated status (fresh burn halves their physical damage; fresh sleep
  // locks them out entirely).
  let final_outs : Array[(Double, SwitchingGameState)] = []
  for b in after_first {
    let (p1, s1) = b
    let second_attacker_active = if second_is_me {
      s1.my_active
    } else {
      s1.opp_active
    }
    let second_attacker_hps = if second_is_me { s1.my_hps } else { s1.opp_hps }
    let second_now_status = if second_is_me {
      s1.my_status[second_attacker_active]
    } else {
      s1.opp_status[second_attacker_active]
    }
    // Second actor KO'd by first attacker's hit: no second leg, just advance.
    if second_attacker_hps[second_attacker_active] <= 0 {
      final_outs.push((p1, clone_state(s1, 1)))
      continue
    }
    // Second actor newly slept / frozen mid-turn: skip their move.
    if action_blocked_by_fresh_status(second_pre_status, second_now_status) {
      final_outs.push((p1, clone_state(s1, 1)))
      continue
    }
    let second_burn = is_burned(second_now_status)
    let ws2 = ws_from_state(s1)
    let after_second = resolve_attacker_leg(
      ws2,
      second_is_me,
      second_move,
      second_mv_idx,
      second_mega_now,
      second_def_mega_now,
      second_burn,
      my_team,
      opp_team,
      dmg_cache,
    )
    for x in after_second {
      let (p2, s2) = x
      final_outs.push((p1 * p2, clone_state(s2, 1)))
    }
  }
  final_outs
}

///|
/// Return a fresh copy of `state` with `turn` shifted by `turn_delta`. Used
/// at the tail of `resolve_moves` to advance the turn counter once both
/// attacker legs are fully resolved (turn_delta=1), and elsewhere when a
/// pristine deep copy is needed (turn_delta=0).
fn clone_state(
  state : SwitchingGameState,
  turn_delta : Int,
) -> SwitchingGameState {
  {
    my_active: state.my_active,
    opp_active: state.opp_active,
    my_hps: state.my_hps.copy(),
    opp_hps: state.opp_hps.copy(),
    my_ranks: state.my_ranks.copy(),
    opp_ranks: state.opp_ranks.copy(),
    my_mega_used: state.my_mega_used,
    opp_mega_used: state.opp_mega_used,
    my_megaed: state.my_megaed.copy(),
    opp_megaed: state.opp_megaed.copy(),
    my_status: state.my_status.copy(),
    opp_status: state.opp_status.copy(),
    my_must_recharge: state.my_must_recharge.copy(),
    opp_must_recharge: state.opp_must_recharge.copy(),
    my_item_consumed: state.my_item_consumed.copy(),
    opp_item_consumed: state.opp_item_consumed.copy(),
    my_moves_used: state.my_moves_used.copy(),
    opp_moves_used: state.opp_moves_used.copy(),
    turn: state.turn + turn_delta,
  }
}

///|
/// Convenience: pick the active slot on the side indicated by `is_me`.
pub fn target_active(state : SwitchingGameState, is_me : Bool) -> Int {
  if is_me { state.my_active } else { state.opp_active }
}

///|
/// Apply one game step to `state` given both players' actions, using
/// `dmg_cache` to memoize the 16-roll damage computations. Damage is applied
/// in action-order (priority → effective speed; first KO skips the slower
/// side's attack), switches reset the switcher's ranks, stat-boost moves
/// update the user's ranks. Always advances `turn` by 1.
///
/// Returns an array of `(probability, next_state)` pairs. For most actions
/// there is exactly one outcome with probability 1.0. Speed ties produce two
/// outcomes each with probability 0.5 so that the caller can average successor
/// *values* rather than successor *states* (Jensen's inequality).
pub fn transition_with_cache(
  state : SwitchingGameState,
  my_action : ActionKind,
  opp_action : ActionKind,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
) -> Array[(Double, SwitchingGameState)] {
  // Normalise `Mega(mi)` into `UseMove(mi)` plus a same-turn mega trigger.
  // This keeps the existing per-pair arms minimal and funnels every damage
  // call through the `resolve_moves` helper, which is already rank-aware.
  let (my_core, my_mega_trigger) = normalize_action(my_action)
  let (opp_core, opp_mega_trigger) = normalize_action(opp_action)
  // "Currently running on mega stats" for this resolution = already megaed
  // going into the turn OR triggered now.
  let my_mega_now = state.my_megaed[state.my_active] || my_mega_trigger
  let opp_mega_now = state.opp_megaed[state.opp_active] || opp_mega_trigger
  let my_hps_new = state.my_hps.copy()
  let opp_hps_new = state.opp_hps.copy()
  let my_ranks_new = state.my_ranks.copy()
  let opp_ranks_new = state.opp_ranks.copy()
  let my_megaed_new = state.my_megaed.copy()
  let opp_megaed_new = state.opp_megaed.copy()
  let my_status_new = state.my_status.copy()
  let opp_status_new = state.opp_status.copy()
  let my_must_recharge_new = state.my_must_recharge.copy()
  let opp_must_recharge_new = state.opp_must_recharge.copy()
  let my_item_consumed_new = state.my_item_consumed.copy()
  let opp_item_consumed_new = state.opp_item_consumed.copy()
  let my_moves_used_new = state.my_moves_used.copy()
  let opp_moves_used_new = state.opp_moves_used.copy()
  if my_mega_trigger {
    my_megaed_new[state.my_active] = true
  }
  if opp_mega_trigger {
    opp_megaed_new[state.opp_active] = true
  }
  let my_mega_used_new = state.my_mega_used || my_mega_trigger
  let opp_mega_used_new = state.opp_mega_used || opp_mega_trigger
  let mut my_active_new = state.my_active
  let mut opp_active_new = state.opp_active
  // Track a single attack event for status fan-out after the state is built.
  // Set to `Some((attacker_is_me, target_slot, used_move))` in the two
  // Switch+UseMove arms; None for pure-Switch / pure-UseMove handled below.
  // Phase 2-E (#91): payload extended to (attacker_is_me, target_slot,
  // used_move, mv_idx) so the Some(...) arm can call damage_variants_cached
  // with the attacker move's index.
  let mut attack_event : (Bool, Int, @model.Move, Int)? = None
  // P5 (#97): defender HP just before damage application — captured at the
  // damage sites so apply_item_pre/post_damage_proc_fanout can reconstruct
  // the dealt damage (= pre - post) and gate full-HP triggers (きあいのタスキ).
  let mut pre_dmg_defender_hp : Int = 0
  match (my_core, opp_core) {
    (Switch(i), Switch(j)) => {
      my_active_new = i
      opp_active_new = j
      // Ranks reset on switch-in. Mega state is slot-scoped so it survives.
      for k in 0..<5 {
        my_ranks_new[k] = 0
        opp_ranks_new[k] = 0
      }
      my_status_new[state.my_active] = reset_toxic_counter_on_switch(
        my_status_new[state.my_active],
      )
      opp_status_new[state.opp_active] = reset_toxic_counter_on_switch(
        opp_status_new[state.opp_active],
      )
    }
    (Switch(i), UseMove(mj)) => {
      my_active_new = i
      for k in 0..<5 {
        my_ranks_new[k] = 0
      }
      my_status_new[state.my_active] = reset_toxic_counter_on_switch(
        my_status_new[state.my_active],
      )
      // Phase 2-E (#91): damage application + post-hit effects + 4 fanout
      // are deferred to apply_damage_variants_fanout in the Some(...) arm
      // below, which fans the chance-node leaves across hit-count variants.
      // Only the pre-damage HP snapshot survives in the local mut so the
      // post-hit fanouts can gate full-HP triggers (resist berry / sash).
      pre_dmg_defender_hp = my_hps_new[i]
      attack_event = Some((false, i, opp_team[state.opp_active].moves[mj], mj))
      // Last Resort 解禁判定用に opp が選択した move を「使用済み」として記録。
      mark_move_used_inplace(opp_moves_used_new, state.opp_active, mj)
    }
    (UseMove(mi), Switch(j)) => {
      opp_active_new = j
      for k in 0..<5 {
        opp_ranks_new[k] = 0
      }
      opp_status_new[state.opp_active] = reset_toxic_counter_on_switch(
        opp_status_new[state.opp_active],
      )
      // Phase 2-E (#91): see (Switch, UseMove) for rationale — damage and
      // post-hit effects are handled per-variant in the Some(...) arm.
      pre_dmg_defender_hp = opp_hps_new[j]
      attack_event = Some((true, j, my_team[state.my_active].moves[mi], mi))
      // Last Resort 解禁判定用に my が選択した move を「使用済み」として記録。
      mark_move_used_inplace(my_moves_used_new, state.my_active, mi)
    }
    (UseMove(mi), UseMove(mj)) => {
      let me = my_team[state.my_active]
      let opp = opp_team[state.opp_active]
      let mv_me = me.moves[mi]
      let mv_opp = opp.moves[mj]
      let my_para = is_paralyzed(state.my_status[state.my_active])
      let opp_para = is_paralyzed(state.opp_status[state.opp_active])
      let s = move_turn_sign(
        me, my_ranks_new, mv_me, my_mega_now, my_para,
        opp, opp_ranks_new, mv_opp, opp_mega_now, opp_para,
      )
      // Last Resort 解禁判定用に両サイドの move を「使用済み」として記録。
      // resolve_moves は state を ws に変換して回すので、state を新しい mask で
      // 上書きしてから渡す。
      let state_marked : SwitchingGameState = {
        ..state,
        my_moves_used: mark_move_used(state.my_moves_used, state.my_active, mi),
        opp_moves_used: mark_move_used(state.opp_moves_used, state.opp_active, mj),
      }
      if s == 0 {
        // Speed tie: return two outcomes so the caller averages successor
        // *values* (not states). resolve_moves recomputes the second hit's
        // damage after the first actor's stat boosts.
        let outs : Array[(Double, SwitchingGameState)] = []
        for half in resolve_moves(
          state_marked, mi, mj, true, my_mega_now, opp_mega_now,
          my_team, opp_team, dmg_cache,
        ) {
          outs.push((0.5 * half.0, half.1))
        }
        for half in resolve_moves(
          state_marked, mi, mj, false, my_mega_now, opp_mega_now,
          my_team, opp_team, dmg_cache,
        ) {
          outs.push((0.5 * half.0, half.1))
        }
        return outs
      } else {
        let my_first = s > 0
        return resolve_moves(
          state_marked, mi, mj, my_first, my_mega_now, opp_mega_now,
          my_team, opp_team, dmg_cache,
        )
      }
    }
    // Switch-variants are the only non-UseMove pairs that reach this point;
    // `Mega` is already normalised away, and a pair-of-Switch is handled above.
    // Any remaining arm is unreachable — treat as a no-op turn advance.
    (_, _) => ()
  }
  let base_state : SwitchingGameState = {
    my_active: my_active_new,
    opp_active: opp_active_new,
    my_hps: my_hps_new,
    opp_hps: opp_hps_new,
    my_ranks: my_ranks_new,
    opp_ranks: opp_ranks_new,
    my_mega_used: my_mega_used_new,
    opp_mega_used: opp_mega_used_new,
    my_megaed: my_megaed_new,
    opp_megaed: opp_megaed_new,
    my_status: my_status_new,
    opp_status: opp_status_new,
    my_must_recharge: my_must_recharge_new,
    opp_must_recharge: opp_must_recharge_new,
    my_item_consumed: my_item_consumed_new,
    opp_item_consumed: opp_item_consumed_new,
    my_moves_used: my_moves_used_new,
    opp_moves_used: opp_moves_used_new,
    turn: state.turn + 1,
  }
  match attack_event {
    None => [(1.0, base_state)]
    Some((attacker_is_me, target_slot, used_move, mv_idx)) => {
      let attacker_slot = target_active(base_state, attacker_is_me)
      let attacker_ranks = if attacker_is_me {
        base_state.my_ranks
      } else {
        base_state.opp_ranks
      }
      let defender_ranks = if attacker_is_me {
        base_state.opp_ranks
      } else {
        base_state.my_ranks
      }
      let attacker_team = if attacker_is_me { my_team } else { opp_team }
      let defender_team_eff = if attacker_is_me { opp_team } else { my_team }
      let attacker_mega = if attacker_is_me { my_mega_now } else { opp_mega_now }
      let defender_mega = if attacker_is_me {
        base_state.opp_megaed[target_slot]
      } else {
        base_state.my_megaed[target_slot]
      }
      let attacker_burn = if attacker_is_me {
        is_burned(state.my_status[state.my_active])
      } else {
        is_burned(state.opp_status[state.opp_active])
      }
      let atk_item_consumed = if attacker_is_me {
        base_state.my_item_consumed[state.my_active]
      } else {
        base_state.opp_item_consumed[state.opp_active]
      }
      let def_item_consumed = if attacker_is_me {
        if target_slot < base_state.opp_item_consumed.length() {
          base_state.opp_item_consumed[target_slot]
        } else {
          false
        }
      } else if target_slot < base_state.my_item_consumed.length() {
        base_state.my_item_consumed[target_slot]
      } else {
        false
      }
      let outcomes = damage_variants_cached(
        dmg_cache,
        attacker_is_me,
        attacker_slot,
        attacker_ranks,
        target_slot,
        defender_ranks,
        mv_idx,
        my_team,
        opp_team,
        atk_mega=attacker_mega,
        def_mega=defender_mega,
        atk_burn=attacker_burn,
        atk_item_consumed=atk_item_consumed,
        def_item_consumed=def_item_consumed,
      )
      apply_damage_variants_fanout(
        base_state,
        outcomes,
        attacker_is_me=attacker_is_me,
        attacker_active=attacker_slot,
        defender_active=target_slot,
        attacker_move=used_move,
        attacker_team=attacker_team,
        defender_team=defender_team_eff,
        pre_dmg_defender_hp=pre_dmg_defender_hp,
      )
    }
  }
}

///|
/// Normalise `Mega(mi)` into `(UseMove(mi), true)`; `UseMove(mi)` /
/// `Switch(i)` pass through with `false`. Keeps the main transition dispatch
/// minimal — same-turn mega is handled as "this side's attack runs on mega
/// stats" with a side-effect flag to flip `*_mega_used` / `*_megaed`.
fn normalize_action(a : ActionKind) -> (ActionKind, Bool) {
  match a {
    Mega(mi) => (UseMove(mi), true)
    other => (other, false)
  }
}

///|
/// Backwards-compatible wrapper around `transition_with_cache` that allocates
/// a fresh single-use `DamageCache`. Suitable for standalone calls (unit
/// tests, one-off transitions); inside a recursion prefer `transition_with_cache`
/// with a shared cache so repeated damage computations are memoized.
pub fn transition(
  state : SwitchingGameState,
  my_action : ActionKind,
  opp_action : ActionKind,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> SwitchingGameState {
  let outcomes = transition_with_cache(
    state, my_action, opp_action, my_team, opp_team, new_damage_cache(),
  )
  outcomes[0].1
}

///|
/// Look up an action's accuracy. Switch has no accuracy (returns 100).
/// `UseMove` / `Mega` read the move's accuracy from the active combatant.
fn action_accuracy(
  action : ActionKind,
  active : Int,
  team : Array[Combatant],
) -> Int {
  match action {
    Switch(_) => 100
    UseMove(mi) | Mega(mi) => team[active].moves[mi].accuracy
  }
}

///|
/// Apply a pre-turn status override to an active slot — used by
/// `attempt_turn_with_cache` to thread sleep-wake / sleep-tick / paralysis
/// through to the next state. Returns a fresh status array copy.
fn override_active_status(
  base : Array[@model.StatusCondition],
  active : Int,
  new_status : @model.StatusCondition,
) -> Array[@model.StatusCondition] {
  let out = base.copy()
  out[active] = new_status
  out
}

///|
/// Construct a no-op next state where neither side acted this turn (e.g. both
/// paralyzed-skip / sleep-skip / miss). Advances the turn counter, keeps HPs
/// / ranks / mega state intact, and only overrides the two active slots'
/// statuses to reflect any sleep-counter ticks or wake-ups.
fn pass_turn_state(
  state : SwitchingGameState,
  my_post_status : @model.StatusCondition,
  opp_post_status : @model.StatusCondition,
) -> SwitchingGameState {
  let my_status = override_active_status(
    state.my_status, state.my_active, my_post_status,
  )
  let opp_status = override_active_status(
    state.opp_status, state.opp_active, opp_post_status,
  )
  {
    my_active: state.my_active,
    opp_active: state.opp_active,
    my_hps: state.my_hps.copy(),
    opp_hps: state.opp_hps.copy(),
    my_ranks: state.my_ranks.copy(),
    opp_ranks: state.opp_ranks.copy(),
    my_mega_used: state.my_mega_used,
    opp_mega_used: state.opp_mega_used,
    my_megaed: state.my_megaed.copy(),
    opp_megaed: state.opp_megaed.copy(),
    my_status,
    opp_status,
    my_must_recharge: state.my_must_recharge.copy(),
    opp_must_recharge: state.opp_must_recharge.copy(),
    my_item_consumed: state.my_item_consumed.copy(),
    opp_item_consumed: state.opp_item_consumed.copy(),
    my_moves_used: state.my_moves_used.copy(),
    opp_moves_used: state.opp_moves_used.copy(),
    turn: state.turn + 1,
  }
}

///|
/// Entry point that composes `per_side_attempt` status-driven fan-out with
/// `transition_with_cache`. Returns a list of `(prob, next_state)` pairs
/// summing to 1.0 (modulo floating-point drift).
///
/// For outcomes where both sides act, the existing `transition_with_cache`
/// drives resolution (with pre-turn status overrides applied so burn / para
/// damage-calc helpers see the post-attempt status). For outcomes where one
/// or both sides skip, `pass_turn_state` / partial-execution arms build the
/// next state directly.
pub fn attempt_turn_with_cache(
  state : SwitchingGameState,
  my_action : ActionKind,
  opp_action : ActionKind,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
) -> Array[(Double, SwitchingGameState)] {
  let my_acc = action_accuracy(my_action, state.my_active, my_team)
  let opp_acc = action_accuracy(opp_action, state.opp_active, opp_team)
  let my_attempts = per_side_attempt(
    state.my_status[state.my_active],
    state.my_must_recharge[state.my_active],
    my_action,
    my_acc,
  )
  let opp_attempts = per_side_attempt(
    state.opp_status[state.opp_active],
    state.opp_must_recharge[state.opp_active],
    opp_action,
    opp_acc,
  )
  let results : Array[(Double, SwitchingGameState)] = []
  for ma in my_attempts {
    for oa in opp_attempts {
      let joint = ma.prob * oa.prob
      if joint <= 0.0 {
        continue
      }
      // Apply the attempt-phase status overrides to the active slots so
      // downstream damage / action-order logic reads the post-attempt status.
      let pre_state : SwitchingGameState = {
        my_active: state.my_active,
        opp_active: state.opp_active,
        my_hps: state.my_hps,
        opp_hps: state.opp_hps,
        my_ranks: state.my_ranks,
        opp_ranks: state.opp_ranks,
        my_mega_used: state.my_mega_used,
        opp_mega_used: state.opp_mega_used,
        my_megaed: state.my_megaed,
        opp_megaed: state.opp_megaed,
        my_status: override_active_status(
          state.my_status, state.my_active, ma.post_status,
        ),
        opp_status: override_active_status(
          state.opp_status, state.opp_active, oa.post_status,
        ),
        my_must_recharge: state.my_must_recharge,
        opp_must_recharge: state.opp_must_recharge,
        my_item_consumed: state.my_item_consumed,
        opp_item_consumed: state.opp_item_consumed,
        my_moves_used: state.my_moves_used,
        opp_moves_used: state.opp_moves_used,
        turn: state.turn,
      }
      let branch_outs : Array[(Double, SwitchingGameState)] = match (
        ma.acts, oa.acts,
      ) {
        (true, true) =>
          transition_with_cache(
            pre_state, ma.action, oa.action, my_team, opp_team, dmg_cache,
          )
        (true, false) =>
          partial_act_outcomes(
            pre_state, ma.action, true, my_team, opp_team, dmg_cache,
          )
        (false, true) =>
          partial_act_outcomes(
            pre_state, oa.action, false, my_team, opp_team, dmg_cache,
          )
        (false, false) =>
          [(1.0, pass_turn_state(pre_state, ma.post_status, oa.post_status))]
      }
      for s in branch_outs {
        let (p, ns_pre_eot) = s
        // Consume must_recharge **only for slots that had the flag set at
        // turn start** (they just paid their one-turn penalty). Slots that
        // gained the flag *this turn* via a recharge move (Hyper Beam etc.)
        // must keep it set so the penalty actually applies next turn.
        // Must run before apply_eot so caching / downstream logic never sees
        // a stale flag.
        let ns_recharge_cleared = clear_consumed_recharge(
          ns_pre_eot,
          state.my_active,
          state.my_must_recharge[state.my_active],
          state.opp_active,
          state.opp_must_recharge[state.opp_active],
        )
        let ns = apply_eot(ns_recharge_cleared, my_team, opp_team)
        results.push((joint * p, ns))
      }
    }
  }
  results
}

///|
/// Resolve a turn where only one side acts (the other skipped due to para /
/// sleep / miss). `me_is_actor = true` means `action` belongs to `my_team`
/// and `opp_team`'s active is idle; false mirrors. Returns probabilistic
/// outcomes (usually a single 1.0 pair).
fn partial_act_outcomes(
  state : SwitchingGameState,
  action : ActionKind,
  me_is_actor : Bool,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
) -> Array[(Double, SwitchingGameState)] {
  let (core, mega_trigger) = normalize_action(action)
  let my_status_copy = state.my_status.copy()
  let opp_status_copy = state.opp_status.copy()
  let my_hps = state.my_hps.copy()
  let opp_hps = state.opp_hps.copy()
  let my_ranks = state.my_ranks.copy()
  let opp_ranks = state.opp_ranks.copy()
  let my_megaed = state.my_megaed.copy()
  let opp_megaed = state.opp_megaed.copy()
  let my_must_recharge = state.my_must_recharge.copy()
  let opp_must_recharge = state.opp_must_recharge.copy()
  let my_item_consumed = state.my_item_consumed.copy()
  let opp_item_consumed = state.opp_item_consumed.copy()
  let my_moves_used = state.my_moves_used.copy()
  let opp_moves_used = state.opp_moves_used.copy()
  let mut my_active = state.my_active
  let mut opp_active = state.opp_active
  let mut my_mega_used = state.my_mega_used
  let mut opp_mega_used = state.opp_mega_used
  // Phase 2-E (#91): payload extended to (attacker_is_me, target_slot,
  // used_move, mv_idx) so the Some(...) arm can call damage_variants_cached
  // with the attacker move's index.
  let mut attack_event : (Bool, Int, @model.Move, Int)? = None
  // P5 (#97): pre-damage defender HP — see transition_with_cache for rationale.
  let mut pre_dmg_defender_hp : Int = 0
  match (me_is_actor, core) {
    (true, Switch(i)) => {
      my_active = i
      for k in 0..<5 {
        my_ranks[k] = 0
      }
      my_status_copy[state.my_active] = reset_toxic_counter_on_switch(
        my_status_copy[state.my_active],
      )
    }
    (false, Switch(j)) => {
      opp_active = j
      for k in 0..<5 {
        opp_ranks[k] = 0
      }
      opp_status_copy[state.opp_active] = reset_toxic_counter_on_switch(
        opp_status_copy[state.opp_active],
      )
    }
    (true, UseMove(mi)) => {
      if mega_trigger {
        my_megaed[state.my_active] = true
        my_mega_used = true
      }
      // Phase 2-E (#91): damage application + post-hit effects + 4 fanout
      // are handled per-variant in the Some(...) arm via
      // apply_damage_variants_fanout. Pre-damage HP is captured here so
      // resist-berry / sash gating can compare against full HP.
      pre_dmg_defender_hp = opp_hps[state.opp_active]
      attack_event = Some(
        (true, state.opp_active, my_team[state.my_active].moves[mi], mi),
      )
      mark_move_used_inplace(my_moves_used, state.my_active, mi)
    }
    (false, UseMove(mj)) => {
      if mega_trigger {
        opp_megaed[state.opp_active] = true
        opp_mega_used = true
      }
      // Phase 2-E (#91): see (true, UseMove) for rationale.
      pre_dmg_defender_hp = my_hps[state.my_active]
      attack_event = Some(
        (false, state.my_active, opp_team[state.opp_active].moves[mj], mj),
      )
      mark_move_used_inplace(opp_moves_used, state.opp_active, mj)
    }
    (_, _) => ()
  }
  let base_state : SwitchingGameState = {
    my_active,
    opp_active,
    my_hps,
    opp_hps,
    my_ranks,
    opp_ranks,
    my_mega_used,
    opp_mega_used,
    my_megaed,
    opp_megaed,
    my_status: my_status_copy,
    opp_status: opp_status_copy,
    my_must_recharge,
    opp_must_recharge,
    my_item_consumed,
    opp_item_consumed,
    my_moves_used,
    opp_moves_used,
    turn: state.turn + 1,
  }
  match attack_event {
    None => [(1.0, base_state)]
    Some((attacker_is_me, target_slot, used_move, mv_idx)) => {
      let attacker_slot = target_active(base_state, attacker_is_me)
      let attacker_ranks = if attacker_is_me {
        base_state.my_ranks
      } else {
        base_state.opp_ranks
      }
      let defender_ranks = if attacker_is_me {
        base_state.opp_ranks
      } else {
        base_state.my_ranks
      }
      let attacker_team = if attacker_is_me { my_team } else { opp_team }
      let defender_team_eff = if attacker_is_me { opp_team } else { my_team }
      let attacker_mega = if attacker_is_me {
        base_state.my_megaed[state.my_active]
      } else {
        base_state.opp_megaed[state.opp_active]
      }
      let defender_mega = if attacker_is_me {
        base_state.opp_megaed[target_slot]
      } else {
        base_state.my_megaed[target_slot]
      }
      let attacker_burn = if attacker_is_me {
        is_burned(state.my_status[state.my_active])
      } else {
        is_burned(state.opp_status[state.opp_active])
      }
      let atk_item_consumed = if attacker_is_me {
        base_state.my_item_consumed[state.my_active]
      } else {
        base_state.opp_item_consumed[state.opp_active]
      }
      let def_item_consumed = if attacker_is_me {
        if target_slot < base_state.opp_item_consumed.length() {
          base_state.opp_item_consumed[target_slot]
        } else {
          false
        }
      } else if target_slot < base_state.my_item_consumed.length() {
        base_state.my_item_consumed[target_slot]
      } else {
        false
      }
      let outcomes = damage_variants_cached(
        dmg_cache,
        attacker_is_me,
        attacker_slot,
        attacker_ranks,
        target_slot,
        defender_ranks,
        mv_idx,
        my_team,
        opp_team,
        atk_mega=attacker_mega,
        def_mega=defender_mega,
        atk_burn=attacker_burn,
        atk_item_consumed=atk_item_consumed,
        def_item_consumed=def_item_consumed,
      )
      apply_damage_variants_fanout(
        base_state,
        outcomes,
        attacker_is_me=attacker_is_me,
        attacker_active=attacker_slot,
        defender_active=target_slot,
        attacker_move=used_move,
        attacker_team=attacker_team,
        defender_team=defender_team_eff,
        pre_dmg_defender_hp=pre_dmg_defender_hp,
      )
    }
  }
}

///|
/// Consume the `must_recharge` flag for active slots that started the turn
/// with the flag set — their mandatory skip is now paid. Slots that gained
/// the flag *during* this turn (recharge-move hit landing) must keep it so
/// the penalty fires next turn. Called once per branch outcome in
/// `attempt_turn_with_cache`; returns a copy with the two flags cleared iff
/// the corresponding `*_start_was_recharging` flag was `true`.
fn clear_consumed_recharge(
  state : SwitchingGameState,
  my_start_active : Int,
  my_start_was_recharging : Bool,
  opp_start_active : Int,
  opp_start_was_recharging : Bool,
) -> SwitchingGameState {
  let my_mr = state.my_must_recharge.copy()
  let opp_mr = state.opp_must_recharge.copy()
  if my_start_was_recharging &&
    my_start_active >= 0 &&
    my_start_active < my_mr.length() {
    my_mr[my_start_active] = false
  }
  if opp_start_was_recharging &&
    opp_start_active >= 0 &&
    opp_start_active < opp_mr.length() {
    opp_mr[opp_start_active] = false
  }
  { ..state, my_must_recharge: my_mr, opp_must_recharge: opp_mr }
}

///|
/// Tolerance for the node-level pure-saddle early-exit in `value`. When the
/// fully-filled payoff matrix has `maxmin == minmax` within this tolerance, we
/// skip the LP solve and return the saddle value directly. Matches the solver-
/// level `SADDLE_TOL` in spirit; kept separate so the payoff layer can be
/// tuned independently of the LP solver's internal tolerance.
const VALUE_SADDLE_TOL : Double = 1.0e-10

///|
/// Tolerance for the β-cutoff in `value`: when the running pure-maximin lower
/// bound strictly exceeds `beta`, the remaining rows can be skipped because
/// the caller only cares about values ≤ β. The ε margin prevents premature
/// cutoff from floating-point noise when the bound exactly equals β.
const VALUE_PRUNE_EPS : Double = 1.0e-12

///|
/// Recursive Nash value of a `SwitchingGameState`. Solves a per-state zero-sum
/// matrix whose cells are `value(next_state, ...)` for each action pair.
/// Memoized by `cache` (state-value memo) and `dmg_cache` (damage-table memo);
/// both caches' hit/miss counters are recorded on `stats` and `dmg_cache`
/// respectively.
///
/// ## αβ-pruning semantics
///
/// `alpha` / `beta` bracket the range of values the caller cares about:
/// `alpha ≤ v ≤ beta`. If the caller determines (via pure-strategy pre-probes
/// from its own partially-filled matrix) that values outside `[alpha, beta]`
/// are acceptable as bounded substitutes, `value` may short-circuit and return
/// an upper bound ≥ β instead of the exact Nash value. The recursion in this
/// implementation is **conservative**: it only prunes at the current node and
/// always calls children with the full range `(-1.0, +1.0)`, so children
/// return exact values and the top-level result is bit-exact against the
/// unpruned reference implementation.
///
/// The `alpha` parameter is accepted for forward compatibility with a
/// symmetric α-cutoff (which would require iterating columns before rows); it
/// is currently unused.
pub fn value(
  state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
  cache : @hashmap.HashMap[SwitchingGameState, Double],
  stats : ValueStats,
  dmg_cache : DamageCache,
  alpha~ : Double = -1.0,
  beta~ : Double = 1.0,
  depth~ : Int = 0,
) -> Double {
  match terminal_value(state, my_team, opp_team, turn_limit) {
    Some(v) => return v
    None => ()
  }
  match cache.get(state) {
    Some(v) => {
      stats.hits = stats.hits + 1
      return v
    }
    None => stats.misses = stats.misses + 1
  }
  let actions_me = alive_actions(
    state.my_active,
    state.my_hps,
    my_team,
    state.my_mega_used,
    must_recharge=state.my_must_recharge[state.my_active],
    moves_used=state.my_moves_used,
  )
  let actions_opp = alive_actions(
    state.opp_active,
    state.opp_hps,
    opp_team,
    state.opp_mega_used,
    must_recharge=state.opp_must_recharge[state.opp_active],
    moves_used=state.opp_moves_used,
  )
  if actions_me.length() == 0 {
    return -1.0
  }
  if actions_opp.length() == 0 {
    return 1.0
  }
  let rows = actions_me.length()
  let cols = actions_opp.length()
  let data = Array::make(rows, ([] : Array[Double]))
  for i in 0..<rows {
    data[i] = Array::make(cols, 0.0)
  }
  let mut total_outcomes = 0
  // Running pure-maximin lower bound on the Nash value. Nash(A) ≥ max_i row_min_i
  // holds for every filled row, so once this lower bound is ≥ β we can
  // return it: the caller only needs `≤ β` to be informative.
  let mut lower = -2.0 // sentinel: any actual row_min ∈ [-1, +1] will dominate
  let mut pruned_early = false
  for i in 0..<rows {
    let mut row_min = 2.0 // sentinel: any actual cell ∈ [-1, +1] will dominate
    for j in 0..<cols {
      let outcomes = attempt_turn_with_cache(
        state, actions_me[i], actions_opp[j], my_team, opp_team, dmg_cache,
      )
      total_outcomes = total_outcomes + outcomes.length()
      let mut ev = 0.0
      for outcome in outcomes {
        let (prob, next) = outcome
        ev += prob * value(
          next,
          my_team,
          opp_team,
          turn_limit,
          cache,
          stats,
          dmg_cache,
          depth=depth + 1,
        )
      }
      data[i][j] = ev
      if ev < row_min {
        row_min = ev
      }
    }
    if row_min > lower {
      lower = row_min
    }
    // β-cutoff: Nash(A) ≥ lower ≥ β ⇒ caller's interest range exhausted.
    if lower >= beta - VALUE_PRUNE_EPS {
      pruned_early = true
      break
    }
  }
  if pruned_early {
    // Do NOT cache: the returned value is a lower bound, not the exact Nash.
    // A different caller with a wider β would miss the true value.
    maybe_emit_dp_node(stats, depth, rows, cols, total_outcomes, "pruned")
    return lower
  }
  // All rows filled: compute upper = min over j of col_max[j], which is now
  // the tight minimax bound on this node's Nash value (Nash(A) ≤ upper).
  let mut upper = 2.0
  for j in 0..<cols {
    let mut col_max = -2.0
    for i in 0..<rows {
      let v = data[i][j]
      if v > col_max {
        col_max = v
      }
    }
    if col_max < upper {
      upper = col_max
    }
  }
  // α-cutoff: caller's interest range is `[alpha, beta]`. If Nash ≤ upper ≤ α,
  // we know the value is below the caller's threshold without solving the LP.
  // Return `upper` as a valid upper bound; do NOT cache because a different
  // caller with a tighter `α` would miss the true Nash. Symmetric to the
  // β-cutoff above (which returns `lower` as a valid lower bound).
  if upper <= alpha + VALUE_PRUNE_EPS {
    maybe_emit_dp_node(stats, depth, rows, cols, total_outcomes, "alpha_pruned")
    return upper
  }
  // Pure saddle check: maxmin == minmax within tolerance ⇒ skip the LP. Speeds
  // up trivially-resolved subgames and avoids funnelling highly degenerate
  // matrices into the simplex path.
  if upper - lower <= VALUE_SADDLE_TOL {
    let saddle = (upper + lower) / 2.0
    cache.set(state, saddle)
    maybe_emit_dp_node(stats, depth, rows, cols, total_outcomes, "saddle")
    return saddle
  }
  let m = match @nash.FiniteMatrix::new(data) {
    Ok(x) => x
    Err(_) => return 0.0
  }
  let lp = try @nash.solve_zero_sum(m) catch {
    _ => return 0.0
  }
  let result = match lp {
    Optimal(value~, ..) => value
    _ => 0.0
  }
  cache.set(state, result)
  maybe_emit_dp_node(stats, depth, rows, cols, total_outcomes, "nash")
  result
}

///|
/// Emit a `DpNode` checkpoint when the running miss-count crosses the
/// `log_every` gate. Called from `value()` at each non-pruned exit so the
/// payload reflects the node that actually completed (depth + matrix dims +
/// outcome count + classification).
fn maybe_emit_dp_node(
  stats : ValueStats,
  depth : Int,
  rows : Int,
  cols : Int,
  outcomes : Int,
  classification : String,
) -> Unit {
  if stats.log_every > 0 &&
    stats.misses - stats.last_logged >= stats.log_every {
    stats.last_logged = stats.misses
    (stats.progress)(
      DpNode(
        stats.misses,
        stats.hits,
        depth,
        rows,
        cols,
        outcomes,
        classification,
      ),
    )
  }
}

///|
/// Entry point: compute the Nash value of a SwitchingGame between `my_team`
/// and `opp_team` starting at full HP with active slot 0 on each side, zero
/// ranks, and `turn = 0`. Return value is in `[-1, +1]`. Priority and
/// stat-boost metadata are read directly from each `move.priority` /
/// `move.stat_effects` — populate those fields via `pkdx moves` (which JOINs
/// `move_meta`) before building the combatants.
pub fn switching_game_winrate(
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
  disk~ : @damage_cache.DamageDiskCache? = None,
  progress~ : (ProgressEvent) -> Unit = noop_progress,
  dp_log_every~ : Int = 0,
) -> Double {
  let (v, _, _) = switching_game_winrate_stats(
    my_team, opp_team, turn_limit, disk~, progress~, dp_log_every~,
  )
  v
}

///|
/// Same as `switching_game_winrate`, but also returns the `ValueStats` and
/// `DamageCache` collected during the recursion. Useful for CI smoke tests
/// and diagnostics that need to sanity-check cache behaviour at larger
/// `turn_limit`.
pub fn switching_game_winrate_stats(
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
  disk~ : @damage_cache.DamageDiskCache? = None,
  progress~ : (ProgressEvent) -> Unit = noop_progress,
  dp_log_every~ : Int = 0,
) -> (Double, ValueStats, DamageCache) {
  let my_hps = Array::make(my_team.length(), 0)
  let opp_hps = Array::make(opp_team.length(), 0)
  for i in 0..<my_team.length() {
    my_hps[i] = my_team[i].pokemon.hp
  }
  for i in 0..<opp_team.length() {
    opp_hps[i] = opp_team[i].pokemon.hp
  }
  let state : SwitchingGameState = {
    my_active: 0,
    opp_active: 0,
    my_hps,
    opp_hps,
    my_ranks: zero_ranks(),
    opp_ranks: zero_ranks(),
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: Array::make(my_team.length(), false),
    opp_megaed: Array::make(opp_team.length(), false),
    my_status: zero_status(my_team.length()),
    opp_status: zero_status(opp_team.length()),
    my_must_recharge: Array::make(my_team.length(), false),
    opp_must_recharge: Array::make(opp_team.length(), false),
    my_item_consumed: Array::make(my_team.length(), false),
    opp_item_consumed: Array::make(opp_team.length(), false),
    my_moves_used: Array::make(my_team.length(), 0),
    opp_moves_used: Array::make(opp_team.length(), 0),
    turn: 0,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap([])
  let stats = new_stats_with_progress(progress, dp_log_every)
  let dmg_cache = new_damage_cache(disk~)
  let v = value(state, my_team, opp_team, turn_limit, cache, stats, dmg_cache)
  stats.cached_states = cache.length()
  (v, stats, dmg_cache)
}

///|
/// Enumerate legal actions for a side whose `active` slot is Pokemon `active`.
/// If `active` is alive, all of its moves (power=0 included) are legal. If
/// `active` is fainted (HP = 0), only `Switch(i)` actions to alive teammates
/// are legal (forced-switch semantics).
///
/// When this side has not yet consumed its mega (`mega_used = false`) and the
/// active carries a `mega_form`, one `Mega(mi)` action is appended per move,
/// letting the caller decide whether to trade the mega now (in exchange for
/// post-mega stats / type / ability on this turn's attack).
///
/// When `must_recharge` is true the entire turn is forfeit on this side —
/// matches the mainline behaviour for Hyper Beam / Giga Impact / Blast Burn /
/// Hydro Cannon / Frenzy Plant, where the next turn is fully skipped (no
/// move, no mega, no switch). A single `UseMove(0)` placeholder is returned
/// so the game tree still has exactly one branch; `per_side_attempt` will
/// short-circuit it to `acts=false`.
pub fn alive_actions(
  active : Int,
  hps : Array[Int],
  team : Array[Combatant],
  mega_used : Bool,
  must_recharge~ : Bool = false,
  moves_used~ : Array[Int] = [],
) -> Array[ActionKind] {
  let active_alive = hps[active] > 0
  if must_recharge && active_alive {
    return [UseMove(0)]
  }
  // とっておき (Last Resort) のフィルタ用に slot ごとの mask を取得。
  // 旧テスト fixture など length 0 の untracked 入力は 0 扱いで
  // last_resort_barred 内の "他の技を使っていない → barred" 条件に流れ込み、
  // 1 技目に Last Resort を投げると即フィルタされる。テストが Last Resort
  // を持たないなら結果は不変。
  let used_for_slot = if active < moves_used.length() {
    moves_used[active]
  } else {
    0
  }
  let moves = team[active].moves
  let out : Array[ActionKind] = []
  if active_alive {
    for i in 0..<moves.length() {
      if last_resort_barred(moves, i, used_for_slot) {
        continue
      }
      out.push(UseMove(i))
    }
  }
  if active_alive && can_mega(active, hps, team, mega_used) {
    for i in 0..<moves.length() {
      if last_resort_barred(moves, i, used_for_slot) {
        continue
      }
      out.push(Mega(i))
    }
  }
  for i in 0..<hps.length() {
    if i != active && hps[i] > 0 {
      out.push(Switch(i))
    }
  }
  out
}
