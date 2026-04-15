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
/// Compute the mean damage for the given `(attacker, defender, move, ranks)`
/// tuple directly, without cache lookup. The numeric kernel underneath
/// `mean_damage_cached` — call-sites should reach it via the cache wrapper
/// so the 16-roll table is not recomputed on every state transition.
fn compute_mean_damage(
  attacker : Combatant,
  defender : Combatant,
  mv : @model.Move,
  atk_rank : Int,
  def_rank : Int,
) -> Int {
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
/// Cache key for memoized mean damage. `my_attacker` distinguishes which
/// side's team the attacker/defender indices reference — without it my_team[0]
/// and opp_team[0] would collide. Ranks are stored pre-resolved (already
/// dispatched by move category in `mean_damage_cached`), so the key contains
/// only the values that change the damage output.
pub(all) struct DamageKey {
  my_attacker : Bool
  atk_idx : Int
  def_idx : Int
  mv_idx : Int
  atk_rank : Int
  def_rank : Int
} derive(Eq, Hash)

///|
/// Memoized mean-damage cache for a single SwitchingGame evaluation. Stores
/// `DamageKey → Int` (mean damage) and tracks hit/miss counts for
/// observability.
///
/// Lifetime is one `switching_game_winrate*` call: teams / abilities / items /
/// stat_system / tera_type are all fixed across the recursion, so the cache
/// stays valid. Reusing the same cache across calls with different teams
/// would be unsound (indices rebind).
pub(all) struct DamageCache {
  data : @hashmap.HashMap[DamageKey, Int]
  mut hits : Int
  mut misses : Int
}

///|
pub fn new_damage_cache() -> DamageCache {
  { data: @hashmap.HashMap::new(), hits: 0, misses: 0 }
}

///|
/// Cached mean-damage lookup. `my_attacker = true` means the attacker is in
/// `my_team` (and defender in `opp_team`); swap otherwise. `atk_ranks` /
/// `def_ranks` are the 5-slot rank vectors of the attacker / defender side
/// respectively. Public so external tests can observe cache counters.
pub fn mean_damage_cached(
  cache : DamageCache,
  my_attacker : Bool,
  atk_idx : Int,
  atk_ranks : Array[Int],
  def_idx : Int,
  def_ranks : Array[Int],
  mv_idx : Int,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> Int {
  let attacker = if my_attacker { my_team[atk_idx] } else { opp_team[atk_idx] }
  let defender = if my_attacker { opp_team[def_idx] } else { my_team[def_idx] }
  let mv = attacker.moves[mv_idx]
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
  let key : DamageKey = {
    my_attacker,
    atk_idx,
    def_idx,
    mv_idx,
    atk_rank,
    def_rank,
  }
  match cache.data.get(key) {
    Some(v) => {
      cache.hits = cache.hits + 1
      v
    }
    None => {
      cache.misses = cache.misses + 1
      let v = compute_mean_damage(attacker, defender, mv, atk_rank, def_rank)
      cache.data[key] = v
      v
    }
  }
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
/// Apply the stat-boost effects carried on `mv.stat_effects` to `ranks`
/// in-place. Each delta is added and clamped to `[-2, +2]` via `clamp_rank`.
/// Metadata is populated upstream in `query_moves` (DB) or in the JSON
/// payload consumed by `parse_move_json`.
fn apply_stat_boost(ranks : Array[Int], mv : @model.Move) -> Unit {
  for eff in mv.stat_effects {
    let (idx, delta) = eff
    if idx >= 0 && idx < ranks.length() {
      ranks[idx] = clamp_rank(ranks[idx] + delta)
    }
  }
}

///|
/// Priority-aware, rank-aware turn order sign between the two actives for the
/// given moves. Returns `+1` if my active acts first, `-1` if opp acts first,
/// `0` on full ties. Reads priority directly from `@model.Move.priority`
/// (populated by `query_moves` via the `move_meta` DB JOIN).
fn move_turn_sign(
  me : Combatant,
  me_ranks : Array[Int],
  mv_me : @model.Move,
  opp : Combatant,
  opp_ranks : Array[Int],
  mv_opp : @model.Move,
) -> Int {
  let eff_me = effective_speed(me.pokemon.spe, me_ranks[4])
  let eff_opp = effective_speed(opp.pokemon.spe, opp_ranks[4])
  turn_order_sign(me, mv_me.priority, eff_me, opp, mv_opp.priority, eff_opp)
}

///|
/// Resolve a turn where both sides use a move, with proper damage recomputation
/// after the first actor's stat boosts. `my_first` determines action order.
fn resolve_moves(
  state : SwitchingGameState,
  mi : Int,
  mj : Int,
  my_first : Bool,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
  dmg_cache : DamageCache,
) -> SwitchingGameState {
  let my_hps = state.my_hps.copy()
  let opp_hps = state.opp_hps.copy()
  let my_ranks = state.my_ranks.copy()
  let opp_ranks = state.opp_ranks.copy()
  let mv_me = my_team[state.my_active].moves[mi]
  let mv_opp = opp_team[state.opp_active].moves[mj]
  if my_first {
    let dmg_mo = mean_damage_cached(
      dmg_cache, true, state.my_active, my_ranks, state.opp_active, opp_ranks,
      mi, my_team, opp_team,
    )
    opp_hps[state.opp_active] = clamp_zero(opp_hps[state.opp_active] - dmg_mo)
    apply_stat_boost(my_ranks, mv_me)
    if opp_hps[state.opp_active] > 0 {
      let dmg_om = mean_damage_cached(
        dmg_cache, false, state.opp_active, opp_ranks, state.my_active, my_ranks,
        mj, my_team, opp_team,
      )
      my_hps[state.my_active] = clamp_zero(my_hps[state.my_active] - dmg_om)
      apply_stat_boost(opp_ranks, mv_opp)
    }
  } else {
    let dmg_om = mean_damage_cached(
      dmg_cache, false, state.opp_active, opp_ranks, state.my_active, my_ranks,
      mj, my_team, opp_team,
    )
    my_hps[state.my_active] = clamp_zero(my_hps[state.my_active] - dmg_om)
    apply_stat_boost(opp_ranks, mv_opp)
    if my_hps[state.my_active] > 0 {
      let dmg_mo = mean_damage_cached(
        dmg_cache, true, state.my_active, my_ranks, state.opp_active, opp_ranks,
        mi, my_team, opp_team,
      )
      opp_hps[state.opp_active] = clamp_zero(opp_hps[state.opp_active] - dmg_mo)
      apply_stat_boost(my_ranks, mv_me)
    }
  }
  {
    my_active: state.my_active,
    opp_active: state.opp_active,
    my_hps,
    opp_hps,
    my_ranks,
    opp_ranks,
    turn: state.turn + 1,
  }
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
      let dmg = mean_damage_cached(
        dmg_cache,
        false,
        state.opp_active,
        opp_ranks_new,
        i,
        my_ranks_new,
        mj,
        my_team,
        opp_team,
      )
      my_hps_new[i] = clamp_zero(my_hps_new[i] - dmg)
      // Opp's own stat-boost (if status move) still resolves on user.
      apply_stat_boost(
        opp_ranks_new,
        opp_team[state.opp_active].moves[mj],
      )
    }
    (UseMove(mi), Switch(j)) => {
      opp_active_new = j
      for k in 0..<5 {
        opp_ranks_new[k] = 0
      }
      let dmg = mean_damage_cached(
        dmg_cache,
        true,
        state.my_active,
        my_ranks_new,
        j,
        opp_ranks_new,
        mi,
        my_team,
        opp_team,
      )
      opp_hps_new[j] = clamp_zero(opp_hps_new[j] - dmg)
      apply_stat_boost(my_ranks_new, my_team[state.my_active].moves[mi])
    }
    (UseMove(mi), UseMove(mj)) => {
      let me = my_team[state.my_active]
      let opp = opp_team[state.opp_active]
      let mv_me = me.moves[mi]
      let mv_opp = opp.moves[mj]
      let s = move_turn_sign(
        me, my_ranks_new, mv_me, opp, opp_ranks_new, mv_opp,
      )
      if s == 0 {
        // Speed tie: return two outcomes so the caller averages successor
        // *values* (not states). resolve_moves recomputes the second hit's
        // damage after the first actor's stat boosts.
        return [
          (0.5, resolve_moves(state, mi, mj, true, my_team, opp_team, dmg_cache)),
          (0.5, resolve_moves(state, mi, mj, false, my_team, opp_team, dmg_cache)),
        ]
      } else {
        let my_first = s > 0
        return [
          (1.0, resolve_moves(state, mi, mj, my_first, my_team, opp_team, dmg_cache)),
        ]
      }
    }
  }
  [(1.0, {
    my_active: my_active_new,
    opp_active: opp_active_new,
    my_hps: my_hps_new,
    opp_hps: opp_hps_new,
    my_ranks: my_ranks_new,
    opp_ranks: opp_ranks_new,
    turn: state.turn + 1,
  })]
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
) -> Double {
  let _ = alpha // Reserved for future symmetric α-cutoff; see doc comment.
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
  let rows = actions_me.length()
  let cols = actions_opp.length()
  let data = Array::make(rows, ([] : Array[Double]))
  for i in 0..<rows {
    data[i] = Array::make(cols, 0.0)
  }
  // Running pure-maximin lower bound on the Nash value. Nash(A) ≥ max_i row_min_i
  // holds for every filled row, so once this lower bound is ≥ β we can
  // return it: the caller only needs `≤ β` to be informative.
  let mut lower = -2.0 // sentinel: any actual row_min ∈ [-1, +1] will dominate
  let mut pruned_early = false
  for i in 0..<rows {
    let mut row_min = 2.0 // sentinel: any actual cell ∈ [-1, +1] will dominate
    for j in 0..<cols {
      let outcomes = transition_with_cache(
        state, actions_me[i], actions_opp[j], my_team, opp_team, dmg_cache,
      )
      let mut ev = 0.0
      for outcome in outcomes {
        let (prob, next) = outcome
        ev += prob * value(
          next, my_team, opp_team, turn_limit, cache, stats, dmg_cache,
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
    return lower
  }
  // All rows filled: check for a pure saddle (maxmin == minmax within tolerance)
  // and skip the LP if so. This both speeds up trivially-resolved subgames and
  // avoids funnelling highly degenerate matrices into the simplex path.
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
  if upper - lower <= VALUE_SADDLE_TOL {
    let saddle = (upper + lower) / 2.0
    cache.set(state, saddle)
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
  result
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
) -> Double {
  let (v, _, _) = switching_game_winrate_stats(my_team, opp_team, turn_limit)
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
    turn: 0,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let stats = new_stats()
  let dmg_cache = new_damage_cache()
  let v = value(state, my_team, opp_team, turn_limit, cache, stats, dmg_cache)
  (v, stats, dmg_cache)
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
