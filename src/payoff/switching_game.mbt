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
  // Volatile "must recharge this turn" flag per team slot. Separate from
  // StatusCondition so major conditions (burn / paralysis / sleep) can
  // coexist with a recharge turn. Set by recharge moves (Hyper Beam etc.)
  // on the turn after the hit lands; consumed when the slot's next `UseMove`
  // is attempted and cleared to `false` at the end of the same turn.
  // Reset on switch (fresh entrant never starts recharging).
  my_must_recharge : Array[Bool]
  opp_must_recharge : Array[Bool]
  // P5 (#97): per-slot held-item consumption flag. Set to `true` once the
  // slot's held item triggers (resist berry weakness reduction, きあいのタスキ
  // KO survival, フィラのみ HP heal). Persists across switches — a consumed
  // berry doesn't reappear when the holder switches back in. Length = team
  // size; aligns with my_megaed / my_status indexing.
  my_item_consumed : Array[Bool]
  opp_item_consumed : Array[Bool]
  // Per-slot bitmask of moves used so far (bit `i` = move index `i` was used
  // at least once). Persists across switches — とっておき (Last Resort) needs
  // every other move to have been used before it becomes legal, and that
  // memory survives switch-out.
  // Convention: length 0 = "not tracked" (test fixtures default; alive_actions
  // skips the Last Resort filter). Length = team size = "tracked" (production
  // initial state). Mixed length is treated as untracked for safety.
  my_moves_used : Array[Int]
  opp_moves_used : Array[Int]
  turn : Int
} derive(Debug, Eq, Hash)

///|
/// Fresh `None`-filled status array sized for a team. Used at game entry
/// and in test construction.
pub fn zero_status(team_size : Int) -> Array[@model.StatusCondition] {
  Array::make(team_size, @model.None)
}

///|
/// In-place: set bit `mv_idx` on `masks[slot]`. Length-0 masks (untracked
/// fixtures) and out-of-range slots are no-ops; production state always has
/// `length == team size`.
fn mark_move_used_inplace(masks : Array[Int], slot : Int, mv_idx : Int) -> Unit {
  if slot < 0 || slot >= masks.length() {
    return
  }
  if mv_idx < 0 {
    return
  }
  masks[slot] = masks[slot] | (1 << mv_idx)
}

///|
/// Return a fresh `masks` copy with bit `mv_idx` set on slot `slot`. Used
/// when a state must be passed by value (e.g. into `resolve_moves`) without
/// mutating the caller's array.
fn mark_move_used(masks : Array[Int], slot : Int, mv_idx : Int) -> Array[Int] {
  let out = masks.copy()
  mark_move_used_inplace(out, slot, mv_idx)
  out
}

///|
/// Check whether `mv_idx` is the `とっておき` (Last Resort) slot on this team
/// member and whether it is currently barred. Last Resort is barred until
/// every OTHER move on this slot has been used at least once during the
/// battle (used-state persists across switches in mainline rules).
///
/// `moves_used` is the slot-level bitmask. Length 0 (untracked) is treated
/// as "not barred" — keeps legacy test fixtures, which never construct
/// Last-Resort movesets, working without per-fixture updates.
fn last_resort_barred(
  moves : Array[@model.Move],
  mv_idx : Int,
  moves_used_for_slot : Int,
) -> Bool {
  if mv_idx < 0 || mv_idx >= moves.length() {
    return false
  }
  if moves[mv_idx].name != "とっておき" {
    return false
  }
  // 1 技だけ覚えている (= とっておき のみ) は条件を満たしようがないので
  // mainline でもそのまま発動する。
  if moves.length() <= 1 {
    return false
  }
  for j in 0..<moves.length() {
    if j == mv_idx {
      continue
    }
    if ((moves_used_for_slot >> j) & 1) == 0 {
      return true
    }
  }
  false
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
} derive(Debug)


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
} derive(Debug, Eq)

