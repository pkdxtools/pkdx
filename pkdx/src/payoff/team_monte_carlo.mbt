///|
/// Team-level Monte Carlo rollout used by the Screened pipeline. Simulates
/// 3v3-style battles with switching as a cheap pre-screening signal for
/// `team_payoff_matrix_screened`.
///
/// Returned value is in `[-1, +1]` (own-side utility): +1 = own sweeps,
/// -1 = own swept, otherwise the HP-ratio difference clamped to that range
/// when the rollout hits `turn_limit`. Mega evolution is intentionally
/// ignored — this is a rough screening pass; precise refinement is the
/// job of the SwitchingGame DP downstream.

///|
/// Switch hysteresis threshold: only switch when the best alternative slot's
/// expected damage / opp_hp exceeds the current active's value by more than
/// this. Keeps the rollout from thrashing on marginal matchups.
const SWITCH_HYSTERESIS : Double = 0.05

///|
/// Compute the best avg-damage move a given attacker can land on the given
/// defender with the given ranks. Returns `0.0` when all moves are immune or
/// non-damaging. Cheap wrapper around `pick_best_move` used by the greedy
/// heuristic — the returned scalar is not the move index but the expected
/// damage scalar.
fn best_expected_damage(
  atk : Combatant,
  dfn : Combatant,
  atk_ranks : Array[Int],
  def_ranks : Array[Int],
) -> Double {
  let mut best = 0.0
  for i in 0..<atk.moves.length() {
    let mv = atk.moves[i]
    if mv.power <= 0 {
      continue
    }
    let ar = match mv.category {
      @model.Physical => atk_ranks[0]
      @model.Special => atk_ranks[2]
      @model.Status => 0
    }
    let dr = match mv.category {
      @model.Physical => def_ranks[1]
      @model.Special => def_ranks[3]
      @model.Status => 0
    }
    let r = @damage.calc_damage(build_input_with_ranks(atk, dfn, mv, ar, dr))
    let avg = avg_damage(r)
    if avg > best {
      best = avg
    }
  }
  best
}

///|
/// Team action chosen for one rollout turn: `UseMove(mv_idx)` or
/// `Switch(slot_idx)`. Simpler than `ActionKind` in `switching_game.mbt` —
/// no Mega support in the screening rollout.
priv enum TeamAction {
  TmUseMove(Int)
  TmSwitch(Int)
}

///|
/// Pick a TeamAction for the given side under a stay-vs-best-switch greedy
/// policy with ε-greedy exploration. When `active` is KO-d, returns the
/// best forced switch (or `None` if the entire side has fainted).
fn greedy_team_action(
  active : Int,
  my_team : Array[Combatant],
  my_hps : Array[Int],
  my_ranks : Array[Int],
  opp_active : Int,
  opp_team : Array[Combatant],
  opp_ranks : Array[Int],
  rng : @random.Rand,
  epsilon : Double,
) -> TeamAction? {
  let alive_slots : Array[Int] = []
  for i in 0..<my_hps.length() {
    if my_hps[i] > 0 {
      alive_slots.push(i)
    }
  }
  if alive_slots.length() == 0 {
    return None
  }
  // active KO → forced switch (only switch actions are legal)
  if my_hps[active] <= 0 {
    let mut best = alive_slots[0]
    let mut best_score = -1.0
    let zero_ranks = [0, 0, 0, 0, 0]
    for s in alive_slots {
      let score = best_expected_damage(
        my_team[s], opp_team[opp_active], zero_ranks, opp_ranks,
      )
      if score > best_score {
        best_score = score
        best = s
      }
    }
    return Some(TmSwitch(best))
  }
  // ε-greedy: uniform over all legal actions (UseMove for every move + Switch
  // for every alive teammate other than `active`).
  let n_moves = my_team[active].moves.length()
  let n_switch = {
    let mut c = 0
    for s in alive_slots {
      if s != active {
        c = c + 1
      }
    }
    c
  }
  let total_actions = n_moves + n_switch
  if total_actions == 0 {
    return None
  }
  let draw = rng.int(limit=1000000).to_double() / 1000000.0
  if draw < epsilon {
    let idx = rng.int(limit=total_actions)
    if idx < n_moves {
      return Some(TmUseMove(idx))
    }
    // find the idx-n_moves-th switch slot in alive_slots order
    let mut k = idx - n_moves
    for s in alive_slots {
      if s == active {
        continue
      }
      if k == 0 {
        return Some(TmSwitch(s))
      }
      k = k - 1
    }
    return Some(TmUseMove(0))
  }
  // Greedy: stay vs best-switch comparison, normalised by opp active max HP.
  let opp_hp_denom = {
    let h = opp_team[opp_active].pokemon.hp
    if h > 0 {
      h.to_double()
    } else {
      1.0
    }
  }
  let stay_value = best_expected_damage(
      my_team[active], opp_team[opp_active], my_ranks, opp_ranks,
    ) /
    opp_hp_denom
  let mut best_switch = -1
  let mut best_switch_value = 0.0
  let zero_ranks = [0, 0, 0, 0, 0]
  for s in alive_slots {
    if s == active {
      continue
    }
    let v = best_expected_damage(
        my_team[s], opp_team[opp_active], zero_ranks, opp_ranks,
      ) /
      opp_hp_denom
    if v > best_switch_value {
      best_switch_value = v
      best_switch = s
    }
  }
  if best_switch >= 0 && best_switch_value > stay_value + SWITCH_HYSTERESIS {
    return Some(TmSwitch(best_switch))
  }
  // UseMove: greedy max-damage move. Fall back to move 0 if no damaging move.
  match pick_best_move(
    my_team[active], opp_team[opp_active],
    atk_ranks=my_ranks, def_ranks=opp_ranks,
  ) {
    Some(i) => Some(TmUseMove(i))
    None => Some(TmUseMove(0))
  }
}

