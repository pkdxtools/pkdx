///|
/// Phase 13 SwitchingGame: turn-limited extensive-form 2-player zero-sum
/// game that models Pokemon switching. Each turn both players simultaneously
/// choose an action (use a move or switch), transitions advance the state by
/// one turn, and the value is computed recursively from terminal HP via Nash
/// equilibria of the induced payoff matrix.

///|
/// Immutable state of a `SwitchingGame`: which Pokemon is active on each
/// side, HPs for all Pokemon, and turn counter. Used as a `HashMap` key for
/// the memoized `value` recursion.
pub(all) struct SwitchingGameState {
  my_active : Int
  opp_active : Int
  my_hps : Array[Int]
  opp_hps : Array[Int]
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
/// without relying on wall-clock timing.
pub(all) struct ValueStats {
  mut hits : Int
  mut misses : Int
}

///|
pub fn new_stats() -> ValueStats {
  { hits: 0, misses: 0 }
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
/// - `Some((opp_ratio - my_ratio) / 2)` if both still alive but
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
    // Row player (my team) sees positive value when winning, so use
    // my_r - opp_r (not opp - my).
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
/// `defender`, measured as the mean of the 16-roll damage table. Used as the
/// transition payload in `SwitchingGame` (no RNG at state-transition level).
fn mean_damage_idx(
  attacker : Combatant,
  defender : Combatant,
  move_idx : Int,
) -> Int {
  let mv = attacker.moves[move_idx]
  if mv.power <= 0 {
    return 0
  }
  let r = @damage.calc_damage(build_input(attacker, defender, mv))
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
/// Apply one game step to `state` given both players' actions. Damage is
/// applied in speed order (first KO skips the slower side's attack), both
/// switches happen simultaneously, and attack-vs-switch damages the newly
/// switched-in Pokemon. Always advances `turn` by 1.
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
  match (my_action, opp_action) {
    (Switch(i), Switch(j)) => {
      my_active_new = i
      opp_active_new = j
    }
    (Switch(i), UseMove(mj)) => {
      my_active_new = i
      let dmg = mean_damage_idx(opp_team[state.opp_active], my_team[i], mj)
      my_hps_new[i] = clamp_zero(my_hps_new[i] - dmg)
    }
    (UseMove(mi), Switch(j)) => {
      opp_active_new = j
      let dmg = mean_damage_idx(my_team[state.my_active], opp_team[j], mi)
      opp_hps_new[j] = clamp_zero(opp_hps_new[j] - dmg)
    }
    (UseMove(mi), UseMove(mj)) => {
      let me = my_team[state.my_active]
      let opp = opp_team[state.opp_active]
      let s = speed_sign(me, opp)
      if s == 0 {
        // Simultaneous: independently apply both sides' damage.
        let dmg_mo = mean_damage_idx(me, opp, mi)
        let dmg_om = mean_damage_idx(opp, me, mj)
        opp_hps_new[state.opp_active] = clamp_zero(
          opp_hps_new[state.opp_active] - dmg_mo,
        )
        my_hps_new[state.my_active] = clamp_zero(
          my_hps_new[state.my_active] - dmg_om,
        )
      } else if s > 0 {
        // My attacks first.
        let dmg_mo = mean_damage_idx(me, opp, mi)
        opp_hps_new[state.opp_active] = clamp_zero(
          opp_hps_new[state.opp_active] - dmg_mo,
        )
        if opp_hps_new[state.opp_active] > 0 {
          let dmg_om = mean_damage_idx(opp, me, mj)
          my_hps_new[state.my_active] = clamp_zero(
            my_hps_new[state.my_active] - dmg_om,
          )
        }
      } else {
        // Opp attacks first.
        let dmg_om = mean_damage_idx(opp, me, mj)
        my_hps_new[state.my_active] = clamp_zero(
          my_hps_new[state.my_active] - dmg_om,
        )
        if my_hps_new[state.my_active] > 0 {
          let dmg_mo = mean_damage_idx(me, opp, mi)
          opp_hps_new[state.opp_active] = clamp_zero(
            opp_hps_new[state.opp_active] - dmg_mo,
          )
        }
      }
    }
  }
  {
    my_active: my_active_new,
    opp_active: opp_active_new,
    my_hps: my_hps_new,
    opp_hps: opp_hps_new,
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
/// and `opp_team` starting at full HP with active slot 0 on each side and
/// `turn = 0`. Return value is in `[-1, +1]`.
pub fn switching_game_winrate(
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  turn_limit : Int,
) -> Double {
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
    turn: 0,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let stats = new_stats()
  value(state, my_team, opp_team, turn_limit, cache, stats)
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
