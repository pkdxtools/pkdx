///|
/// Monte Carlo battle simulator used by the `MonteCarloSim` payoff model.
///
/// Simulates single-Pokemon duels with a seeded ChaCha8 RNG. Rollouts use
/// ε-greedy move selection (`default_rollout_epsilon = 0.1`), so status /
/// variation moves are sampled with non-zero probability and their presence
/// is no longer structurally invisible to the winrate estimate. Each side
/// tracks stat ranks across the rollout, so self-boost moves (つるぎのまい,
/// りゅうのまい, etc.) actually affect subsequent damage — the "boost then
/// sweep" plan is measurable in the winrate instead of being silently
/// discarded as a wasted turn. Damage is applied in priority → effective-
/// speed order until one side is KO'd (or the safety turn limit is reached).
///
/// Priority and stat-boost metadata are read directly from each
/// `@model.Move` (populated upstream by `query_moves` via the `move_meta`
/// DB JOIN), so no per-run cache or lookup layer is required here.

///|
/// Default ε for ε-greedy rollout move selection. Rationale: 10% keeps the
/// expected-damage greedy signal dominant while giving status / non-damaging
/// moves non-zero sampling weight, so MC winrates reflect their presence
/// rather than collapsing to best-damaging-only behaviour. Overridable per
/// call for sensitivity analysis.
pub let default_rollout_epsilon : Double = 0.1

///|
/// Convert a `UInt64` seed into a 32-byte seed for `Rand::chacha8`. The
/// value is packed into the first 8 bytes (little-endian) with the remaining
/// 24 bytes zero-padded. `Rand::chacha8` aborts unless the seed is exactly
/// 32 bytes (MoonBit core specification).
pub fn seed_to_bytes(seed : UInt64) -> Bytes {
  Bytes::makei(32, fn(i) {
    if i < 8 {
      ((seed >> (i * 8)) & 0xFFUL).to_byte()
    } else {
      b'\x00'
    }
  })
}

///|
/// Create a seeded ChaCha8 RNG from a `UInt64` seed.
pub fn seeded_rng(seed : UInt64) -> @random.Rand {
  @random.Rand::chacha8(seed=seed_to_bytes(seed))
}

///|
/// Pick the index of the damage move (`power > 0`) with the highest average
/// damage against `dfn`, scoring with the given attacker/defender rank
/// vectors. Returns `None` if `atk` has no damaging moves.
///
/// This is the greedy baseline used by `rollout_pick_move` — callers should
/// prefer `rollout_pick_move` to get ε-greedy semantics. Ranks default to
/// zero when the optional args are omitted to keep the old single-shot
/// signature usable from tests / diagnostics.
pub fn pick_best_move(
  atk : Combatant,
  dfn : Combatant,
  atk_ranks~ : Array[Int] = [0, 0, 0, 0, 0],
  def_ranks~ : Array[Int] = [0, 0, 0, 0, 0],
) -> Int? {
  let mut best_idx = -1
  let mut best_avg = 0.0
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
    let r = @damage.calc_damage(
      build_input_with_ranks(atk, dfn, mv, ar, dr),
    )
    let avg = avg_damage(r)
    if avg > best_avg {
      best_avg = avg
      best_idx = i
    }
  }
  if best_idx >= 0 {
    Some(best_idx)
  } else {
    None
  }
}

///|
/// ε-greedy move selection for a rollout turn. With probability `epsilon`
/// returns a uniform random move from the attacker's full moveset (including
/// status / non-damaging moves); otherwise returns the greedy
/// max-expected-damage move under the given ranks. Returns `None` only when
/// `atk` has no moves at all — status-only movesets still return a random
/// move, not `None`.
pub fn rollout_pick_move(
  atk : Combatant,
  dfn : Combatant,
  rng : @random.Rand,
  epsilon : Double,
  atk_ranks~ : Array[Int] = [0, 0, 0, 0, 0],
  def_ranks~ : Array[Int] = [0, 0, 0, 0, 0],
) -> Int? {
  let n = atk.moves.length()
  if n == 0 {
    return None
  }
  // Uniform-over-[0,1) draw built from a single int sample — `@random.Rand`
  // does not expose `double()`, and this keeps determinism tight.
  let draw = rng.int(limit=1000000).to_double() / 1000000.0
  if draw < epsilon {
    return Some(rng.int(limit=n))
  }
  match pick_best_move(atk, dfn, atk_ranks~, def_ranks~) {
    Some(idx) => Some(idx)
    None =>
      // Fallback: no damaging moves, but status moves exist — pick a random
      // status move so non-damaging rollouts still advance.
      Some(rng.int(limit=n))
  }
}