///|
/// Live progress events emitted from the SwitchingGame DP and the screened
/// pipeline. Sinks may format these to stderr (`--progress=stderr`) or to
/// JSON Lines (`--progress=json`); the default sink is a no-op.
///
/// - `PhaseStart(name, total)` — Phase A/B/C boundary; `total` is the unit
///   count for the phase (cells for A/C, 1 for B).
/// - `PhaseProgress(name, current, total)` — increment marker within a phase.
/// - `PhaseEnd(name)` — phase completion.
/// - `CellStart(team_indices, opp_indices, row, col, phase)` — entering a
///   selection cell of the team-payoff matrix. `row` / `col` are the indices
///   in the original `combinations_with_lead(n, k)` enumeration
///   (0..size_a × 0..size_b), so a visualiser can paint a fixed grid (e.g.
///   60×60 for 6-vs-6 single) regardless of whether the screened pipeline
///   has dropped some cells. `phase` carries the originating phase name
///   ("screening" / "dp-refine" / "dp-full") so a visualiser can colour the
///   cell without consulting the surrounding `PhaseStart` / `PhaseEnd`
///   brackets — under parallel fan-out, child shards write to the parent's
///   inherited stderr, and the kernel pipe does not guarantee ordering
///   between a child's last `CellDone` and the parent's next `PhaseStart`,
///   so phase has to travel with the event.
/// - `CellDone(team_indices, opp_indices, row, col, phase)` — paired
///   completion event for `CellStart`. Emitted when the per-cell compute
///   finishes; carries the same `phase` string as its matching `CellStart`.
/// - `DpNode(visited, hits, depth, rows, cols, outcomes, classification)` —
///   DP recursion checkpoint (emitted from `value()` every
///   `ValueStats::log_every` cache misses). `visited` is the running miss
///   count, `hits` the running cache-hit count, `depth` the recursion depth
///   of the sample node, `rows × cols` the per-turn action matrix at that
///   node, `outcomes` the stochastic edges walked from it, and
///   `classification` one of `"saddle"` / `"nash"` / `"pruned"` (β-cutoff) /
///   `"alpha_pruned"` (α-cutoff at node level when `upper ≤ alpha + eps`).
pub(all) enum ProgressEvent {
  PhaseStart(String, Int)
  PhaseProgress(String, Int, Int)
  PhaseEnd(String)
  CellStart(Array[Int], Array[Int], Int, Int, String)
  CellDone(Array[Int], Array[Int], Int, Int, String)
  DpNode(Int, Int, Int, Int, Int, Int, String)
} derive(Debug)

///|
/// Observability hooks for memoization: callers can inspect hit/miss counts
/// without relying on wall-clock timing. Used by tests and by CLI diagnostics
/// to verify that larger `turn_limit` values stay cache-bound.
///
/// The `progress` closure receives DP-node checkpoints when `log_every > 0`.
/// `last_logged` tracks the miss count at the previous emission so the gating
/// stays O(1) per visit.
pub(all) struct ValueStats {
  mut hits : Int
  mut misses : Int
  mut cached_states : Int
  mut last_logged : Int
  log_every : Int
  progress : (ProgressEvent) -> Unit
}

///|
fn noop_progress(_event : ProgressEvent) -> Unit {
  ()
}

///|
pub fn new_stats() -> ValueStats {
  {
    hits: 0,
    misses: 0,
    cached_states: 0,
    last_logged: 0,
    log_every: 0,
    progress: noop_progress,
  }
}