///|
/// Apply one pre-selected attack in the team rollout. Mirrors
/// `perform_attack_with` in `monte_carlo.mbt` but free-standing so the team
/// rollout stays self-contained.
fn team_perform_attack(
  attacker : Combatant,
  defender : Combatant,
  defender_hp : Int,
  mv : @model.Move,
  rng : @random.Rand,
  atk_ranks : Array[Int],
  def_ranks : Array[Int],
  atk_burn~ : Bool = false,
) -> Int {
  if mv.power <= 0 {
    for eff in mv.stat_effects {
      let (idx, delta) = eff
      if idx >= 0 && idx < atk_ranks.length() {
        atk_ranks[idx] = clamp_rank(atk_ranks[idx] + delta)
      }
    }
    return defender_hp
  }
  let atk_rank = match mv.category {
    @model.Physical => atk_ranks[0]
    @model.Special => atk_ranks[2]
    @model.Status => 0
  }
  let def_rank = match mv.category {
    @model.Physical => def_ranks[1]
    @model.Special => def_ranks[3]
    @model.Status => 0
  }
  let r = @damage.calc_damage(
    build_input_with_ranks(attacker, defender, mv, atk_rank, def_rank),
  )
  if r.is_immune {
    return defender_hp
  }
  let raw = r.damages[rng.int(limit=16)]
  // やけど + 物理: ダメージ半減。
  let dmg = if atk_burn {
    match mv.category {
      @model.Physical => raw / 2
      _ => raw
    }
  } else {
    raw
  }
  defender_hp - dmg
}

///|
/// Sample a Bernoulli outcome with success probability `p` in [0, 1] using
/// `rng.int(limit=N)` quantised at 1/1_000_000 granularity.
fn rand_bool(rng : @random.Rand, p : Double) -> Bool {
  if p <= 0.0 {
    return false
  }
  if p >= 1.0 {
    return true
  }
  rng.int(limit=1000000).to_double() / 1000000.0 < p
}

///|
/// Resolve a single attack attempt for `me` in the MC rollout, respecting
/// paralysis (12.5% failure), sleep (skip + counter decrement / wake-up),
/// and move accuracy. Returns the new status of `me` and whether the action
/// executes this turn.
fn mc_resolve_attempt(
  status : @model.StatusCondition,
  mv_acc : Int,
  rng : @random.Rand,
) -> (@model.StatusCondition, Bool) {
  match status {
    @model.Sleep(n) => {
      if n > 0 {
        return (@model.Sleep(n - 1), false)
      }
      // Sleep(0): wake up and act subject to accuracy below.
      let acts = rand_bool(rng, mv_acc.to_double() / 100.0)
      (@model.None, acts)
    }
    @model.Paralyze => {
      if rand_bool(rng, PARALYZE_SKIP_RATE) {
        return (@model.Paralyze, false)
      }
      let acts = rand_bool(rng, mv_acc.to_double() / 100.0)
      (@model.Paralyze, acts)
    }
    other => {
      let acts = rand_bool(rng, mv_acc.to_double() / 100.0)
      (other, acts)
    }
  }
}

