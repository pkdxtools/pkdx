///|
/// Phase 13 SwitchingGame: turn-limited extensive-form 2-player zero-sum
/// game that models Pokemon switching, stat-rank-affecting setup moves, and
/// priority-aware action order. Each turn both players simultaneously choose
/// an action (use a move or switch), transitions advance the state by one
/// turn, and the value is computed recursively from terminal HP via Nash
/// equilibria of the induced per-turn payoff matrix.
///
/// ## αβ-pruning readiness
///
/// The state representation is intentionally αβ-friendly: it is immutable
/// (`derive(Eq, Hash)`), all side-effects of a turn are captured in the
/// returned next-state, and `value` is a pure recursion over the state-action
/// tree with `solve_zero_sum` as the per-node aggregator. Adding αβ bounds
/// (minimax with bound propagation) amounts to threading `alpha` / `beta`
/// arguments through `value`, walking rows / columns with an ordering
/// heuristic (e.g. by negated expected payoff), and pruning when the running
/// upper/lower bounds cross. No state-structure changes are required — the
/// existing `SwitchingGameState` + per-state Nash solve is the structure αβ
/// expects.

///|
/// Immutable state of a `SwitchingGame`: which Pokemon is active on each
/// side, HPs for all Pokemon, stat ranks of the current actives (clamped to
/// `[-2, +2]` per the payoff-layer convention, reset on switch), and turn
/// counter. Used as a `HashMap` key for the memoized `value` recursion.
///
/// `my_ranks` / `opp_ranks` have length 5: `[A, B, C, D, S]` (see
/// `move_meta.mbt` for the index convention). They track only the currently-
/// active Pokemon; a `Switch` action resets them to `[0, 0, 0, 0, 0]`.
pub(all) struct SwitchingGameState {
  my_active : Int
  opp_active : Int
  my_hps : Array[Int]
  opp_hps : Array[Int]
  my_ranks : Array[Int]
  opp_ranks : Array[Int]
  turn : Int
} derive(Show, Eq, Hash)

///|
/// A single-turn action: use a move from the active Pokemon's moveset, or
/// switch to another (alive, non-active) Pokemon on the same team.
pub(all) enum ActionKind {
  UseMove(Int)
  Switch(Int)
} derive(Show, Eq)

///|
/// Observability hooks for memoization: callers can inspect hit/miss counts
/// without relying on wall-clock timing. Used by tests and by CLI diagnostics
/// to verify that larger `turn_limit` values stay cache-bound.
pub(all) struct ValueStats {
  mut hits : Int
  mut misses : Int
}

///|
pub fn new_stats() -> ValueStats {
  { hits: 0, misses: 0 }
}

///|
/// Fresh zero-rank vector for a newly switched-in Pokemon.
fn zero_ranks() -> Array[Int] {
  [0, 0, 0, 0, 0]
}

///|
/// Is at least one Pokemon on this side still alive?
fn any_alive(hps : Array[Int]) -> Bool {
  for hp in hps {
    if hp > 0 {
      return true
    }
  }
  false
}

///|
/// Average HP ratio across a team: `Σ max(hp_i, 0)/max_hp_i / N`, in [0, 1].
fn hp_ratio(hps : Array[Int], team : Array[Combatant]) -> Double {
  let n = hps.length()
  if n == 0 {
    return 0.0
  }
  let mut total = 0.0
  for i in 0..<n {
    let max_hp = team[i].pokemon.hp
    if max_hp > 0 {
      let cur = if hps[i] > 0 { hps[i] } else { 0 }
      total += cur.to_double() / max_hp.to_double()
    }
  }
  total / n.to_double()
}

///|
/// Terminal value of `state`:
/// - `Some(-1.0)` if all `my_hps` are 0 (my team wiped)
/// - `Some(+1.0)` if all `opp_hps` are 0 (opp team wiped)
/// - `Some((my_ratio - opp_ratio) / 2)` if both still alive but
///   `turn >= turn_limit`; clamped to [-1, +1]
/// - `None` otherwise (non-terminal)
pub fn terminal_value(
  state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
) -> Double? {
  let my_alive = any_alive(state.my_hps)
  let opp_alive = any_alive(state.opp_hps)
  if not(my_alive) {
    return Some(-1.0)
  }
  if not(opp_alive) {
    return Some(1.0)
  }
  if state.turn >= turn_limit {
    let my_r = hp_ratio(state.my_hps, my_team)
    let opp_r = hp_ratio(state.opp_hps, opp_team)
    let delta = (my_r - opp_r) / 2.0
    let clamped = if delta > 1.0 {
      1.0
    } else if delta < -1.0 {
      -1.0
    } else {
      delta
    }
    return Some(clamped)
  }
  None
}