///|
/// Build a `ValueStats` that emits `DpNode` events through `progress` every
/// `log_every` cache misses. `log_every <= 0` disables emission and returns a
/// value identical to `new_stats()` (the supplied `progress` closure is
/// discarded in favour of `noop_progress`), so disabled-progress callers stay
/// observationally equivalent to the legacy `new_stats()` path.
pub fn new_stats_with_progress(
  progress : (ProgressEvent) -> Unit,
  log_every : Int,
) -> ValueStats {
  if log_every <= 0 {
    return new_stats()
  }
  {
    hits: 0,
    misses: 0,
    cached_states: 0,
    last_logged: 0,
    log_every,
    progress,
  }
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
  if !(my_alive) {
    return Some(-1.0)
  }
  if !(opp_alive) {
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
        forms: [],
      }
      // mega 後は base が変化するため、pre-mega `actual_stats` はそのまま
      // 使えない。`stat_points` + `nature` が残っていれば post-mega base から
      // 実数値を再計算する。残っていないときは engine 既定投資に落とす。
      let post_mega_actual_stats = recompute_actual_stats_for_mega(
        effective_pokemon, c,
      )
      {
        pokemon: effective_pokemon,
        moves: c.moves,
        ability: m.ability,
        item: c.item,
        tera_type: c.tera_type,
        stat_system: c.stat_system,
        mega_form: c.mega_form,
        nature: c.nature,
        stat_points: c.stat_points,
        actual_stats: post_mega_actual_stats,
        ivs: c.ivs,
      }
    }
    _ => c
  }
}

///|
/// Recompute `actual_stats` for the post-mega Pokemon using the combatant's
/// `stat_points` and `nature`. Returns `None` when either input is missing
/// (the caller drops `actual_stats` so the engine falls back to its default
/// investment for the post-mega form).
///
/// HP is not changed by mega evolution, so HP is taken from pre-mega
/// `actual_stats` when available (preserves user spread even if `stat_points`
/// HP differs from the "implied" recomputation). Other stats are always
/// recomputed from the post-mega base to stay in sync with the post-mega form.
///
/// Standard format: `pre.ivs` が与えられていればユーザ指定の IV 配列を
/// そのまま流し込み、欠損時のみ 31 揃い (完璧個体) を仮定する。0 Atk
/// 特殊アタッカーや 0 Spe トリル等で IV を敢えて下げた構築は、ここで IV を
/// 引き継がないと post-mega の A / Spe が「勝手に 31 基準」へ流されて
/// しまうため、pre-mega `actual_stats` で守った user spread が壊れる。
/// Champions format は IV 廃止なので `ivs` フィールドは読み飛ばす。
fn recompute_actual_stats_for_mega(
  post_mega : @model.Pokemon,
  pre : Combatant,
) -> Array[Int]? {
  let sp = match pre.stat_points {
    Some(p) if p.length() == 6 => p
    _ => return None
  }
  let nature = match pre.nature {
    Some(n) => n
    None => return None
  }
  let ivs : FixedArray[Int] = match pre.ivs {
    Some(arr) if arr.length() == 6 =>
      [arr[0], arr[1], arr[2], arr[3], arr[4], arr[5]]
    _ => [31, 31, 31, 31, 31, 31]
  }
  let model : @damage.StatModel = match pre.stat_system {
    @model.Champions => @damage.Champions
    @model.Standard => @damage.Standard(ivs~)
  }
  let bases : FixedArray[Int] = [
    post_mega.hp, post_mega.atk, post_mega.def_, post_mega.spa, post_mega.spd,
    post_mega.spe,
  ]
  let stat_indices : FixedArray[@model.StatIndex] = [
    HP, Atk, Def, SpA, SpD, Spe,
  ]
  let out : Array[Int] = Array::make(6, 0)
  // HP: mega は HP を変えないので、pre-mega の actual_stats[0] が与えられて
  // いればそちらを優先する (stat_points と actual_stats が独立に書かれたときに
  // actual_stats 側を尊重する方針)。無ければ stat_points から再計算する。
  out[0] = match pre.actual_stats {
    Some(a) if a.length() == 6 => a[0]
    _ => model.calc_hp(bases[0], sp[0])
  }
  for i in 1..<6 {
    let (num, den) = @model.nature_mult_int(nature, stat_indices[i])
    out[i] = model.calc_other(i, bases[i], sp[i], num, den)
  }
  Some(out)
}