///|
/// MC rollout variant of `maybe_apply_status_fanout` — samples the chance
/// roll directly. Mutates `defender_status_arr[defender_slot]` in place when
/// the status lands (ignored when already statused, type immune, fainted, or
/// the chance roll fails).
fn mc_try_apply_status(
  rng : @random.Rand,
  mv : @model.Move,
  defender_team : Array[Combatant],
  defender_hps : Array[Int],
  defender_status_arr : Array[@model.StatusCondition],
  defender_slot : Int,
) -> Unit {
  let eff = match mv.status_effect {
    None => return
    Some(x) => x
  }
  let (kind, chance) = eff
  if chance <= 0 {
    return
  }
  if defender_hps[defender_slot] <= 0 {
    return
  }
  if defender_status_arr[defender_slot] != @model.None {
    return
  }
  let c = defender_team[defender_slot]
  if @model.immune_to_status(kind, c.pokemon.type1, c.pokemon.type2) {
    return
  }
  if not(rand_bool(rng, chance.to_double() / 100.0)) {
    return
  }
  defender_status_arr[defender_slot] = @model.inflict_status(kind)
}

///|
/// Apply end-of-turn slip damage for one side's active slot. Mirrors
/// `eot_slip_active` from switching_game but operates on mutable team arrays.
fn mc_eot_slip(
  max_hp : Int,
  current_hp : Int,
  status : @model.StatusCondition,
) -> (Int, @model.StatusCondition) {
  if current_hp <= 0 {
    return (current_hp, status)
  }
  match status {
    @model.Burn => {
      let dmg = max_hp / 16
      let h = current_hp - dmg
      (if h < 0 { 0 } else { h }, status)
    }
    @model.Poison => {
      let dmg = max_hp / 8
      let h = current_hp - dmg
      (if h < 0 { 0 } else { h }, status)
    }
    @model.BadPoison(n) => {
      let ticks = if n + 1 > TOXIC_MAX_TICKS { TOXIC_MAX_TICKS } else { n + 1 }
      let dmg = max_hp * ticks / 16
      let h = current_hp - dmg
      (if h < 0 { 0 } else { h }, @model.BadPoison(ticks))
    }
    @model.Drowsy(n) => {
      if n > 0 {
        (current_hp, @model.Drowsy(n - 1))
      } else {
        (current_hp, @model.Sleep(2))
      }
    }
    _ => (current_hp, status)
  }
}