///|
/// Deterministic expected damage of `attacker`'s `move_idx`-th move against
/// `defender`, measured as the mean of the 16-roll damage table under the
/// given attacker / defender rank vectors. Stat ranks feed `atk_rank` /
/// `def_rank` in the damage calc, picking `A` vs `B` for physical moves and
/// `C` vs `D` for special moves (stat indices 0/1 vs 2/3 in the 5-slot rank
/// vector).
fn mean_damage_idx(
  attacker : Combatant,
  atk_ranks : Array[Int],
  defender : Combatant,
  def_ranks : Array[Int],
  move_idx : Int,
) -> Int {
  let mv = attacker.moves[move_idx]
  if mv.power <= 0 {
    return 0
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
    return 0
  }
  let mut s = 0
  for i in 0..<16 {
    s += r.damages[i]
  }
  s / 16
}

///|
fn clamp_zero(x : Int) -> Int {
  if x > 0 {
    x
  } else {
    0
  }
}

///|
/// Apply the stat-boost effects (if any) of `mv_name` to `ranks` in-place.
/// Each delta is added and clamped to `[-2, +2]` via `clamp_rank`.
fn apply_stat_boost(ranks : Array[Int], mv_name : String) -> Unit {
  match stat_boost_effect(mv_name) {
    Some(effs) =>
      for eff in effs {
        let (idx, delta) = eff
        if idx >= 0 && idx < ranks.length() {
          ranks[idx] = clamp_rank(ranks[idx] + delta)
        }
      }
    None => ()
  }
}

///|
/// Priority-aware, rank-aware turn order sign between the two actives for the
/// given moves. Returns `+1` if my active acts first, `-1` if opp acts first,
/// `0` on full ties.
fn move_turn_sign(
  me : Combatant,
  me_ranks : Array[Int],
  mv_me : @model.Move,
  opp : Combatant,
  opp_ranks : Array[Int],
  mv_opp : @model.Move,
) -> Int {
  let prio_me = move_priority(mv_me.name)
  let prio_opp = move_priority(mv_opp.name)
  let eff_me = effective_speed(me.pokemon.spe, me_ranks[4])
  let eff_opp = effective_speed(opp.pokemon.spe, opp_ranks[4])
  turn_order_sign(me, prio_me, eff_me, opp, prio_opp, eff_opp)
}