///|
/// Apply burn to a pre-burn mean damage. Single source of truth for burn
/// semantics so L1-only and L2-backed paths cannot drift: both reduce the
/// 16-roll table to a mean first (`s / 16`), then this helper halves the
/// mean when the attacker is burned and the move is Physical. Special /
/// Status moves are unaffected.
fn apply_burn_to_mean(
  mean : Int,
  category : @model.MoveCategory,
  atk_burn : Bool,
) -> Int {
  if atk_burn {
    match category {
      @model.Physical => mean / 2
      _ => mean
    }
  } else {
    mean
  }
}

///|
/// Convert engine `r.variants[]` to per-variant `DamageOutcome` records
/// with burn folded in. Single source of truth for the engine-result →
/// outcome adapter, used by both `compute_damage_variants` (in-memory
/// path) and `compute_and_populate_disk` (L2 populate path) so the per-
/// variant 16-roll mean + burn computation lives in exactly one place.
fn outcomes_from_calc_result(
  r : @model.DamageCalcResult,
  category : @model.MoveCategory,
  atk_burn : Bool,
) -> Array[@model.DamageOutcome] {
  let outcomes : Array[@model.DamageOutcome] = []
  for i = 0; i < r.variants.length(); i = i + 1 {
    let v = r.variants[i]
    let mut s = 0
    for j in 0..<16 {
      s += v.total_damages[j]
    }
    let mean = apply_burn_to_mean(s / 16, category, atk_burn)
    outcomes.push({
      probability: v.probability,
      mean_damage: mean,
      hits_count: v.hits_count,
      hit_steps: v.hits,
    })
  }
  outcomes
}

///|
/// Mirror of `outcomes_from_calc_result` for the L2 read-side path: convert
/// `ParsedVariant`s decoded from the disk JSON to `DamageOutcome` with burn
/// folded in. `hit_steps` is empty because the wire format intentionally
/// omits per-hit detail to keep entries compact — call sites that need
/// per-hit metadata recompute via `calc_damage`.
fn outcomes_from_parsed(
  parsed : Array[@damage_cache.ParsedVariant],
  category : @model.MoveCategory,
  atk_burn : Bool,
) -> Array[@model.DamageOutcome] {
  let outcomes : Array[@model.DamageOutcome] = []
  for i = 0; i < parsed.length(); i = i + 1 {
    let v = parsed[i]
    let n = v.total_damages.length()
    let raw_mean = if n == 0 {
      0
    } else {
      let mut s = 0
      for j = 0; j < n; j = j + 1 {
        s = s + v.total_damages[j]
      }
      s / n
    }
    let mean = apply_burn_to_mean(raw_mean, category, atk_burn)
    outcomes.push({
      probability: v.probability,
      mean_damage: mean,
      hits_count: v.hits_count,
      hit_steps: [],
    })
  }
  outcomes
}

///|
/// Probability-weighted mean of `DamageOutcome`s, floored to Int. Floors
/// at the very end (not per-variant) to match the legacy `s / 16`
/// integer-division convention exactly. Single source of truth shared by
/// L1 (`compute_mean_damage`), L2 read (`mean_damage_via_disk`), and L2
/// populate (`compute_and_populate_disk`) so future changes to the floor
/// convention land in one place.
fn weighted_mean_floor(outcomes : Array[@model.DamageOutcome]) -> Int {
  let mut acc = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    acc = acc + outcomes[i].probability * outcomes[i].mean_damage.to_double()
  }
  acc.to_int()
}

///|
/// Compute the mean damage for the given `(attacker, defender, move, ranks)`
/// tuple directly, without cache lookup. The numeric kernel underneath
/// `mean_damage_cached` — call-sites should reach it via the cache wrapper
/// so the 16-roll table is not recomputed on every state transition.
///
/// Phase 2-B (#91): now derives the scalar mean from `r.variants[]` so it
/// matches `damage_variants_cached`'s probability-weighted aggregation.
/// The legacy `r.damages` path used the most-likely variant's 16-roll
/// average, which collapsed Triple Axel / Random2to5 / PopulationBomb
/// into a single hits_count instead of weighting all hit-count branches.
fn compute_mean_damage(
  attacker : Combatant,
  defender : Combatant,
  mv : @model.Move,
  atk_rank : Int,
  def_rank : Int,
  atk_burn~ : Bool = false,
) -> Int {
  weighted_mean_floor(
    compute_damage_variants(
      attacker, defender, mv, atk_rank, def_rank, atk_burn~,
    ),
  )
}