///|
/// Run a single team rollout trial. Returns own-side value in `[-1, +1]`:
///
/// - `+1.0` when all opponents are KO'd
/// - `-1.0` when all own Pokemon are KO'd
/// - `own_team_hp_ratio - opp_team_hp_ratio` clamped to `[-1, +1]` when `turn_limit`
///   elapses with both sides still alive
///
/// Mega evolution is not modelled here (screening heuristic).
pub fn team_rollout(
  own : Array[Combatant],
  opp : Array[Combatant],
  rng : @random.Rand,
  turn_limit~ : Int = MC_TURN_LIMIT,
  epsilon~ : Double = default_rollout_epsilon,
) -> Double {
  let own_hps = Array::make(own.length(), 0)
  let opp_hps = Array::make(opp.length(), 0)
  for i in 0..<own.length() {
    own_hps[i] = own[i].pokemon.hp
  }
  for i in 0..<opp.length() {
    opp_hps[i] = opp[i].pokemon.hp
  }
  let own_ranks = [0, 0, 0, 0, 0]
  let opp_ranks = [0, 0, 0, 0, 0]
  let own_status : Array[@model.StatusCondition] = Array::make(
    own.length(), @model.None,
  )
  let opp_status : Array[@model.StatusCondition] = Array::make(
    opp.length(), @model.None,
  )
  let mut own_active = 0
  let mut opp_active = 0
  for _ in 0..<turn_limit {
    let a_own = greedy_team_action(
      own_active, own, own_hps, own_ranks, opp_active, opp, opp_ranks, rng,
      epsilon,
    )
    let a_opp = greedy_team_action(
      opp_active, opp, opp_hps, opp_ranks, own_active, own, own_ranks, rng,
      epsilon,
    )
    match (a_own, a_opp) {
      (None, _) => return -1.0
      (_, None) => return 1.0
      (Some(ao), Some(ap)) => {
        let own_switches = match ao {
          TmSwitch(_) => true
          _ => false
        }
        let opp_switches = match ap {
          TmSwitch(_) => true
          _ => false
        }
        // Step 1: resolve status-phase attempts for move attempts (switches are
        // always successful and bypass sleep / paralyze).
        let mut own_attempt_acts = true
        let mut opp_attempt_acts = true
        match ao {
          TmUseMove(mi) => {
            let (st, acts) = mc_resolve_attempt(
              own_status[own_active], own[own_active].moves[mi].accuracy, rng,
            )
            own_status[own_active] = st
            own_attempt_acts = acts
          }
          _ => ()
        }
        match ap {
          TmUseMove(mi) => {
            let (st, acts) = mc_resolve_attempt(
              opp_status[opp_active], opp[opp_active].moves[mi].accuracy, rng,
            )
            opp_status[opp_active] = st
            opp_attempt_acts = acts
          }
          _ => ()
        }
        // Step 2: apply switches. Reset toxic counter on the switched-out slot.
        match ao {
          TmSwitch(i) => {
            own_status[own_active] = reset_toxic_counter_on_switch(
              own_status[own_active],
            )
            own_active = i
            reset_ranks(own_ranks)
          }
          _ => ()
        }
        match ap {
          TmSwitch(i) => {
            opp_status[opp_active] = reset_toxic_counter_on_switch(
              opp_status[opp_active],
            )
            opp_active = i
            reset_ranks(opp_ranks)
          }
          _ => ()
        }
        // Step 3: resolve moves honouring paralysis speed halving and skips.
        if not(own_switches) && not(opp_switches) {
          let mi_own = match ao {
            TmUseMove(i) => i
            _ => -1
          }
          let mi_opp = match ap {
            TmUseMove(i) => i
            _ => -1
          }
          let mv_own = own[own_active].moves[mi_own]
          let mv_opp = opp[opp_active].moves[mi_opp]
          let base_spe_own = effective_speed(
            own[own_active].pokemon.spe,
            own_ranks[4],
          )
          let base_spe_opp = effective_speed(
            opp[opp_active].pokemon.spe,
            opp_ranks[4],
          )
          let eff_spe_own = if is_paralyzed(own_status[own_active]) {
            base_spe_own / 2
          } else {
            base_spe_own
          }
          let eff_spe_opp = if is_paralyzed(opp_status[opp_active]) {
            base_spe_opp / 2
          } else {
            base_spe_opp
          }
          let s = turn_order_sign(
            own[own_active], mv_own.priority, eff_spe_own, opp[opp_active],
            mv_opp.priority, eff_spe_opp,
          )
          let own_first = if s > 0 {
            true
          } else if s < 0 {
            false
          } else {
            rng.boolean()
          }
          // Pre-first-leg statuses. Captured so the second leg can detect a
          // mid-turn sleep (Spore/Hypnosis) that locks the target out and read
          // the post-first-leg burn (Will-O-Wisp halving physical damage).
          let own_pre_status = own_status[own_active]
          let opp_pre_status = opp_status[opp_active]
          if own_first {
            let mut opp_blocked_mid_turn = false
            if own_attempt_acts {
              opp_hps[opp_active] = team_perform_attack(
                own[own_active], opp[opp_active], opp_hps[opp_active], mv_own,
                rng, own_ranks, opp_ranks, atk_burn=is_burned(own_pre_status),
              )
              mc_try_apply_status(
                rng, mv_own, opp, opp_hps, opp_status, opp_active,
              )
              if all_ko(opp_hps) {
                return 1.0
              }
              if action_blocked_by_fresh_status(
                opp_pre_status,
                opp_status[opp_active],
              ) {
                opp_blocked_mid_turn = true
              }
            }
            if opp_hps[opp_active] > 0 &&
              opp_attempt_acts &&
              not(opp_blocked_mid_turn) {
              // Read burn *after* first leg's status fan-out so a fresh burn
              // from own's move halves opp's physical damage this turn.
              let opp_burn_now = is_burned(opp_status[opp_active])
              own_hps[own_active] = team_perform_attack(
                opp[opp_active], own[own_active], own_hps[own_active], mv_opp,
                rng, opp_ranks, own_ranks, atk_burn=opp_burn_now,
              )
              mc_try_apply_status(
                rng, mv_opp, own, own_hps, own_status, own_active,
              )
              if all_ko(own_hps) {
                return -1.0
              }
            }
          } else {
            let mut own_blocked_mid_turn = false
            if opp_attempt_acts {
              own_hps[own_active] = team_perform_attack(
                opp[opp_active], own[own_active], own_hps[own_active], mv_opp,
                rng, opp_ranks, own_ranks, atk_burn=is_burned(opp_pre_status),
              )
              mc_try_apply_status(
                rng, mv_opp, own, own_hps, own_status, own_active,
              )
              if all_ko(own_hps) {
                return -1.0
              }
              if action_blocked_by_fresh_status(
                own_pre_status,
                own_status[own_active],
              ) {
                own_blocked_mid_turn = true
              }
            }
            if own_hps[own_active] > 0 &&
              own_attempt_acts &&
              not(own_blocked_mid_turn) {
              let own_burn_now = is_burned(own_status[own_active])
              opp_hps[opp_active] = team_perform_attack(
                own[own_active], opp[opp_active], opp_hps[opp_active], mv_own,
                rng, own_ranks, opp_ranks, atk_burn=own_burn_now,
              )
              mc_try_apply_status(
                rng, mv_own, opp, opp_hps, opp_status, opp_active,
              )
              if all_ko(opp_hps) {
                return 1.0
              }
            }
          }
        } else if not(own_switches) {
          let mi_own = match ao {
            TmUseMove(i) => i
            _ => -1
          }
          let mv_own = own[own_active].moves[mi_own]
          let own_burn = is_burned(own_status[own_active])
          if own_attempt_acts {
            opp_hps[opp_active] = team_perform_attack(
              own[own_active], opp[opp_active], opp_hps[opp_active], mv_own,
              rng, own_ranks, opp_ranks, atk_burn=own_burn,
            )
            mc_try_apply_status(
              rng, mv_own, opp, opp_hps, opp_status, opp_active,
            )
            if all_ko(opp_hps) {
              return 1.0
            }
          }
        } else if not(opp_switches) {
          let mi_opp = match ap {
            TmUseMove(i) => i
            _ => -1
          }
          let mv_opp = opp[opp_active].moves[mi_opp]
          let opp_burn = is_burned(opp_status[opp_active])
          if opp_attempt_acts {
            own_hps[own_active] = team_perform_attack(
              opp[opp_active], own[own_active], own_hps[own_active], mv_opp,
              rng, opp_ranks, own_ranks, atk_burn=opp_burn,
            )
            mc_try_apply_status(
              rng, mv_opp, own, own_hps, own_status, own_active,
            )
            if all_ko(own_hps) {
              return -1.0
            }
          }
        }
        // Step 4: end-of-turn slip damage on each active (both still alive
        // below; dead slots are handled by `all_ko` earlier).
        let own_max = effective_hp(own[own_active])
        let opp_max = effective_hp(opp[opp_active])
        let (new_own_hp, new_own_st) = mc_eot_slip(
          own_max, own_hps[own_active], own_status[own_active],
        )
        own_hps[own_active] = new_own_hp
        own_status[own_active] = new_own_st
        let (new_opp_hp, new_opp_st) = mc_eot_slip(
          opp_max, opp_hps[opp_active], opp_status[opp_active],
        )
        opp_hps[opp_active] = new_opp_hp
        opp_status[opp_active] = new_opp_st
        if all_ko(own_hps) {
          return -1.0
        }
        if all_ko(opp_hps) {
          return 1.0
        }
      }
    }
  }
  // Turn limit hit: return HP ratio difference clamped to [-1, +1].
  let own_ratio = team_hp_ratio(own, own_hps)
  let opp_ratio = team_hp_ratio(opp, opp_hps)
  let v = own_ratio - opp_ratio
  if v > 1.0 {
    1.0
  } else if v < -1.0 {
    -1.0
  } else {
    v
  }
}

