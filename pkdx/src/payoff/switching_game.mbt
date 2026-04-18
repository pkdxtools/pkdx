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
  // 各サイドで mega をすでに 1 回消費したか。Mega は各サイド 1 回までの制約。
  my_mega_used : Bool
  opp_mega_used : Bool
  // team 各スロットが mega 済みか。switch 後に戻ってきたスロットの mega 状態を
  // 維持するために slot ごとに保存する。長さは team サイズ。
  my_megaed : Array[Bool]
  opp_megaed : Array[Bool]
  // Slot-scoped status condition for each team member. Length = team size.
  // Persists across switches (conditions don't heal on switch-out); counter
  // semantics per StatusCondition variant docs (BadPoison resets on switch,
  // Sleep persists).
  my_status : Array[@model.StatusCondition]
  opp_status : Array[@model.StatusCondition]
  turn : Int
} derive(Show, Eq, Hash)

///|
/// Fresh `None`-filled status array sized for a team. Used at game entry
/// and in test construction.
pub fn zero_status(team_size : Int) -> Array[@model.StatusCondition] {
  Array::make(team_size, @model.None)
}

///|
/// Per-side outcome of an action attempt (Task 5). Paralyze / sleep / move
/// accuracy can cause the side's declared action to fail or the sleep counter
/// to tick without an act. The `post_status` field carries the active slot's
/// status after this attempt resolves (pre-EOT-tick), so the caller can
/// thread it into the resulting next-state.
pub(all) struct SideAttempt {
  prob : Double
  acts : Bool
  action : ActionKind
  post_status : @model.StatusCondition
} derive(Show)

///|
/// Paralyze: 12.5% chance of full-turn failure (gen7+ freeze/paralysis rate).
pub const PARALYZE_SKIP_RATE : Double = 0.125

///|
/// Enumerate the attempt outcomes for a side given its current status, the
/// declared action, and the move's accuracy (ignored for Switch; 100 for the
/// selected move if `UseMove`/`Mega`). Outcomes with probability 0 are
/// filtered out so downstream fan-out doesn't enumerate dead branches.
///
/// The Switch action is always deterministic — status / accuracy don't gate
/// switching. Only `UseMove` / `Mega` can skip.
pub fn per_side_attempt(
  status : @model.StatusCondition,
  action : ActionKind,
  accuracy : Int,
) -> Array[SideAttempt] {
  let acts_only : Array[SideAttempt] = [
    { prob: 1.0, acts: true, action, post_status: status },
  ]
  match action {
    Switch(_) => acts_only
    UseMove(_) | Mega(_) => {
      let acc_hit = accuracy.to_double() / 100.0
      let acc_miss = 1.0 - acc_hit
      let outs : Array[SideAttempt] = []
      match status {
        @model.Sleep(n) =>
          if n > 0 {
            outs.push({
              prob: 1.0,
              acts: false,
              action,
              post_status: @model.Sleep(n - 1),
            })
          } else {
            // Sleep(0): this turn is the wake-up; act normally afterward.
            if acc_hit > 0.0 {
              outs.push({
                prob: acc_hit,
                acts: true,
                action,
                post_status: @model.None,
              })
            }
            if acc_miss > 0.0 {
              outs.push({
                prob: acc_miss,
                acts: false,
                action,
                post_status: @model.None,
              })
            }
          }
        @model.Paralyze => {
          outs.push({
            prob: PARALYZE_SKIP_RATE,
            acts: false,
            action,
            post_status: @model.Paralyze,
          })
          let non_para = 1.0 - PARALYZE_SKIP_RATE
          if acc_hit > 0.0 {
            outs.push({
              prob: non_para * acc_hit,
              acts: true,
              action,
              post_status: @model.Paralyze,
            })
          }
          if acc_miss > 0.0 {
            outs.push({
              prob: non_para * acc_miss,
              acts: false,
              action,
              post_status: @model.Paralyze,
            })
          }
        }
        _ => {
          if acc_hit > 0.0 {
            outs.push({ prob: acc_hit, acts: true, action, post_status: status })
          }
          if acc_miss > 0.0 {
            outs.push({
              prob: acc_miss,
              acts: false,
              action,
              post_status: status,
            })
          }
        }
      }
      outs
    }
  }
}