///|
/// Apply one game step to `state` given both players' actions. Damage is
/// applied in action-order (priority → effective speed; first KO skips the
/// slower side's attack), switches reset the switcher's ranks, stat-boost
/// moves update the user's ranks. Always advances `turn` by 1.
pub fn transition(
  state : SwitchingGameState,
  my_action : ActionKind,
  opp_action : ActionKind,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> SwitchingGameState {
  let my_hps_new = state.my_hps.copy()
  let opp_hps_new = state.opp_hps.copy()
  let mut my_active_new = state.my_active
  let mut opp_active_new = state.opp_active
  let my_ranks_new = state.my_ranks.copy()
  let opp_ranks_new = state.opp_ranks.copy()
  match (my_action, opp_action) {
    (Switch(i), Switch(j)) => {
      my_active_new = i
      opp_active_new = j
      // Ranks reset on switch-in.
      for k in 0..<5 {
        my_ranks_new[k] = 0
        opp_ranks_new[k] = 0
      }
    }
    (Switch(i), UseMove(mj)) => {
      my_active_new = i
      for k in 0..<5 {
        my_ranks_new[k] = 0
      }
      // Attack hits the freshly switched-in target (fresh ranks = 0).
      let dmg = mean_damage_idx(
        opp_team[state.opp_active],
        opp_ranks_new,
        my_team[i],
        my_ranks_new,
        mj,
      )
      my_hps_new[i] = clamp_zero(my_hps_new[i] - dmg)
      // Opp's own stat-boost (if status move) still resolves on user.
      apply_stat_boost(opp_ranks_new, opp_team[state.opp_active].moves[mj].name)
    }
    (UseMove(mi), Switch(j)) => {
      opp_active_new = j
      for k in 0..<5 {
        opp_ranks_new[k] = 0
      }
      let dmg = mean_damage_idx(
        my_team[state.my_active],
        my_ranks_new,
        opp_team[j],
        opp_ranks_new,
        mi,
      )
      opp_hps_new[j] = clamp_zero(opp_hps_new[j] - dmg)
      apply_stat_boost(my_ranks_new, my_team[state.my_active].moves[mi].name)
    }
    (UseMove(mi), UseMove(mj)) => {
      let me = my_team[state.my_active]
      let opp = opp_team[state.opp_active]
      let mv_me = me.moves[mi]
      let mv_opp = opp.moves[mj]
      let s = move_turn_sign(
        me, my_ranks_new, mv_me, opp, opp_ranks_new, mv_opp,
      )
      let dmg_mo = mean_damage_idx(
        me, my_ranks_new, opp, opp_ranks_new, mi,
      )
      let dmg_om = mean_damage_idx(
        opp, opp_ranks_new, me, my_ranks_new, mj,
      )
      if s == 0 {
        // Simultaneous: both sides' damage applied independently.
        opp_hps_new[state.opp_active] = clamp_zero(
          opp_hps_new[state.opp_active] - dmg_mo,
        )
        my_hps_new[state.my_active] = clamp_zero(
          my_hps_new[state.my_active] - dmg_om,
        )
        apply_stat_boost(my_ranks_new, mv_me.name)
        apply_stat_boost(opp_ranks_new, mv_opp.name)
      } else if s > 0 {
        // My active attacks first. Rank-ups on my side apply regardless of
        // whether the move damages (status moves).
        opp_hps_new[state.opp_active] = clamp_zero(
          opp_hps_new[state.opp_active] - dmg_mo,
        )
        apply_stat_boost(my_ranks_new, mv_me.name)
        if opp_hps_new[state.opp_active] > 0 {
          my_hps_new[state.my_active] = clamp_zero(
            my_hps_new[state.my_active] - dmg_om,
          )
          apply_stat_boost(opp_ranks_new, mv_opp.name)
        }
      } else {
        my_hps_new[state.my_active] = clamp_zero(
          my_hps_new[state.my_active] - dmg_om,
        )
        apply_stat_boost(opp_ranks_new, mv_opp.name)
        if my_hps_new[state.my_active] > 0 {
          opp_hps_new[state.opp_active] = clamp_zero(
            opp_hps_new[state.opp_active] - dmg_mo,
          )
          apply_stat_boost(my_ranks_new, mv_me.name)
        }
      }
    }
  }
  {
    my_active: my_active_new,
    opp_active: opp_active_new,
    my_hps: my_hps_new,
    opp_hps: opp_hps_new,
    my_ranks: my_ranks_new,
    opp_ranks: opp_ranks_new,
    turn: state.turn + 1,
  }
}

///|
/// Recursive Nash value of a `SwitchingGameState`. Solves a per-state zero-sum
/// matrix whose cells are `value(next_state, ...)` for each action pair.
/// Memoized by `cache`; cache hit/miss counters are recorded in `stats`.
pub fn value(
  state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
  cache : @hashmap.HashMap[SwitchingGameState, Double],
  stats : ValueStats,
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
  let actions_me = alive_actions(state.my_active, state.my_hps, my_team)
  let actions_opp = alive_actions(state.opp_active, state.opp_hps, opp_team)
  if actions_me.length() == 0 {
    return -1.0
  }
  if actions_opp.length() == 0 {
    return 1.0
  }
  let data = Array::make(actions_me.length(), ([] : Array[Double]))
  for i in 0..<actions_me.length() {
    data[i] = Array::make(actions_opp.length(), 0.0)
  }
  for i in 0..<actions_me.length() {
    for j in 0..<actions_opp.length() {
      let next = transition(
        state, actions_me[i], actions_opp[j], my_team, opp_team,
      )
      data[i][j] = value(next, my_team, opp_team, turn_limit, cache, stats)
    }
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
  result
}

///|
/// Entry point: compute the Nash value of a SwitchingGame between `my_team`
/// and `opp_team` starting at full HP with active slot 0 on each side, zero
/// ranks, and `turn = 0`. Return value is in `[-1, +1]`.
pub fn switching_game_winrate(
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
) -> Double {
  let (v, _) = switching_game_winrate_stats(my_team, opp_team, turn_limit)
  v
}

///|
/// Same as `switching_game_winrate`, but also returns the `ValueStats`
/// collected during the recursion. Useful for CI smoke tests and diagnostics
/// that need to sanity-check cache behaviour at larger `turn_limit`.
pub fn switching_game_winrate_stats(
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
) -> (Double, ValueStats) {
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
    turn: 0,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let stats = new_stats()
  let v = value(state, my_team, opp_team, turn_limit, cache, stats)
  (v, stats)
}

///|
/// Enumerate legal actions for a side whose `active` slot is Pokemon `active`.
/// If `active` is alive, all of its moves (power=0 included) are legal. If
/// `active` is fainted (HP = 0), only `Switch(i)` actions to alive teammates
/// are legal (forced-switch semantics).
pub fn alive_actions(
  active : Int,
  hps : Array[Int],
  team : Array[Combatant],
) -> Array[ActionKind] {
  let out : Array[ActionKind] = []
  if hps[active] > 0 {
    for i in 0..<team[active].moves.length() {
      out.push(UseMove(i))
    }
  }
  for i in 0..<hps.length() {
    if i != active && hps[i] > 0 {
      out.push(Switch(i))
    }
  }
  out
}