///|
/// #91: Compute hit-count-fanned damage outcomes for the payoff layer.
///
/// Returns one `DamageOutcome` per chance-node leaf (1 entry for single
/// hits / Skill Link, 3 for Triple Axel, 4 for Random2to5, 10 for
/// PopulationBomb). `mean_damage` is the variant's 16-roll mean folded
/// through `apply_burn_to_mean` so callers do not need to re-apply burn
/// — matching the contract `compute_mean_damage` already exposes.
///
/// Immune matchups produce `[(1.0, 0, 0, [])]` so callers always have at
/// least one outcome to fan out. `hits_count = 0` is *not* used to
/// represent move miss — that is `per_side_attempt`'s job.
fn compute_damage_variants(
  attacker : Combatant,
  defender : Combatant,
  mv : @model.Move,
  atk_rank : Int,
  def_rank : Int,
  atk_burn~ : Bool = false,
) -> Array[@model.DamageOutcome] {
  // Status moves and zero-power moves never deal damage. Mirror the early
  // return in `mean_damage_cached` so the variants pipeline does not invent
  // a stray damage point from the engine's variant table for moves whose
  // power was clamped to 0 upstream.
  if mv.power <= 0 {
    return [
      { probability: 1.0, mean_damage: 0, hits_count: 1, hit_steps: [] },
    ]
  }
  let r = @damage.calc_damage(
    build_input_with_ranks(attacker, defender, mv, atk_rank, def_rank),
  )
  if r.is_immune {
    return [
      {
        probability: 1.0,
        mean_damage: 0,
        hits_count: 0,
        hit_steps: [],
      },
    ]
  }
  outcomes_from_calc_result(r, mv.category, atk_burn)
}

///|
/// Phase 2-D (#91): expand a single attack-resolution into chance-node leaves
/// fanning out across hit-count variants.
///
/// For each `DamageOutcome` returned by `compute_damage_variants` (1 entry for
/// Single / Skill Link, 3 for Triple Axel, 4 for Random2to5, 10 for
/// PopulationBomb), the variant-specific `mean_damage` is applied to defender
/// HP and the resulting per-variant state is threaded through the four
/// post-hit fanouts with `hits_count` fixed to that variant's count. The four
/// fanouts were extended in Phase 2-C to accept `hits_count` so per-hit
/// secondaries (status secondary, contact proc) compound across the variant's
/// hits without double-counting through the legacy `resolve_hit_distribution`
/// fold.
///
/// Returns leaves with `outcome.probability * sub_leaf_probability` so summing
/// over all leaves equals 1.0 within float drift bounds.
fn apply_damage_variants_fanout(
  state : SwitchingGameState,
  outcomes : Array[@model.DamageOutcome],
  attacker_is_me~ : Bool,
  attacker_active~ : Int,
  defender_active~ : Int,
  attacker_move~ : @model.Move,
  attacker_team~ : Array[Combatant],
  defender_team~ : Array[Combatant],
  pre_dmg_defender_hp~ : Int,
) -> Array[(Double, SwitchingGameState)] {
  // Phase 2-E (#91): outcomes are resolved by the caller via
  // `damage_variants_cached` so that the engine's variant table is
  // memoised across recursion. Inside this helper we own the per-variant
  // state mutation and the four post-hit fanouts only.
  let target_is_me = !(attacker_is_me)
  let target_slot = defender_active
  let attacker_slot = attacker_active
  let leaves : Array[(Double, SwitchingGameState)] = []
  for i = 0; i < outcomes.length(); i = i + 1 {
    let outcome = outcomes[i]
    let state_dmg = with_hp_damage(state, target_is_me, target_slot, outcome.mean_damage)
    // Phase 2-E (#91): per-variant post-hit state effects so recoil /
    // self_ko / recharge / stat_effects compound on the variant-specific
    // damage rather than a single mean. State remains immutable; with_-
    // post_hit_effects produces a fresh copy with updated arrays.
    let state_v = with_post_hit_effects(
      state_dmg,
      attacker_is_me,
      attacker_slot,
      target_slot,
      attacker_move,
      outcome.mean_damage,
    )
    let sub = compose_fanouts(state_v, [
      fn(s) {
        apply_item_pre_damage_proc_fanout(
          s,
          target_is_me,
          target_slot,
          defender_team,
          attacker_team,
          pre_dmg_defender_hp,
          attacker_move,
          hits_count=outcome.hits_count,
        )
      },
      fn(s) {
        apply_item_post_damage_proc_fanout(
          s,
          target_is_me,
          target_slot,
          defender_team,
          attacker_team,
          pre_dmg_defender_hp,
          attacker_move,
          hits_count=outcome.hits_count,
        )
      },
      fn(s) {
        maybe_apply_status_fanout(
          s,
          target_is_me,
          target_slot,
          defender_team,
          attacker_move,
          hits_count=outcome.hits_count,
        )
      },
      fn(s) {
        apply_contact_proc_fanout(
          s,
          attacker_is_me,
          attacker_slot,
          target_slot,
          attacker_team,
          defender_team,
          attacker_move,
          hits_count=Some(outcome.hits_count),
        )
      },
    ])
    for j = 0; j < sub.length(); j = j + 1 {
      let (p, s) = sub[j]
      leaves.push((outcome.probability * p, s))
    }
  }
  leaves
}

