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
  // Stage 2 (healing-moves plan): infrastructure fields for upcoming healing /
  // weather / leech-seed / wish semantics. Stage 2 only adds these fields and
  // wires their propagation through every state helper / clone path; the
  // read/write logic that consumes them lands in stages 3–11. Default values
  // are no-op: `Weather::None` / `0` turns left / no slot seeded / `-1` wish
  // pending. Existing 943+ tests must observe identical behaviour with these
  // defaults — verified by stage 2's "behaviour unchanged" gate.
  // - weather: current battlefield weather. Read by WeatherDependent healing
  //   and post-hit weather-setting moves in later stages.
  // - weather_turns_left: remaining turns of `weather` (5 base, stone-extended
  //   not modeled in this PR). When 0 the next EOT clears to `None`.
  // - my_leech_seeded / opp_leech_seeded: per-slot seeded flag. Persists slot-
  //   scoped (Switch clears the switched-out slot's flag in stage 8).
  // - my_wish_turns / opp_wish_turns: pending Wish counter for the side's
  //   single active battle slot. pkdx's payoff layer models single battle —
  //   exactly one active slot per side — so the Wish state collapses to one
  //   scalar per side. This is observationally equivalent to a per-active-
  //   slot `Array[Int]` of length 1; we use `Int` directly to keep the state
  //   `derive(Hash)`-friendly and the struct lean. If pkdx ever extends to
  //   double battle, this becomes `Array[Int]` indexed by battle position.
  //   Sentinel values:
  //     `-1` = idle (no pending wish)
  //      `0` = fires on the next EOT (atomic tick-and-fire; see `apply_eot`)
  //     `>0` = ticks down by 1 each EOT
  //   Receiver semantics (mainline Gen5+): the heal lands on whoever is in
  //   the side's active battle slot at fire time — that is, the replacement
  //   if the original Wisher switched out. The "Wish, then switch to receive
  //   on the replacement" pattern is captured by `state.my_active` /
  //   `state.opp_active` being read at fire time inside `apply_eot`.
  //   Non-stacking: a fresh Wish overwrites a pending one (Gen5+ rule that
  //   only one Wish can be queued per side at any time). See `with_post_hit_
  //   effects`'s `Wish` arm and `model/move.mbt :: HealingEffect :: Wish`.
  //   Timing (set value = 2): used on turn T → counter = 2 at end of T's
  //   action phase → EOT(T) ticks 2→1 → EOT(T+1) ticks 1→0 and fires. So
  //   Wish set on turn T heals at EOT(T+1) — "at the end of the next turn"
  //   per Bulbapedia's Gen5+ wording. Two EOTs elapse between set and fire.
  weather : @model.Weather
  weather_turns_left : Int
  my_leech_seeded : Array[Bool]
  opp_leech_seeded : Array[Bool]
  // per-slot Protean/Libero ロックタイプ。""=未発動、型名=ロック中。
  // switch-out と mega でリセット（後段）。
  my_protean_locked : Array[String]
  opp_protean_locked : Array[String]
  my_wish_turns : Int
  opp_wish_turns : Int
  // Stage D (field semantics): mirror weather / weather_turns_left for terrain.
  // Stage D only adds these fields, threads them through state helpers, and
  // pins their inclusion in derive(Hash) so the DP cache cannot collide two
  // distinct states that differ only on terrain. The Move.field_set consumption,
  // EOT counter tick, Grassy heal, Misty status block, Psychic priority block,
  // and damage multipliers all land in stages E–G. Default no-op values:
  // Field::None / 0 turns left.
  // - field: current battlefield terrain. Read by damage / heal / status /
  //   priority arms in later stages.
  // - field_turns_left: remaining turns of `field` (5 base, terrain-extender
  //   not modeled in this PR). When 0 the next EOT clears to `None`.
  field : @model.Field
  field_turns_left : Int
  turn : Int
} derive(Debug, Eq, Hash)

///|
/// Fresh `None`-filled status array sized for a team. Used at game entry
/// and in test construction.
pub fn zero_status(team_size : Int) -> Array[@model.StatusCondition] {
  Array::make(team_size, @model.None)
}