///|
/// Aggregate team rollout result over `trials` seeded runs. Returns value in
/// `[-1, +1]`. `trials <= 0` returns `0.0` (neutral prior).
pub fn team_monte_carlo_value(
  own : Array[Combatant],
  opp : Array[Combatant],
  trials : Int,
  seed : UInt64,
  turn_limit~ : Int = MC_TURN_LIMIT,
) -> Double {
  if trials <= 0 {
    return 0.0
  }
  let rng = seeded_rng(seed)
  let mut total = 0.0
  for _ in 0..<trials {
    total += team_rollout(own, opp, rng, turn_limit~)
  }
  total / trials.to_double()
}

///|
fn reset_ranks(ranks : Array[Int]) -> Unit {
  for i in 0..<ranks.length() {
    ranks[i] = 0
  }
}

///|
fn all_ko(hps : Array[Int]) -> Bool {
  for h in hps {
    if h > 0 {
      return false
    }
  }
  true
}

///|
/// Sum of `(hp_i / max_hp_i)` divided by team size.
fn team_hp_ratio(team : Array[Combatant], hps : Array[Int]) -> Double {
  let mut total = 0.0
  for i in 0..<team.length() {
    let max_hp = team[i].pokemon.hp
    if max_hp > 0 {
      let h = if hps[i] > 0 { hps[i] } else { 0 }
      total += h.to_double() / max_hp.to_double()
    }
  }
  total / team.length().to_double()
}