///|
/// Badpoison counter denominator cap. Toxic deals `min(counter+1, TOXIC_MAX)/16`
/// of max HP per EOT tick. The gen-accurate cap is 15/16 (counter saturates
/// at 15); mirrored here so the state space stays bounded.
pub const TOXIC_MAX_TICKS : Int = 15

///|
/// Produce probabilistic next-state outcomes for a status-effect fan-out.
/// Given `state_after_dmg` (already updated for damage and stat boosts) plus
/// the attacking `move` and the target slot, returns either a single 1.0
/// outcome (no status applied — move has no effect, target is fainted /
/// already statused / type immune, or chance is 0) or two outcomes
/// `[(1-p, no_status), (p, with_status)]`.
///
/// `target_is_me = true` means the status would land on `state.my_status`
/// (i.e., the opponent used the move). `target_slot` is the slot receiving
/// the status, which is usually the active but may be a switched-in slot.
pub fn maybe_apply_status_fanout(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  target_team : Array[Combatant],
  mv : @model.Move,
) -> Array[(Double, SwitchingGameState)] {
  let eff = match mv.status_effect {
    None => return [(1.0, state)]
    Some(x) => x
  }
  let (kind, chance) = eff
  if chance <= 0 {
    return [(1.0, state)]
  }
  let target_hps = if target_is_me { state.my_hps } else { state.opp_hps }
  if target_hps[target_slot] <= 0 {
    return [(1.0, state)]
  }
  let target_status = if target_is_me { state.my_status } else { state.opp_status }
  let cur = target_status[target_slot]
  if cur != @model.None {
    return [(1.0, state)]
  }
  let combatant = target_team[target_slot]
  if @model.immune_to_status(
    kind, combatant.pokemon.type1, combatant.pokemon.type2,
  ) {
    return [(1.0, state)]
  }
  let p = chance.to_double() / 100.0
  if p >= 1.0 {
    return [(1.0, with_status_set(state, target_is_me, target_slot, kind))]
  }
  [
    (1.0 - p, state),
    (p, with_status_set(state, target_is_me, target_slot, kind)),
  ]
}

///|
/// Copy `state` and set `target_slot`'s status on the chosen side to the
/// freshly-inflicted `StatusCondition` for `kind` (via `inflict_status`).
fn with_status_set(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  kind : @model.StatusKind,
) -> SwitchingGameState {
  let new_cond = @model.inflict_status(kind)
  let my_status = if target_is_me {
    override_active_status(state.my_status, target_slot, new_cond)
  } else {
    state.my_status.copy()
  }
  let opp_status = if target_is_me {
    state.opp_status.copy()
  } else {
    override_active_status(state.opp_status, target_slot, new_cond)
  }
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
    turn: state.turn,
  }
}

