///|
/// Monte Carlo battle simulator used by the `MonteCarloSim` payoff model.
///
/// Simulates single-Pokemon duels with a seeded ChaCha8 RNG. Each trial
/// picks the highest-expected-damage move for both sides, samples the
/// 16-roll damage table, and applies damage in speed order until one side
/// is KO'd (or the safety turn limit is reached).

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
/// damage against `dfn`. Returns `None` if `atk` has no damaging moves.
pub fn pick_best_move(atk : Combatant, dfn : Combatant) -> Int? {
  let mut best_idx = -1
  let mut best_avg = 0.0
  for i in 0..<atk.moves.length() {
    let mv = atk.moves[i]
    if mv.power <= 0 {
      continue
    }
    let r = @damage.calc_damage(build_input(atk, dfn, mv))
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
/// Apply one attack from `attacker` to `defender` and return the new
/// defender HP. If the attacker has no damaging moves, HP is unchanged.
fn perform_attack(
  attacker : Combatant,
  defender : Combatant,
  defender_hp : Int,
  rng : @random.Rand,
) -> Int {
  match pick_best_move(attacker, defender) {
    Some(idx) => {
      let r = @damage.calc_damage(
        build_input(attacker, defender, attacker.moves[idx]),
      )
      let dmg = r.damages[rng.int(limit=16)]
      defender_hp - dmg
    }
    None => defender_hp
  }
}

///|
/// Compute Monte Carlo winrate for `a` vs `b` over `trials` seeded
/// simulations. Returns a value in `[0, 1]` matching the existing `winrate`
/// contract (1.0 → `a` always wins, 0.0 → `b` always wins, 0.5 → draw).
/// Returns `0.5` immediately when `trials <= 0`.
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
/// `turn_limit` is injected so tests can keep runtime bounded.
pub fn simulate_battle(
  a : Combatant,
  b : Combatant,
  rng : @random.Rand,
  turn_limit~ : Int = 200,
) -> Double {
  let mut a_hp = a.pokemon.hp
  let mut b_hp = b.pokemon.hp
  let s = speed_sign(a, b)
  let a_first = if s > 0 {
    true
  } else if s < 0 {
    false
  } else {
    rng.boolean()
  }
  for _ in 0..<turn_limit {
    if a_first {
      b_hp = perform_attack(a, b, b_hp, rng)
      if b_hp <= 0 {
        return 1.0
      }
      a_hp = perform_attack(b, a, a_hp, rng)
      if a_hp <= 0 {
        return 0.0
      }
    } else {
      a_hp = perform_attack(b, a, a_hp, rng)
      if a_hp <= 0 {
        return 0.0
      }
      b_hp = perform_attack(a, b, b_hp, rng)
      if b_hp <= 0 {
        return 1.0
      }
    }
  }
  0.5
}
