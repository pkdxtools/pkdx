// Seeded ChaCha8 RNG + ε-greedy move selection helpers

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