///|
/// Apply one end-of-turn slip / counter update for the given active slot.
/// Returns `(new_hp, new_status)`. HP never falls below 0 from slip damage.
/// - Burn / Poison: subtract max_hp / 16 or max_hp / 8 respectively.
/// - BadPoison(n): subtract max_hp * min(n+1, TOXIC_MAX_TICKS) / 16 and
///   advance to BadPoison(min(n+1, TOXIC_MAX_TICKS)).
/// - Sleep / Paralyze / None: no-op.
pub fn eot_slip_active(
  current_hp : Int,
  max_hp : Int,
  status : @model.StatusCondition,
) -> (Int, @model.StatusCondition) {
  if current_hp <= 0 {
    return (current_hp, status)
  }
  match status {
    @model.Burn => {
      let dmg = max_hp / 16
      (clamp_zero(current_hp - dmg), status)
    }
    @model.Poison => {
      let dmg = max_hp / 8
      (clamp_zero(current_hp - dmg), status)
    }
    @model.BadPoison(n) => {
      let ticks = if n + 1 > TOXIC_MAX_TICKS { TOXIC_MAX_TICKS } else { n + 1 }
      let dmg = max_hp * ticks / 16
      (clamp_zero(current_hp - dmg), @model.BadPoison(ticks))
    }
    @model.Drowsy(n) => {
      // n>0: まだ猶予あり、カウンタを 1 減らす。n==0: ここでねむり発動。
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
/// Apply end-of-turn slip damage and counter updates to both actives of
/// `state` in place on fresh copies; returns the updated state. Only the
/// active slot receives EOT — bench Pokemon don't tick. Called at the end of
/// every turn resolution in `attempt_turn_with_cache`.
pub fn apply_eot(
  state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> SwitchingGameState {
  let my_hps = state.my_hps.copy()
  let opp_hps = state.opp_hps.copy()
  let my_status = state.my_status.copy()
  let opp_status = state.opp_status.copy()
  let my_max = effective_hp(my_team[state.my_active])
  let opp_max = effective_hp(opp_team[state.opp_active])
  let (my_hp_new, my_st_new) = eot_slip_active(
    my_hps[state.my_active], my_max, my_status[state.my_active],
  )
  my_hps[state.my_active] = my_hp_new
  my_status[state.my_active] = my_st_new
  let (opp_hp_new, opp_st_new) = eot_slip_active(
    opp_hps[state.opp_active], opp_max, opp_status[state.opp_active],
  )
  opp_hps[state.opp_active] = opp_hp_new
  opp_status[state.opp_active] = opp_st_new
  {
    my_active: state.my_active,
    opp_active: state.opp_active,
    my_hps,
    opp_hps,
    my_ranks: state.my_ranks.copy(),
    opp_ranks: state.opp_ranks.copy(),
    my_mega_used: state.my_mega_used,
    opp_mega_used: state.opp_mega_used,
    my_megaed: state.my_megaed.copy(),
    opp_megaed: state.opp_megaed.copy(),
    my_status,
    opp_status,
    turn: state.turn,
  }
}

///|
/// Update a switched-out slot's status per mainline switch-out rules:
/// - `BadPoison(n)`: keep the status but reset the counter to 0 (next tick
///   is 1/16 again).
/// - `Drowsy(_)`: clear entirely — あくびの予告は控えに下がると消える。
/// - Other conditions: carry over unchanged (burns / paralysis / sleep all
///   persist across switches in canonical rules).
pub fn reset_toxic_counter_on_switch(
  status : @model.StatusCondition,
) -> @model.StatusCondition {
  match status {
    @model.BadPoison(_) => @model.BadPoison(0)
    @model.Drowsy(_) => @model.None
    other => other
  }
}

///|
pub fn is_paralyzed(s : @model.StatusCondition) -> Bool {
  match s {
    @model.Paralyze => true
    _ => false
  }
}

///|
pub fn is_burned(s : @model.StatusCondition) -> Bool {
  match s {
    @model.Burn => true
    _ => false
  }
}

///|
/// Return the number of remaining unable-to-act turns if `s` is a `Sleep`
/// condition. `Some(n)` means the sufferer will skip this turn (n ≥ 1) or
/// wake up (n == 0). `None` means not asleep.
pub fn sleep_turns(s : @model.StatusCondition) -> Int? {
  match s {
    @model.Sleep(n) => Some(n)
    _ => None
  }
}

///|
/// A single-turn action: use a move from the active Pokemon's moveset, or
/// switch to another (alive, non-active) Pokemon on the same team.
pub(all) enum ActionKind {
  UseMove(Int)
  Switch(Int)
  // `Mega(mi)`: mega evolve the current active and use move index `mi` this
  // turn. Legal only when the active's `mega_form` is `Some(_)` and this
  // side's `*_mega_used` flag is still false. Mega flips the side's flag and
  // marks `*_megaed[active] = true` so the post-mega stats/type/ability persist
  // across later switches.
  Mega(Int)
} derive(Show, Eq)

///|
/// Observability hooks for memoization: callers can inspect hit/miss counts
/// without relying on wall-clock timing. Used by tests and by CLI diagnostics
/// to verify that larger `turn_limit` values stay cache-bound.
pub(all) struct ValueStats {
  mut hits : Int
  mut misses : Int
  mut cached_states : Int
}

///|
pub fn new_stats() -> ValueStats {
  { hits: 0, misses: 0, cached_states: 0 }
}

///|
/// Fresh zero-rank vector for a newly switched-in Pokemon.
fn zero_ranks() -> Array[Int] {
  [0, 0, 0, 0, 0]
}

///|
/// Is this side allowed to declare a `Mega` action right now?
/// `mega_used = false` (side has not spent its one mega), the active is alive,
/// and the active has a `mega_form` attached. The mega-stone item name is not
/// part of the gate — the presence of `mega_form = Some(_)` is the single
/// source of truth (mega-stone validation happens upstream in cache / CLI).
fn can_mega(
  active : Int,
  hps : Array[Int],
  team : Array[Combatant],
  mega_used : Bool,
) -> Bool {
  if mega_used {
    return false
  }
  if hps[active] <= 0 {
    return false
  }
  match team[active].mega_form {
    None => false
    Some(_) => true
  }
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
/// Build a shallow combatant view with mega-form stats / type / ability applied
/// when `is_mega` is true and the original has a `mega_form`. HP is intentionally
/// preserved from the base Pokemon (mega does not change max or current HP).
/// Items and move list stay untouched.
fn effective_combatant(c : Combatant, is_mega : Bool) -> Combatant {
  match (is_mega, c.mega_form) {
    (true, Some(m)) => {
      let base = c.pokemon
      let effective_pokemon : @model.Pokemon = {
        global_no: base.global_no,
        name_ja: m.name_ja,
        name_en: base.name_en,
        type1: m.type1,
        type2: m.type2,
        hp: base.hp,
        atk: m.atk,
        def_: m.def_,
        spa: m.spa,
        spd: m.spd,
        spe: m.spe,
        bst: base.hp + m.atk + m.def_ + m.spa + m.spd + m.spe,
        ability1: m.ability,
        ability2: "",
        dream_ability: "",
        weight: base.weight,
      }
      {
        pokemon: effective_pokemon,
        moves: c.moves,
        ability: m.ability,
        item: c.item,
        tera_type: c.tera_type,
        stat_system: c.stat_system,
        mega_form: c.mega_form,
      }
    }
    _ => c
  }
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
  atk_burn~ : Bool = false,
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
  let mean = s / 16
  // やけど + 物理技: 攻撃半減 (gen3+ ルール)。特殊 / 変化は影響なし。
  if atk_burn {
    match mv.category {
      @model.Physical => mean / 2
      _ => mean
    }
  } else {
    mean
  }
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
  // Mega form resolved flags. `atk_idx` / `my_attacker` identify the slot, and
  // the slot → mega_form mapping is fixed for a single switching-game run, so
  // 1 bit per side is enough to disambiguate base vs mega stats/type/ability
  // in the cache (no collisions across different mega species).
  atk_mega : Bool
  def_mega : Bool
  // Whether the attacker is burned. Only physical moves are affected (halved),
  // but including the flag for all categories keeps the cache key uniform; the
  // reducer silently no-ops for special / status moves.
  atk_burn : Bool
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
  atk_mega~ : Bool = false,
  def_mega~ : Bool = false,
  atk_burn~ : Bool = false,
) -> Int {
  let raw_attacker = if my_attacker {
    my_team[atk_idx]
  } else {
    opp_team[atk_idx]
  }
  let raw_defender = if my_attacker {
    opp_team[def_idx]
  } else {
    my_team[def_idx]
  }
  // Move list is identical across mega / base — read the move from the base
  // combatant so that the post-mega synthetic view (which reuses `moves`) is
  // not required here.
  let mv = raw_attacker.moves[mv_idx]
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
    atk_mega,
    def_mega,
    atk_burn,
  }
  match cache.data.get(key) {
    Some(v) => {
      cache.hits = cache.hits + 1
      v
    }
    None => {
      cache.misses = cache.misses + 1
      let attacker = effective_combatant(raw_attacker, atk_mega)
      let defender = effective_combatant(raw_defender, def_mega)
      let v = compute_mean_damage(
        attacker, defender, mv, atk_rank, def_rank, atk_burn=atk_burn,
      )
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
  let attacker_active = if attacker_is_me { ws.my_active } else { ws.opp_active }
  let defender_active = if attacker_is_me { ws.opp_active } else { ws.my_active }
  let attacker_ranks = if attacker_is_me { ws.my_ranks } else { ws.opp_ranks }
  let defender_ranks = if attacker_is_me { ws.opp_ranks } else { ws.my_ranks }
  let defender_hps = if attacker_is_me { ws.opp_hps } else { ws.my_hps }
  let dmg = mean_damage_cached(
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
  )
  defender_hps[defender_active] = clamp_zero(defender_hps[defender_active] - dmg)
  apply_stat_boost(attacker_ranks, attacker_move)
  let post_damage_state = ws_to_state(ws, bump_turn=false)
  maybe_apply_status_fanout(
    post_damage_state,
    not(attacker_is_me),
    target_active(post_damage_state, not(attacker_is_me)),
    if attacker_is_me { opp_team } else { my_team },
    attacker_move,
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
      final_outs.push((p1, bump_turn_only(s1)))
      continue
    }
    // Second actor newly slept / frozen mid-turn: skip their move.
    if action_blocked_by_fresh_status(second_pre_status, second_now_status) {
      final_outs.push((p1, bump_turn_only(s1)))
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
      final_outs.push((p1 * p2, bump_turn_only(s2)))
    }
  }
  final_outs
}

///|
/// Return a fresh copy of `state` with `turn` incremented by 1. Used at the
/// tail of `resolve_moves` once both attacker legs are fully resolved so the
/// intermediate snapshots don't prematurely advance the turn counter.
fn bump_turn_only(state : SwitchingGameState) -> SwitchingGameState {
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
    turn: state.turn + 1,
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
  let mut attack_event : (Bool, Int, @model.Move)? = None
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
      // Opponent attacks the freshly switched-in target. The target's mega
      // flag comes from its slot-level `my_megaed_new[i]` (rather than from
      // the out-going active's mega state).
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
        atk_mega=opp_mega_now,
        def_mega=my_megaed_new[i],
        atk_burn=is_burned(state.opp_status[state.opp_active]),
      )
      my_hps_new[i] = clamp_zero(my_hps_new[i] - dmg)
      apply_stat_boost(opp_ranks_new, opp_team[state.opp_active].moves[mj])
      attack_event = Some((false, i, opp_team[state.opp_active].moves[mj]))
    }
    (UseMove(mi), Switch(j)) => {
      opp_active_new = j
      for k in 0..<5 {
        opp_ranks_new[k] = 0
      }
      opp_status_new[state.opp_active] = reset_toxic_counter_on_switch(
        opp_status_new[state.opp_active],
      )
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
        atk_mega=my_mega_now,
        def_mega=opp_megaed_new[j],
        atk_burn=is_burned(state.my_status[state.my_active]),
      )
      opp_hps_new[j] = clamp_zero(opp_hps_new[j] - dmg)
      apply_stat_boost(my_ranks_new, my_team[state.my_active].moves[mi])
      attack_event = Some((true, j, my_team[state.my_active].moves[mi]))
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
      if s == 0 {
        // Speed tie: return two outcomes so the caller averages successor
        // *values* (not states). resolve_moves recomputes the second hit's
        // damage after the first actor's stat boosts.
        let outs : Array[(Double, SwitchingGameState)] = []
        for half in resolve_moves(
          state, mi, mj, true, my_mega_now, opp_mega_now,
          my_team, opp_team, dmg_cache,
        ) {
          outs.push((0.5 * half.0, half.1))
        }
        for half in resolve_moves(
          state, mi, mj, false, my_mega_now, opp_mega_now,
          my_team, opp_team, dmg_cache,
        ) {
          outs.push((0.5 * half.0, half.1))
        }
        return outs
      } else {
        let my_first = s > 0
        return resolve_moves(
          state, mi, mj, my_first, my_mega_now, opp_mega_now,
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
    turn: state.turn + 1,
  }
  match attack_event {
    None => [(1.0, base_state)]
    Some((attacker_is_me, target_slot, used_move)) =>
      maybe_apply_status_fanout(
        base_state,
        not(attacker_is_me),
        target_slot,
        if attacker_is_me { opp_team } else { my_team },
        used_move,
      )
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
    state.my_status[state.my_active], my_action, my_acc,
  )
  let opp_attempts = per_side_attempt(
    state.opp_status[state.opp_active], opp_action, opp_acc,
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
        let ns = apply_eot(ns_pre_eot, my_team, opp_team)
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
  let mut my_active = state.my_active
  let mut opp_active = state.opp_active
  let mut my_mega_used = state.my_mega_used
  let mut opp_mega_used = state.opp_mega_used
  let mut attack_event : (Bool, Int, @model.Move)? = None
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
      let mega_now = my_megaed[state.my_active] || mega_trigger
      let burn = is_burned(state.my_status[state.my_active])
      let dmg = mean_damage_cached(
        dmg_cache, true, state.my_active, my_ranks, state.opp_active, opp_ranks,
        mi, my_team, opp_team, atk_mega=mega_now, def_mega=opp_megaed[state.opp_active],
        atk_burn=burn,
      )
      opp_hps[state.opp_active] = clamp_zero(opp_hps[state.opp_active] - dmg)
      apply_stat_boost(my_ranks, my_team[state.my_active].moves[mi])
      attack_event = Some(
        (true, state.opp_active, my_team[state.my_active].moves[mi]),
      )
    }
    (false, UseMove(mj)) => {
      if mega_trigger {
        opp_megaed[state.opp_active] = true
        opp_mega_used = true
      }
      let mega_now = opp_megaed[state.opp_active] || mega_trigger
      let burn = is_burned(state.opp_status[state.opp_active])
      let dmg = mean_damage_cached(
        dmg_cache, false, state.opp_active, opp_ranks, state.my_active, my_ranks,
        mj, my_team, opp_team, atk_mega=mega_now, def_mega=my_megaed[state.my_active],
        atk_burn=burn,
      )
      my_hps[state.my_active] = clamp_zero(my_hps[state.my_active] - dmg)
      apply_stat_boost(opp_ranks, opp_team[state.opp_active].moves[mj])
      attack_event = Some(
        (false, state.my_active, opp_team[state.opp_active].moves[mj]),
      )
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
    turn: state.turn + 1,
  }
  match attack_event {
    None => [(1.0, base_state)]
    Some((attacker_is_me, target_slot, used_move)) =>
      maybe_apply_status_fanout(
        base_state,
        not(attacker_is_me),
        target_slot,
        if attacker_is_me { opp_team } else { my_team },
        used_move,
      )
  }
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
  let actions_me = alive_actions(
    state.my_active, state.my_hps, my_team, state.my_mega_used,
  )
  let actions_opp = alive_actions(
    state.opp_active, state.opp_hps, opp_team, state.opp_mega_used,
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
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: Array::make(my_team.length(), false),
    opp_megaed: Array::make(opp_team.length(), false),
    my_status: zero_status(my_team.length()),
    opp_status: zero_status(opp_team.length()),
    turn: 0,
  }
  let cache : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  let stats = new_stats()
  let dmg_cache = new_damage_cache()
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
pub fn alive_actions(
  active : Int,
  hps : Array[Int],
  team : Array[Combatant],
  mega_used : Bool,
) -> Array[ActionKind] {
  let out : Array[ActionKind] = []
  let active_alive = hps[active] > 0
  if active_alive {
    for i in 0..<team[active].moves.length() {
      out.push(UseMove(i))
    }
  }
  if active_alive && can_mega(active, hps, team, mega_used) {
    for i in 0..<team[active].moves.length() {
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