///|
/// Phase 2-D (#91): copy `state` and subtract `damage` from the defender HP
/// at `target_slot`, clamped to 0. Other arrays are spread-shared from the
/// input state (post-hit fanouts return fresh states rather than mutating).
fn with_hp_damage(
  state : SwitchingGameState,
  target_is_me : Bool,
  target_slot : Int,
  damage : Int,
) -> SwitchingGameState {
  let my_hps = state.my_hps.copy()
  let opp_hps = state.opp_hps.copy()
  if target_is_me {
    my_hps[target_slot] = clamp_zero(my_hps[target_slot] - damage)
  } else {
    opp_hps[target_slot] = clamp_zero(opp_hps[target_slot] - damage)
  }
  { ..state, my_hps, opp_hps }
}

///|
/// Phase 2-E (#91): immutable counterpart of `resolve_post_hit_effects`.
///
/// Applies the same fixed-order post-hit side effects (stat_effects on
/// attacker / defender, recoil to attacker, self_ko, recharge) but
/// returns a fresh state instead of mutating workspace arrays. Used by
/// `apply_damage_variants_fanout` so each chance-node leaf gets its own
/// per-variant recoil / self_ko / recharge bookkeeping based on the
/// variant's `mean_damage`.
fn with_post_hit_effects(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_active : Int,
  defender_active : Int,
  mv : @model.Move,
  dmg : Int,
) -> SwitchingGameState {
  let my_hps = state.my_hps.copy()
  let opp_hps = state.opp_hps.copy()
  let my_ranks = state.my_ranks.copy()
  let opp_ranks = state.opp_ranks.copy()
  let my_must_recharge = state.my_must_recharge.copy()
  let opp_must_recharge = state.opp_must_recharge.copy()
  let attacker_hps = if attacker_is_me { my_hps } else { opp_hps }
  let attacker_ranks = if attacker_is_me { my_ranks } else { opp_ranks }
  let defender_hps = if attacker_is_me { opp_hps } else { my_hps }
  let defender_ranks = if attacker_is_me { opp_ranks } else { my_ranks }
  let attacker_must_recharge = if attacker_is_me {
    my_must_recharge
  } else {
    opp_must_recharge
  }
  let opp_alive = defender_hps[defender_active] > 0
  apply_stat_effects(attacker_ranks, defender_ranks, opp_alive, mv)
  apply_recoil(attacker_hps, attacker_active, mv, dmg)
  if mv.self_ko {
    attacker_hps[attacker_active] = 0
  }
  if mv.recharge && attacker_hps[attacker_active] > 0 {
    attacker_must_recharge[attacker_active] = true
  }
  {
    ..state,
    my_hps,
    opp_hps,
    my_ranks,
    opp_ranks,
    my_must_recharge,
    opp_must_recharge,
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
/// Apply `mv.stat_effects` in-place, routing each entry to either the
/// attacker's or the defender's rank array by its `target` field.
///
/// - `target = 0` → self (attacker). Always applied.
/// - `target = 1` → opp (defender). Skipped when `opp_alive` is `false`
///   (a hit that fainted the target doesn't land a rank drop).
/// Other target values are ignored for forward-compat.
///
/// Delta is added and clamped to `[-2, +2]` via `clamp_rank`.
fn apply_stat_effects(
  self_ranks : Array[Int],
  opp_ranks : Array[Int],
  opp_alive : Bool,
  mv : @model.Move,
) -> Unit {
  for eff in mv.stat_effects {
    let ranks = if eff.target == 0 {
      self_ranks
    } else if eff.target == 1 && opp_alive {
      opp_ranks
    } else {
      continue
    }
    if eff.stat >= 0 && eff.stat < ranks.length() {
      ranks[eff.stat] = clamp_rank(ranks[eff.stat] + eff.delta)
    }
  }
}

///|
/// Apply recoil HP loss to the attacker based on damage dealt. No-op when
/// `mv.recoil_num == 0` or `dmg <= 0`. Enforces a minimum of 1 HP loss for
/// any recoil move that actually landed (matches mainline behaviour on tiny
/// damage values), and clamps attacker HP at 0.
fn apply_recoil(
  attacker_hps : Array[Int],
  attacker_active : Int,
  mv : @model.Move,
  dmg : Int,
) -> Unit {
  if mv.recoil_num <= 0 || dmg <= 0 {
    return
  }
  let raw = dmg * mv.recoil_num / mv.recoil_den
  let recoil = if raw < 1 { 1 } else { raw }
  attacker_hps[attacker_active] = clamp_zero(
    attacker_hps[attacker_active] - recoil,
  )
}

///|
/// Workspace-mutating post-hit side effects (legacy attack-site helper).
///
/// As of Phase 2-E (#91) the production attack sites use `with_post_hit_-
/// effects` (immutable, per-variant) — but white-box tests and Monte Carlo
/// helpers still call this entry point directly to verify the underlying
/// recoil / self_ko / recharge / stat_effects ordering against a workspace
/// mutation. Keeping it preserves the semantic contract for both layers.
///
/// Order (deliberate — changing it alters observable behaviour):
///   1. opp-target `stat_effects` (gated on opp_alive)
///   2. self-target `stat_effects`
///   3. recoil (attacker HP loss; minimum 1 HP for any landed recoil hit)
///   4. self_ko (attacker HP forced to 0, regardless of `dmg`)
///   5. recharge (set only if attacker is still alive after 3 & 4)
///
/// `pub` purely so the lib build sees it as exported; production sites
/// have moved to `with_post_hit_effects`, leaving only white-box tests
/// as callers — which the lib check would otherwise flag as unused.
pub fn resolve_post_hit_effects(
  attacker_hps : Array[Int],
  attacker_active : Int,
  attacker_ranks : Array[Int],
  defender_hps : Array[Int],
  defender_active : Int,
  defender_ranks : Array[Int],
  attacker_must_recharge : Array[Bool],
  mv : @model.Move,
  dmg : Int,
) -> Unit {
  let opp_alive = defender_hps[defender_active] > 0
  apply_stat_effects(attacker_ranks, defender_ranks, opp_alive, mv)
  apply_recoil(attacker_hps, attacker_active, mv, dmg)
  if mv.self_ko {
    attacker_hps[attacker_active] = 0
  }
  if mv.recharge && attacker_hps[attacker_active] > 0 {
    attacker_must_recharge[attacker_active] = true
  }
}

