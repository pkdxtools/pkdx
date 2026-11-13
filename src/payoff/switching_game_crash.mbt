///|
/// 崩れ技 (Showdown `hasCrashDamage` + `onMoveFail`) の使用者 HP 消費。
///
/// 技が命中しなかった leg (外れ / タイプ・特性で対象が残らない) で、使用者は最大 HP の
/// 1/2 を失う。Showdown `data/moves.ts` の `onMoveFail` は
/// `this.damage(source.baseMaxhp / 2, source, source, condition)` を呼ぶ。`spreadDamage`
/// は `clampIntRange(_, 1)` を通す (`sim/battle.ts:2130`)。その `clampIntRange` は
/// `Math.floor` の後に下限 1 を掛ける (`lib/utils.ts:320-326`)。したがって消費量は
/// `max(1, floor(maxHP / 2))`。使用者の HP がこの値以下なら ひんし になる (`sim/pokemon.ts`
/// の `damage`)。
///
/// マジックガードの使用者は消費しない (`ability_blocks_crash_damage`)。Protect はモデル化
/// していない。
pub fn crash_hp_loss(mv : @model.Move, user_ability : String, user_max_hp : Int) -> Int {
  if !@damage.is_crash_move(mv.name) || ability_blocks_crash_damage(user_ability) {
    return 0
  }
  let half = user_max_hp / 2
  if half > 1 {
    half
  } else {
    1
  }
}

///|
/// The move of a UseMove / Mega action of `team[active]`; `None` for Switch or an
/// out-of-range index.
fn action_move_of(
  team : Array[Combatant],
  active : Int,
  action : ActionKind,
) -> @model.Move? {
  match action {
    UseMove(mi) | Mega(mi) =>
      if active >= 0 &&
        active < team.length() &&
        mi >= 0 &&
        mi < team[active].moves.length() {
        Some(team[active].moves[mi])
      } else {
        None
      }
    Switch(_) => None
  }
}

///|
fn is_mega_action(action : ActionKind) -> Bool {
  match action {
    Mega(_) => true
    _ => false
  }
}

///|
/// The self-loss move of a missed attempt (`SideAttempt.miss`): a 崩れ技 (crash) or a
/// てっていこうせん (max-HP recoil). `None` when the attempt did not miss or the move has
/// neither effect. Crash and recoil move lists are disjoint (`move_flags.mbt`).
fn missed_self_loss_move(
  attempt : SideAttempt,
  team : Array[Combatant],
  active : Int,
) -> @model.Move? {
  if !attempt.miss {
    return None
  }
  match action_move_of(team, active, attempt.action) {
    Some(mv) =>
      if @damage.is_crash_move(mv.name) || @damage.is_max_hp_recoil_move(mv.name) {
        Some(mv)
      } else {
        None
      }
    None => None
  }
}