///|
/// Default value for the per-side Wish pending counter. `-1` encodes "no
/// pending wish" so we can keep `wish_turns : Int` (scalar) and stay
/// derive(Hash)-friendly. Values:
///   -1 = idle (no Wish pending)
///    0 = fires on the next EOT
///   >0 = ticks down
/// `_team_size` is unused (kept for API symmetry with `zero_status`; the
/// underscore prefix silences the MoonBit unused-parameter warning).
pub fn no_wish_pending(_team_size : Int) -> Int {
  -1
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
  { hits: 0, misses: 0, cached_states: 0, last_logged: 0, log_every, progress }
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
  if !my_alive {
    return Some(-1.0)
  }
  if !opp_alive {
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
///
/// Precedence (適用順):
///   1. mega form 解決 — `is_mega && mega_form` のとき type/ability/stats を override
///   2. tera 中 (`c.tera_type != ""`) は Protean override 無効 — テラスタルが
///      タイプを支配し、後段の Tera 処理 (engine の `tera_type` 経路) に委ねる
///   3. Protean lock を最後に適用 — `protean_locked != "" && tera_type == ""` の
///      とき返す Pokemon を `type1=protean_locked, type2=""` に上書きする
///      (へんげんじざい / リベロ は使用者を変化技タイプの単タイプにする)
///
/// override を最後に適用することで mega 解決結果にも一律でかぶせられる。mega と
/// Protean は同ターン両立しない (mega が Protean をリセットする) が、順序非依存に
/// するため override を末尾に置く。
fn effective_combatant(
  c : Combatant,
  is_mega : Bool,
  protean_locked? : String = "",
) -> Combatant {
  let base_or_mega : Combatant = match (is_mega, c.mega_form) {
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
  // Protean lock: tera 中は型固定なので override しない (テラスが支配)。
  if protean_locked != "" && base_or_mega.tera_type == "" {
    let p = base_or_mega.pokemon
    let locked_pokemon : @model.Pokemon = {
      ..p,
      type1: protean_locked,
      type2: "",
    }
    { ..base_or_mega, pokemon: locked_pokemon }
  } else {
    base_or_mega
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
    post_mega.hp,
    post_mega.atk,
    post_mega.def_,
    post_mega.spa,
    post_mega.spd,
    post_mega.spe,
  ]
  let stat_indices : FixedArray[@model.StatIndex] = [
    HP,
    Atk,
    Def,
    SpA,
    SpD,
    Spe,
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
  atk_burn? : Bool = false,
  atk_ranks_full? : Array[Int]? = None,
  def_ranks_full? : Array[Int]? = None,
  weather? : @model.Weather = @model.Weather::None,
  field? : @model.Field = @model.Field::None,
  protean_consumed? : Bool = false,
) -> Int {
  weighted_mean_floor(
    compute_damage_variants(
      attacker,
      defender,
      mv,
      atk_rank,
      def_rank,
      atk_burn~,
      atk_ranks_full~,
      def_ranks_full~,
      weather~,
      field~,
      protean_consumed~,
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
  atk_burn? : Bool = false,
  allow_reflect? : Bool = true,
  atk_ranks_full? : Array[Int]? = None,
  def_ranks_full? : Array[Int]? = None,
  weather? : @model.Weather = @model.Weather::None,
  field? : @model.Field = @model.Field::None,
  protean_consumed? : Bool = false,
) -> Array[@model.DamageOutcome] {
  // Status moves and zero-power moves never deal damage. Mirror the early
  // return in `mean_damage_cached` so the variants pipeline does not invent
  // a stray damage point from the engine's variant table for moves whose
  // power was clamped to 0 upstream.
  if mv.power <= 0 {
    return [{ probability: 1.0, mean_damage: 0, hits_count: 1, hit_steps: [] }]
  }
  // 反射技 (カウンター / ミラーコート / メタルバースト / ほうふく) は通常の
  // 威力ベース計算を走らせず、相手の各候補攻撃技から「後手確率 × 命中確率 ×
  // Step1 期待値」の平均 × 反射倍率として静的評価する。Step1 計算は反転再帰
  // (defender→attacker) で行うため、再入を構造的に防ぐ `allow_reflect=false`
  // を渡す。`*_ranks_full` が渡されていれば各候補技のカテゴリで rank を再
  // 振り分けし、外側の反射技カテゴリで一括ディスパッチされた値を使わない。
  if allow_reflect {
    match @damage.is_reflect_move(mv.name) {
      Some(kind) =>
        return reflect_damage_outcomes(
          kind,
          attacker,
          defender,
          atk_rank,
          def_rank,
          atk_burn~,
          atk_ranks_full~,
          def_ranks_full~,
          weather~,
          field~,
        )
      None => ()
    }
  }
  let r = @damage.calc_damage(
    build_input_with_ranks(
      attacker,
      defender,
      mv,
      atk_rank,
      def_rank,
      weather~,
      field~,
      protean_consumed~,
    ),
  )
  if r.is_immune {
    return [{ probability: 1.0, mean_damage: 0, hits_count: 0, hit_steps: [] }]
  }
  outcomes_from_calc_result(r, mv.category, atk_burn)
}

///|
/// Aggregate reflect-move outcomes for the nash payoff matrix.
///
/// `attacker` is the reflect user, `defender` is the opponent whose attacks
/// are being reflected. We iterate the opponent's moves, keep only those the
/// reflect kind accepts (Counter→physical, MirrorCoat→special, MetalBurst /
/// Revenge→both), skip reflect moves (no double-reflect loops), compute each
/// candidate's mean Step1 damage via reverse `compute_damage_variants`
/// (`allow_reflect=false` to lock out further recursion), then weight by
/// `p_slow_i × p_hit_i` and average.
///
/// Rank routing: `atk_ranks_full` / `def_ranks_full` are the FULL 5-slot
/// `[A, B, C, D, S]` rank arrays of the reflect user / opponent respectively.
/// When provided, Step1 picks `(attacker_rank, defender_rank)` per
/// `mv_i.category` instead of reusing the outer reflect-move-category
/// dispatch — Mirror Coat's outer ranks resolve to (SpA, SpD) but Step1 for
/// a physical candidate needs (opponent Atk, our Def), and Metal Burst /
/// Comeuppance accept both categories so any single fixed pair would
/// mis-evaluate mixed candidates. `None` falls back to the pre-dispatched
/// `atk_rank` / `def_rank` for the test fixtures that pass rank 0 directly.
///
/// MVP simplifications:
///   - Speed ranks default to 0 (base speed comparison). Compute-time speed
///     rank is not propagated through `compute_damage_variants` today.
///   - Status / burn of the opponent side is not propagated into Step 1.
fn reflect_damage_outcomes(
  kind : @damage.ReflectKind,
  attacker : Combatant,
  defender : Combatant,
  atk_rank : Int,
  def_rank : Int,
  atk_burn~ : Bool,
  atk_ranks_full? : Array[Int]? = None,
  def_ranks_full? : Array[Int]? = None,
  weather? : @model.Weather = @model.Weather::None,
  field? : @model.Field = @model.Field::None,
) -> Array[@model.DamageOutcome] {
  let _ = atk_burn
  // Type immunity check: reflect move's own type vs the OPPONENT (defender,
  // because the reflect damage is dealt back to them).
  let reflect_type = @damage.reflect_move_type(kind)
  let type_immune = match @types.type_from_jp(reflect_type) {
    Some(rt) =>
      match @types.type_from_jp(defender.pokemon.type1) {
        Some(t1) => {
          let t2 = if defender.pokemon.type2.length() > 0 {
            @types.type_from_jp(defender.pokemon.type2)
          } else {
            None
          }
          @types.get_dual_effectiveness(rt, t1, t2) == 0.0
        }
        None => false
      }
    None => false
  }
  if type_immune {
    return [{ probability: 1.0, mean_damage: 0, hits_count: 1, hit_steps: [] }]
  }
  // Filter candidate incoming moves: category accepted, non-zero power,
  // and itself non-reflect (so a reflect-only defender produces 0).
  let mut accumulator : Double = 0.0
  let mut candidate_count = 0
  for i = 0; i < defender.moves.length(); i = i + 1 {
    let mv_i = defender.moves[i]
    if mv_i.power <= 0 {
      continue
    }
    if @damage.is_reflect_move(mv_i.name) is Some(_) {
      continue
    }
    if !@damage.reflect_accepts_category(kind, mv_i.category) {
      continue
    }
    // Step 1: reverse direction, allow_reflect=false to prevent re-entry.
    // Pick the rank pair from each side's FULL rank array using `mv_i`'s
    // category, NOT the outer reflect move's category. Step1's attacker
    // is the opponent (outer defender) so its offensive rank comes from
    // `def_ranks_full`; Step1's defender is the reflect user (outer
    // attacker) so its defensive rank comes from `atk_ranks_full`.
    let step1_atk_rank = match def_ranks_full {
      Some(arr) =>
        match mv_i.category {
          @model.Physical => arr[0]
          @model.Special => arr[2]
          @model.Status => 0
        }
      None => def_rank
    }
    let step1_def_rank = match atk_ranks_full {
      Some(arr) =>
        match mv_i.category {
          @model.Physical => arr[1]
          @model.Special => arr[3]
          @model.Status => 0
        }
      None => atk_rank
    }
    let step1_outcomes = compute_damage_variants(
      defender,
      attacker,
      mv_i,
      step1_atk_rank,
      step1_def_rank,
      atk_burn=false,
      allow_reflect=false,
      weather~,
      field~,
    )
    let step1_mean = avg_mean_damage(step1_outcomes)
    let p_slow_i = compute_p_slow(kind, mv_i, attacker, defender)
    let p_hit_i = if mv_i.accuracy <= 0 {
      1.0
    } else if mv_i.accuracy >= 100 {
      1.0
    } else {
      mv_i.accuracy.to_double() / 100.0
    }
    accumulator = accumulator + p_slow_i * p_hit_i * step1_mean.to_double()
    candidate_count = candidate_count + 1
  }
  if candidate_count == 0 {
    return [{ probability: 1.0, mean_damage: 0, hits_count: 1, hit_steps: [] }]
  }
  let (mult_num, mult_den) = @damage.reflect_multiplier(kind)
  let expected = accumulator *
    mult_num.to_double() /
    mult_den.to_double() /
    candidate_count.to_double()
  [
    {
      probability: 1.0,
      mean_damage: expected.to_int(),
      hits_count: 1,
      hit_steps: [],
    },
  ]
}

///|
/// Mean of `DamageOutcome.mean_damage` weighted by probability.
fn avg_mean_damage(outcomes : Array[@model.DamageOutcome]) -> Int {
  if outcomes.is_empty() {
    return 0
  }
  let mut weighted : Double = 0.0
  let mut total_p : Double = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    let o = outcomes[i]
    weighted = weighted + o.mean_damage.to_double() * o.probability
    total_p = total_p + o.probability
  }
  if total_p <= 0.0 {
    return 0
  }
  (weighted / total_p).to_int()
}

///|
/// Probability that the reflect user goes AFTER the opponent's chosen move
/// `mv` — required for the reflect to land at all. Counter / MirrorCoat have
/// priority -5 (always go last among equal-priority brackets but still lose
/// to opponent priority moves with priority >= -5). MetalBurst / Revenge
/// have priority 0 and must lose the speed roll to land.
///
/// MVP: speed rank defaults to 0 since `compute_damage_variants` does not
/// propagate speed rank. Item / ability modifiers (Scarf / Sand Rush etc.)
/// are also not factored in for now; same-speed defaults to 0.5 per the
/// in-game random tie-break.
fn compute_p_slow(
  kind : @damage.ReflectKind,
  mv : @model.Move,
  attacker : Combatant,
  defender : Combatant,
) -> Double {
  let reflect_priority = match kind {
    @damage.Counter => -5
    @damage.MirrorCoat => -5
    @damage.MetalBurst => 0
    @damage.Revenge => 0
  }
  if mv.priority > reflect_priority {
    // Opponent move has higher priority → always outspeeds the reflect.
    return 1.0
  }
  if mv.priority < reflect_priority {
    // Opponent priority < reflect priority → reflect actually goes first
    // (very rare; would require opponent using a -6 priority move and
    // reflect at -5). Reflect fails.
    return 0.0
  }
  // Equal priority → base speed comparison. Use base speed (or actual_stats
  // speed if provided) at rank 0 since compute_damage_variants does not
  // currently propagate per-side speed ranks.
  let atk_spe = match attacker.actual_stats {
    Some(stats) => stats[5]
    None => attacker.pokemon.spe
  }
  let def_spe = match defender.actual_stats {
    Some(stats) => stats[5]
    None => defender.pokemon.spe
  }
  if atk_spe < def_spe {
    1.0
  } else if atk_spe > def_spe {
    0.0
  } else {
    0.5
  }
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
  let target_is_me = !attacker_is_me
  let target_slot = defender_active
  let attacker_slot = attacker_active
  let leaves : Array[(Double, SwitchingGameState)] = []
  for i = 0; i < outcomes.length(); i = i + 1 {
    let outcome = outcomes[i]
    // ドレイン / 反動 が overkill 分を吸わないように、実 dealt = min(theoretical,
    // pre_dmg_defender_hp) でクランプ。本家挙動 (Showdown / Gen9) は「与えた
    // ダメージ」基準で吸収・反動を計算するため、防御側 HP が技の理論値を
    // 下回るときは その HP までしか吸えない。Drain / Liquid Ooze だけでなく
    // recoil 系も同じく overkill 分を 吸わないので、共通の `actual_dmg` を
    // 後段の with_post_hit_effects へ渡す。HP 自体の減算は `with_hp_damage`
    // が `clamp_zero` で 0 床にするので、theoretical を渡しても結果は同じ。
    let actual_dmg = if outcome.mean_damage > pre_dmg_defender_hp {
      pre_dmg_defender_hp
    } else {
      outcome.mean_damage
    }
    let state_dmg = with_hp_damage(
      state,
      target_is_me,
      target_slot,
      outcome.mean_damage,
    )
    // Phase 2-E (#91): per-variant post-hit state effects so recoil /
    // self_ko / recharge / stat_effects compound on the variant-specific
    // damage rather than a single mean. State remains immutable; with_-
    // post_hit_effects produces a fresh copy with updated arrays.
    let state_v = with_post_hit_effects(
      state_dmg, attacker_is_me, attacker_slot, target_slot, attacker_team, defender_team,
      attacker_move, actual_dmg,
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
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
  dmg : Int,
) -> SwitchingGameState {
  let my_hps = state.my_hps.copy()
  let opp_hps = state.opp_hps.copy()
  let my_ranks = state.my_ranks.copy()
  let opp_ranks = state.opp_ranks.copy()
  let my_must_recharge = state.my_must_recharge.copy()
  let opp_must_recharge = state.opp_must_recharge.copy()
  // Stage 7 (Rest): attacker_status は apply_healing で書き換わる可能性が
  // あるので copy on write。Rest が attacker_status[active] を Sleep(2) で
  // 上書きする本家挙動を反映する。non-Rest pathways では unchanged のまま
  // 最終 state にスレッドされる。
  let my_status = state.my_status.copy()
  let opp_status = state.opp_status.copy()
  // Stage 9 (LeechSeed): defender 側の leech_seeded 配列を書き換える可能性が
  // あるため copy on write。LeechSeed 以外の経路では unchanged のまま base
  // state を経由して最終 state にスレッドされる。植え付けは attacker 側で
  // なく defender 側のフラグを立てる (attacker_is_me=true → opp_leech_seeded、
  // attacker_is_me=false → my_leech_seeded)。
  let my_leech_seeded = state.my_leech_seeded.copy()
  let opp_leech_seeded = state.opp_leech_seeded.copy()
  let my_protean_locked = state.my_protean_locked.copy()
  let opp_protean_locked = state.opp_protean_locked.copy()
  // Stage 11 (Wish): attacker 側の wish_turns scalar を書き換える可能性があるため
  // ローカルに展開。Wish 以外の経路では unchanged のまま base state を経由して
  // 最終 state にスレッドされる。Wish の発動は attacker_is_me に応じて
  // my_wish_turns / opp_wish_turns のどちらかを書き換える (defender 側は
  // 触らない、これは LeechSeed と対照的)。pkdx single battle は active が常に
  // 1 つなので per-side scalar で十分で、これは長さ 1 の per-active-slot 配列と
  // 観測上等価。受け取りは EOT 発火時の current active がスレッドする (= Wisher
  // が Switch 後でも交代先が受ける、Bulbapedia Gen5+ 仕様)。
  let mut my_wish_turns = state.my_wish_turns
  let mut opp_wish_turns = state.opp_wish_turns
  let attacker_hps = if attacker_is_me { my_hps } else { opp_hps }
  let attacker_ranks = if attacker_is_me { my_ranks } else { opp_ranks }
  let defender_hps = if attacker_is_me { opp_hps } else { my_hps }
  let defender_ranks = if attacker_is_me { opp_ranks } else { my_ranks }
  let attacker_status = if attacker_is_me { my_status } else { opp_status }
  let attacker_must_recharge = if attacker_is_me {
    my_must_recharge
  } else {
    opp_must_recharge
  }
  let opp_alive = defender_hps[defender_active] > 0
  apply_stat_effects(attacker_ranks, defender_ranks, opp_alive, mv)
  apply_recoil(attacker_hps, attacker_active, mv, dmg)
  // 回復技 (HealingEffect) は self_ko の **手前** で適用する。本家挙動と
  // 整合: じばく + healing 等の組合せは現状ゲーム内で存在しないが、ある
  // 場合は self_ko 側 (= HP=0 への強制上書き) が後勝ち。recoil → heal →
  // self_ko の順は本段階以降の追加バリアントでも維持する。
  let attacker_max = effective_hp(attacker_team[attacker_active])
  // state.weather を渡して WeatherDependent (つきのひかり等) が動的に倍率を
  // 選択できるようにする。FixedFraction では参照されない。
  // Stage 7: attacker_status と attacker_ability を追加で渡す。Rest が
  // ability_blocks_status(SleepKind) を見て免疫 ability の場合は失敗し、
  // それ以外では attacker_status[active] を Sleep(2) に上書きする。
  // Stage 8: dmg と defender_ability を追加で渡す。Drain (ギガドレイン等) が
  // dmg * n / d を吸収し、defender_ability=ヘドロえき なら反転して attacker
  // が damage を受ける。defender_ability は damage 計算で参照される mega 後の
  // ability ではなく raw な defender_team[active].ability を読む。回復計算は
  // attacker mega 形態と独立 (Drain 倍率は move 側の n/d で決まる) なので
  // mega 解決経路を再通する必要はない。
  let attacker_ability = attacker_team[attacker_active].ability
  let defender_ability = defender_team[defender_active].ability
  // Stage H (terrain × sleep): Rest がエレキ / ミストフィールド下で grounded
  // 使用者に失敗する判定のため `state.field` と attacker の grounded 状態を
  // 渡す。grounded は mega 後の type/ability/item で解くため、status fanout
  // (`maybe_apply_status_fanout`) と同じく attacker 側 megaed を見て
  // `effective_combatant` 経由で評価する (Mega Gengar が grounded 化する等)。
  let attacker_megaed = if attacker_is_me {
    state.my_megaed
  } else {
    state.opp_megaed
  }
  let atk_is_mega = attacker_active < attacker_megaed.length() &&
    attacker_megaed[attacker_active]
  let atk_eff = effective_combatant(attacker_team[attacker_active], atk_is_mega)
  let attacker_grounded = @damage.is_grounded(
    type1=atk_eff.pokemon.type1,
    type2=atk_eff.pokemon.type2,
    ability=atk_eff.ability,
    item=atk_eff.item,
  )
  apply_healing(
    mv,
    attacker_active,
    attacker_hps,
    attacker_max,
    state.weather,
    attacker_status,
    attacker_ability,
    dmg,
    defender_ability,
    field=state.field,
    attacker_grounded~,
  )
  // Stage 9 (LeechSeed planting): `apply_healing` は attacker 側のバッファ
  // (HP / status) しか書き換えられない設計だが、LeechSeed は defender 側の
  // フラグを立てる必要があるため専用パスとして外出ししている。判定:
  //   - mv.healing == Some(LeechSeed) のときのみ発火
  //   - defender が くさタイプ (mega 後 effective type) なら失敗
  //   - すでに seeded な相手にもう一度撃っても観測上 no-op (true 上書きは無害)
  //   - Magic Guard は植え付け自体は許容する (EOT tick 側で 0 化される)
  // attacker_is_me=true (= 自分が技を撃った) なら opp 側 = opp_leech_seeded、
  // false なら my 側 = my_leech_seeded を書き換える。defender の mega 状態は
  // 撃った側から見た相手側 megaed 配列を参照する。
  match mv.healing {
    Some(@model.LeechSeed) => {
      let def_megaed = if attacker_is_me {
        state.opp_megaed[defender_active]
      } else {
        state.my_megaed[defender_active]
      }
      let defender_eff = effective_combatant(
        defender_team[defender_active],
        def_megaed,
      )
      let is_grass = defender_eff.pokemon.type1 == "くさ" ||
        defender_eff.pokemon.type2 == "くさ"
      if !is_grass {
        // Defensive: legacy test fixtures may size leech_seeded shorter than
        // the team. Out-of-bounds slots are treated as no-op (the cache key
        // / state ignores them entirely).
        if attacker_is_me {
          if defender_active < opp_leech_seeded.length() {
            opp_leech_seeded[defender_active] = true
          }
        } else if defender_active < my_leech_seeded.length() {
          my_leech_seeded[defender_active] = true
        }
      }
    }
    // Stage 10 (PainSplit / いたみわけ): `apply_healing` は attacker 側 HP
    // バッファしか書けない設計のため LeechSeed と同じく外出しで処理する。
    // 双方の現 HP を合算し floor 除算で avg を作り、各側 max_hp で independent
    // にクランプする (asymmetric max への対応)。my_hps / opp_hps は本関数
    // 冒頭で copy-on-write 済みなので、ここで直接書き換えれば最終 state に
    // 反映される。defender_max は defender_team[defender_active] から
    // effective_hp で取得し、attacker_max は外で計算済みの値を流用する。
    //
    // fainted defender (HP=0) への PainSplit は mainline では失敗扱いだが、
    // 本 PR では alive_actions が ひんし を action 候補から外すため通常の
    // ゲーム木では到達しない。テスト都合で直接呼んだときの挙動を pin する
    // (= 失敗扱いではなく avg=attacker_cur/2 で素直に動く)。重複ガードは
    // 入れない (= alive_actions 側で担保)。
    Some(@model.PainSplit) => {
      let defender_max = effective_hp(defender_team[defender_active])
      let attacker_cur = attacker_hps[attacker_active]
      let defender_cur = defender_hps[defender_active]
      let avg = (attacker_cur + defender_cur) / 2
      let new_attacker = if avg > attacker_max { attacker_max } else { avg }
      let new_defender = if avg > defender_max { defender_max } else { avg }
      attacker_hps[attacker_active] = new_attacker
      defender_hps[defender_active] = new_defender
    }
    // Stage 11 (Wish / ねがいごと): attacker 側の wish_turns を 2 にセット。
    // 既に pending な wish_turns があっても上書きする (Gen5+ 仕様: 重ね掛け
    // 不可、後着優先)。`apply_healing` のシグネチャは wish_turns を取らない
    // ため、LeechSeed / PainSplit と同じく専用パスで処理する。発動は EOT 側
    // (`apply_eot` の wish-trigger ブロック) で行う。set 値 2 は「EOT を 2 回
    // 経て発火」の tick 残数。詳しいタイミング契約は struct definition の
    // wish_turns docstring を参照。
    //
    // attacker_is_me=true なら my_wish_turns、false なら opp_wish_turns を
    // 書き換える。pkdx single battle は active が常に 1 つなので per-side
    // scalar で十分 (長さ 1 の per-active-slot 配列と観測上等価)。
    Some(@model.Wish) =>
      if attacker_is_me {
        my_wish_turns = 2
      } else {
        opp_wish_turns = 2
      }
    _ => ()
  }
  // Stage 2 (Protean / Libero): へんげんじざい / リベロ は技を撃った瞬間に
  // 使用者をその技のタイプ 1 つに変える。記録は attacker 側 (LeechSeed が
  // defender 側だったのと対照的) の `*_protean_locked[active]` に `mv.type_`
  // を書き込む。発動条件:
  //   - ability が へんげんじざい / リベロ
  //   - tera_type == "" (テラスタル中は型固定で Protean 非発動)
  //   - 当該 slot が未ロック ("") — once per switch-in。既にロック済みなら
  //     何度撃っても最初のタイプのまま (再変化しない)
  //   - カテゴリゲートなし: Status 技でも発動する
  // ダメージ計算は本フックより前に走るため、発動技自身のダメージは pre-lock
  // 状態で計算済み。ここで記録するロックは「次手以降」の damage / type-chart に
  // 効く。記録値は `mv.type_` で variant 非依存なので、`apply_damage_variants-
  // _fanout` から variant ごとに呼ばれても全 leaf が同一値に収束する。
  //
  // Stage 5: 発動判定は base ability ではなく **mega 後の実効特性** (`atk_eff`)
  // を見る。base げきりゅう → mega へんげんじざい のように mega で初めて Protean
  // を得る個体でも正しく発動を記録するため。`atk_eff` は上で grounded 判定用に
  // `effective_combatant(_, atk_is_mega)` で解決済み (mega 解決のみ・protean
  // override なしなので ability は base/mega いずれも正しく出る)。tera 判定も
  // `atk_eff.tera_type` で統一する (effective_combatant は tera_type を変えない
  // ので atk.tera_type と等価だが、実効 combatant 経由で一貫させる)。
  let attacker_protean = if attacker_is_me {
    my_protean_locked
  } else {
    opp_protean_locked
  }
  if attacker_active < attacker_team.length() {
    if (
        atk_eff.ability == "へんげんじざい" ||
        atk_eff.ability == "リベロ"
      ) &&
      atk_eff.tera_type == "" &&
      attacker_active < attacker_protean.length() &&
      attacker_protean[attacker_active] == "" {
      attacker_protean[attacker_active] = mv.type_
    }
  }
  if mv.self_ko {
    attacker_hps[attacker_active] = 0
  }
  if mv.recharge && attacker_hps[attacker_active] > 0 {
    attacker_must_recharge[attacker_active] = true
  }
  // Stage 5 (healing-moves plan): 天候設定技 (にほんばれ / あまごい /
  // すなあらし / ゆきげしき) の効果を state に反映する。`mv.weather_set` が
  // `Some(w)` なら weather と weather_turns_left を上書き、`None` なら維持。
  // Gen9 base の 5 ターン (天候石なし) を本段階では固定値とし、天候石による
  // 8 ターン延長は後続 PR で `Pokemon.item` から派生させる。HP に対する damage
  // はそもそも status カテゴリの技なので変化しない (apply_healing 直後でも HP
  // は不変)。天候設定の上書きは self_ko / recharge と独立 (じばく + 天候設定の
  // 同居技は本家に存在しないが、ある場合は self_ko 後に weather を書き換える
  // 順序で問題なし — 天候はサイド非依存のグローバル state)。
  let (new_weather, new_weather_turns) = match mv.weather_set {
    Some(w) => (w, 5)
    None => (state.weather, state.weather_turns_left)
  }
  // Stage E (field-setting moves): エレキ / グラス / ミスト / サイコフィールド
  // の効果を state に反映する。`mv.field_set` が `Some(f)` なら field と
  // field_turns_left を上書き、`None` なら維持。Gen9 base の 5 ターン (Terrain
  // Extender なし) を本段階では固定値とし、Terrain Extender (8 ターン延長) は
  // 後続 PR で `Pokemon.item` から派生させる。weather_set と完全に対称な
  // 構造で、weather と同様に side 非依存のグローバル state。同じ field を
  // 撃ち直すと field_turns_left は 5 にリセット (later-wins、weather と同じ
  // semantics)。
  let (new_field, new_field_turns) = match mv.field_set {
    Some(f) => (f, 5)
    None => (state.field, state.field_turns_left)
  }
  {
    ..state,
    my_hps,
    opp_hps,
    my_ranks,
    opp_ranks,
    my_must_recharge,
    opp_must_recharge,
    my_status,
    opp_status,
    weather: new_weather,
    weather_turns_left: new_weather_turns,
    my_leech_seeded,
    opp_leech_seeded,
    my_protean_locked,
    opp_protean_locked,
    my_wish_turns,
    opp_wish_turns,
    field: new_field,
    field_turns_left: new_field_turns,
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