///|
/// Compute Monte Carlo winrate for `a` vs `b` over `trials` seeded
/// simulations. Returns a value in `[0, 1]` matching the existing `winrate`
/// contract (1.0 → `a` always wins, 0.0 → `b` always wins, 0.5 → draw).
/// Returns `0.5` immediately when `trials <= 0`. Move priority and
/// stat-boost effects are read from each `Move.priority` /
/// `Move.stat_effects`; populate those before constructing the combatants.
pub fn monte_carlo_winrate(
  a : Combatant,
  b : Combatant,
  trials : Int,
  seed : UInt64,
) -> Double {
  if trials <= 0 {
    return 0.5
  }
  let rng = seeded_rng(seed)
  let mut total = 0.0
  for _ in 0..<trials {
    total += simulate_battle(a, b, rng)
  }
  total / trials.to_double()
}

///|
/// Simulate one 1v1 battle. Returns:
/// - `1.0` if `a` wins,
/// - `0.0` if `b` wins,
/// - `0.5` if the safety `turn_limit` is reached (draw).
///
/// `turn_limit` / `epsilon` are injected so tests can keep runtime bounded
/// and exercise both pure-greedy and ε-greedy code paths. Action order uses
/// priority → effective speed (priority moves like バレットパンチ out-turn
/// faster opponents; Speed-stage boosts shift the cutoff). Speed ties are
/// broken by RNG. Rank state tracked locally: each status move drawn from
/// the moveset applies its `stat_effects` to the user before damage on the
/// next turn.
pub fn simulate_battle(
  a : Combatant,
  b : Combatant,
  rng : @random.Rand,
  turn_limit~ : Int = 200,
  epsilon~ : Double = default_rollout_epsilon,
) -> Double {
  let mut a_hp = a.pokemon.hp
  let mut b_hp = b.pokemon.hp
  let a_ranks = [0, 0, 0, 0, 0]
  let b_ranks = [0, 0, 0, 0, 0]
  for _ in 0..<turn_limit {
    // Resolve each side's chosen move up-front (rank-aware).
    let idx_a = match rollout_pick_move(
      a, b, rng, epsilon, atk_ranks=a_ranks, def_ranks=b_ranks,
    ) {
      Some(i) => i
      None => -1
    }
    let idx_b = match rollout_pick_move(
      b, a, rng, epsilon, atk_ranks=b_ranks, def_ranks=a_ranks,
    ) {
      Some(i) => i
      None => -1
    }
    let prio_a = if idx_a >= 0 { a.moves[idx_a].priority } else { 0 }
    let prio_b = if idx_b >= 0 { b.moves[idx_b].priority } else { 0 }
    let eff_spe_a = effective_speed(a.pokemon.spe, a_ranks[4])
    let eff_spe_b = effective_speed(b.pokemon.spe, b_ranks[4])
    let s = turn_order_sign(a, prio_a, eff_spe_a, b, prio_b, eff_spe_b)
    let a_first = if s > 0 {
      true
    } else if s < 0 {
      false
    } else {
      rng.boolean()
    }
    if a_first {
      b_hp = perform_attack_with(a, b, b_hp, idx_a, rng, a_ranks, b_ranks)
      if b_hp <= 0 {
        return 1.0
      }
      a_hp = perform_attack_with(b, a, a_hp, idx_b, rng, b_ranks, a_ranks)
      if a_hp <= 0 {
        return 0.0
      }
    } else {
      a_hp = perform_attack_with(b, a, a_hp, idx_b, rng, b_ranks, a_ranks)
      if a_hp <= 0 {
        return 0.0
      }
      b_hp = perform_attack_with(a, b, b_hp, idx_a, rng, a_ranks, b_ranks)
      if b_hp <= 0 {
        return 1.0
      }
    }
  }
  0.5
}

///|
/// Apply one pre-selected attack (move index `idx`, already ε-greedy-chosen).
/// `idx < 0` means the attacker has no legal move this turn — HP is
/// unchanged. For damaging moves, ranks scale the damage calc (attacker
/// offensive stage, defender defensive stage). For status moves with
/// `stat_effects`, the user's own ranks are mutated in-place (clamped to
/// `[-2, +2]`) so the boost persists across turns.
fn perform_attack_with(
  attacker : Combatant,
  defender : Combatant,
  defender_hp : Int,
  idx : Int,
  rng : @random.Rand,
  atk_ranks : Array[Int],
  def_ranks : Array[Int],
) -> Int {
  if idx < 0 {
    return defender_hp
  }
  let mv = attacker.moves[idx]
  // Status / non-damaging move: apply stat_effects to the attacker's own
  // ranks, leave HP unchanged.
  if mv.power <= 0 {
    for eff in mv.stat_effects {
      let (i, delta) = eff
      if i >= 0 && i < atk_ranks.length() {
        atk_ranks[i] = clamp_rank(atk_ranks[i] + delta)
      }
    }
    return defender_hp
  }
  // Damaging move: compute damage with current ranks.
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
  defender_hp - r.damages[rng.int(limit=16)]
}