///|
/// `true` when either side's attempt missed a move with a self-loss (crash or recoil).
/// `attempt_turn_with_cache` routes such attempts to `miss_self_loss_outcomes`; every
/// other attempt keeps the existing branches unchanged.
fn attempt_has_miss_self_loss(
  state : SwitchingGameState,
  ma : SideAttempt,
  oa : SideAttempt,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> Bool {
  let my_loss = missed_self_loss_move(ma, my_team, state.my_active)
  let opp_loss = missed_self_loss_move(oa, opp_team, state.opp_active)
  match (my_loss, opp_loss) {
    (None, None) => false
    _ => true
  }
}

///|
/// `true` when a self-loss move is a てっていこうせん (its trigger reads the defender's HP).
fn loss_is_recoil(loss : @model.Move?) -> Bool {
  match loss {
    Some(mv) => @damage.is_max_hp_recoil_move(mv.name)
    None => false
  }
}

///|
/// DP: subtract the crash HP loss of `mv` from the user at `user_slot`. Returns
/// `state` unchanged for non-crash moves and for Magic Guard users. Shared by the
/// immune leg (`apply_damage_variants_fanout`) and the missed attempt
/// (`miss_self_loss_outcomes`).
fn with_crash_damage(
  state : SwitchingGameState,
  user_is_me : Bool,
  user_slot : Int,
  user_team : Array[Combatant],
  mv : @model.Move,
) -> SwitchingGameState {
  if !@damage.is_crash_move(mv.name) ||
    user_slot < 0 ||
    user_slot >= user_team.length() {
    return state
  }
  let megaed = if user_is_me {
    state.my_megaed
  } else {
    state.opp_megaed
  }
  let is_mega = user_slot < megaed.length() && megaed[user_slot]
  let eff = effective_combatant(user_team[user_slot], is_mega)
  let loss = crash_hp_loss(mv, eff.ability, effective_hp(eff))
  if loss > 0 {
    with_hp_damage(state, user_is_me, user_slot, loss)
  } else {
    state
  }
}

///|
/// DP: the self-loss of `mv` (a missed move or an immune leg) for the user at `user_slot`.
/// 崩れ技 → `with_crash_damage` (no trigger). てっていこうせん → `with_max_hp_recoil`, which
/// fires only while the defender is alive at this point of the turn (`state`), so the
/// speed order of the two legs matters. Identity for every other move.
fn with_miss_self_loss(
  state : SwitchingGameState,
  user_is_me : Bool,
  user_slot : Int,
  user_team : Array[Combatant],
  mv : @model.Move,
) -> SwitchingGameState {
  if @damage.is_max_hp_recoil_move(mv.name) {
    let defender_alive = if user_is_me {
      state.opp_hps[state.opp_active] > 0
    } else {
      state.my_hps[state.my_active] > 0
    }
    with_max_hp_recoil(
      state,
      user_is_me,
      user_slot,
      user_team,
      mv,
      defender_alive,
    )
  } else {
    with_crash_damage(state, user_is_me, user_slot, user_team, mv)
  }
}

///|
/// DP: the missed user was put to sleep by the other side's move this turn
/// (`action_blocked_by_fresh_status`), so it cannot act and nothing crashes. The
/// landing turn is still its first sleep attempt, so the counter steps down here
/// (`consume_sleep_attempt_on_block`). Same rule as `resolve_moves` and the MC
/// `*_blocked_mid_turn` branch. Returns a fresh copy (turn unchanged).
fn with_landing_sleep_consumed(
  state : SwitchingGameState,
  user_is_me : Bool,
  user_slot : Int,
) -> SwitchingGameState {
  let s = clone_state(state, 0)
  if user_is_me {
    s.my_status[user_slot] = consume_sleep_attempt_on_block(s.my_status[user_slot])
  } else {
    s.opp_status[user_slot] = consume_sleep_attempt_on_block(s.opp_status[user_slot])
  }
  s
}

///|
/// Speed sign of the two moves of `ma` and `oa` (`move_turn_sign`, the same rule
/// `transition_with_cache` uses). `+1` = my move first, `-1` = opp first, `0` = tie
/// or a non-move action.
fn attempt_turn_sign(
  state : SwitchingGameState,
  ma : SideAttempt,
  oa : SideAttempt,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> Int {
  match (
    action_move_of(my_team, state.my_active, ma.action),
    action_move_of(opp_team, state.opp_active, oa.action),
  ) {
    (Some(mv_me), Some(mv_opp)) => {
      let my_mega = state.my_active < state.my_megaed.length() &&
        state.my_megaed[state.my_active]
      let opp_mega = state.opp_active < state.opp_megaed.length() &&
        state.opp_megaed[state.opp_active]
      move_turn_sign(
        my_team[state.my_active],
        state.my_ranks,
        mv_me,
        my_mega || is_mega_action(ma.action),
        is_paralyzed(state.my_status[state.my_active]),
        state.my_hps[state.my_active],
        opp_team[state.opp_active],
        state.opp_ranks,
        mv_opp,
        opp_mega || is_mega_action(oa.action),
        is_paralyzed(state.opp_status[state.opp_active]),
        state.opp_hps[state.opp_active],
      )
    }
    _ => 0
  }
}

///|
/// Attempt-phase outcomes when a missed move carries a self-loss (`SideAttempt.miss`:
/// 崩れ技 or てっていこうせん) on at least one side. Showdown runs the MoveFail effect in
/// the same action slot as the missed move, so the missed user loses its HP:
///   - before the other side's action when the missed user is faster,
///   - after it when the missed user is slower (unless a sleep landed on the user
///     this turn, which cancels the move before `MoveFail`),
///   - and averaged over both orders on a speed tie (as `transition_with_cache`).
///     A Switch always resolves before any move, so the missed user comes second.
///
/// When both sides fail (miss or skip), nobody else acts. Two crashes commute (the crash
/// does not read HP), so a crash-only pair keeps one outcome. A recoil reads whether the
/// defender is alive, so a pair with a recoil runs both legs in speed order. A pair of
/// acting sides cannot carry a miss, so it is delegated unchanged.
fn miss_self_loss_outcomes(
  state : SwitchingGameState,
  ma : SideAttempt,
  oa : SideAttempt,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
) -> Array[(Double, SwitchingGameState)] {
  if ma.acts && oa.acts {
    return transition_with_cache(
      state,
      ma.action,
      oa.action,
      my_team,
      opp_team,
      dmg_cache,
    )
  }
  let my_loss = missed_self_loss_move(ma, my_team, state.my_active)
  let opp_loss = missed_self_loss_move(oa, opp_team, state.opp_active)
  if !ma.acts && !oa.acts {
    let s0 = pass_turn_state(state, ma.post_status, oa.post_status)
    if !loss_is_recoil(my_loss) && !loss_is_recoil(opp_loss) {
      let s1 = match my_loss {
        Some(mv) => with_crash_damage(s0, true, s0.my_active, my_team, mv)
        None => s0
      }
      let s2 = match opp_loss {
        Some(mv) => with_crash_damage(s1, false, s1.opp_active, opp_team, mv)
        None => s1
      }
      return [(1.0, s2)]
    }
    let me_leg = fn(s : SwitchingGameState) -> SwitchingGameState {
      match my_loss {
        Some(mv) => with_miss_self_loss(s, true, s.my_active, my_team, mv)
        None => s
      }
    }
    let opp_leg = fn(s : SwitchingGameState) -> SwitchingGameState {
      match opp_loss {
        Some(mv) => with_miss_self_loss(s, false, s.opp_active, opp_team, mv)
        None => s
      }
    }
    let sign = attempt_turn_sign(state, ma, oa, my_team, opp_team)
    if sign > 0 {
      return [(1.0, opp_leg(me_leg(s0)))]
    }
    if sign < 0 {
      return [(1.0, me_leg(opp_leg(s0)))]
    }
    return [(0.5, opp_leg(me_leg(s0))), (0.5, me_leg(opp_leg(s0)))]
  }
  // Exactly one side acts; the other side missed or was skipped.
  let me_acts = ma.acts
  let acting = if me_acts {
    ma.action
  } else {
    oa.action
  }
  let missed_loss = if me_acts {
    opp_loss
  } else {
    my_loss
  }
  let idle = if me_acts { oa.action } else { ma.action }
  match missed_loss {
    None =>
      partial_act_outcomes(
        state, acting, me_acts, my_team, opp_team, dmg_cache, idle,
      )
    Some(mv) => {
      let missed_is_me = !me_acts
      let slot = if missed_is_me {
        state.my_active
      } else {
        state.opp_active
      }
      let team = if missed_is_me {
        my_team
      } else {
        opp_team
      }
      let pre_status = if missed_is_me {
        state.my_status[slot]
      } else {
        state.opp_status[slot]
      }
      // > 0: the missed user acts first; < 0: second; 0: tie.
      let missed_first = match acting {
        Switch(_) => -1
        UseMove(_) | Mega(_) => {
          let s = attempt_turn_sign(state, ma, oa, my_team, opp_team)
          if missed_is_me {
            s
          } else {
            -s
          }
        }
      }
      let loss_first = fn() {
        let s0 = with_miss_self_loss(state, missed_is_me, slot, team, mv)
        partial_act_outcomes(
          s0, acting, me_acts, my_team, opp_team, dmg_cache, idle,
        )
      }
      let loss_second = fn() {
        let outs : Array[(Double, SwitchingGameState)] = []
        for out in partial_act_outcomes(
          state,
          acting,
          me_acts,
          my_team,
          opp_team,
          dmg_cache,
          idle,
        ) {
          let s = out.1
          let now = if missed_is_me {
            s.my_status[slot]
          } else {
            s.opp_status[slot]
          }
          let s1 = if action_blocked_by_fresh_status(pre_status, now) {
            with_landing_sleep_consumed(s, missed_is_me, slot)
          } else {
            with_miss_self_loss(s, missed_is_me, slot, team, mv)
          }
          outs.push((out.0, s1))
        }
        outs
      }
      if missed_first > 0 {
        loss_first()
      } else if missed_first < 0 {
        loss_second()
      } else {
        let outs : Array[(Double, SwitchingGameState)] = []
        for x in loss_first() {
          outs.push((0.5 * x.0, x.1))
        }
        for x in loss_second() {
          outs.push((0.5 * x.0, x.1))
        }
        outs
      }
    }
  }
}

///|
/// MC: the self-loss of a missed move `mv` (or an immune leg) for `team[slot]`. 崩れ技 →
/// `mc_apply_crash` (no trigger); てっていこうせん → `team_apply_max_hp_recoil`, gated by
/// `defender_alive` (the other side's active HP > 0 at this point of the leg).
fn mc_apply_miss_self_loss(
  hps : Array[Int],
  slot : Int,
  team : Array[Combatant],
  mv : @model.Move,
  defender_alive : Bool,
) -> Unit {
  if slot < 0 || slot >= team.length() {
    return
  }
  if @damage.is_max_hp_recoil_move(mv.name) {
    team_apply_max_hp_recoil(hps, slot, team, mv, defender_alive)
  } else {
    mc_apply_crash(hps, slot, team[slot], mv)
  }
}

///|
/// MC: subtract the crash HP loss of `mv` from `hps[slot]` in place. `user` is the
/// raw combatant (MC does not model mega). No-op for non-crash moves and Magic Guard.
fn mc_apply_crash(
  hps : Array[Int],
  slot : Int,
  user : Combatant,
  mv : @model.Move,
) -> Unit {
  if !@damage.is_crash_move(mv.name) || slot < 0 || slot >= hps.length() {
    return
  }
  let loss = crash_hp_loss(mv, user.ability, effective_hp(user))
  if loss > 0 {
    hps[slot] = clamp_zero(hps[slot] - loss)
  }
}
