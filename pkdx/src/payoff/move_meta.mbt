// move.priority / move.stat_effects を使った先制判定・ランク補正ヘルパー
///
/// Stat indices used throughout the module (matches the order inside
/// `my_ranks` / `opp_ranks` in `SwitchingGameState`):
///
/// - 0: Attack (A)
/// - 1: Defense (B)
/// - 2: Special Attack (C)
/// - 3: Special Defense (D)
/// - 4: Speed (S)

///|
/// Clamp a stat rank delta-sum into the payoff layer's reduced range
/// `[-2, +2]`. Abstracting the clamp here keeps `transition` readable and
/// ensures the same rounding rule is applied in every call site.
pub fn clamp_rank(r : Int) -> Int {
  if r > 2 {
    2
  } else if r < -2 {
    -2
  } else {
    r
  }
}

///|
/// Compare two combatants' turn order accounting for move priority. Returns
/// `+1` if `a` acts before `b`, `-1` if after, `0` on a full tie. Priority
/// dominates; speed is the tie-breaker (matches in-game rules).
pub fn turn_order_sign(
  a : Combatant,
  prio_a : Int,
  a_spe : Int,
  b : Combatant,
  prio_b : Int,
  b_spe : Int,
) -> Int {
  // `a` and `b` are kept in the signature for future extensions (ability-
  // based priority, e.g. プレッシャー / いたずらごころ). Currently unused
  // beyond the speed values the caller already resolved.
  let _ = a
  let _ = b
  if prio_a > prio_b {
    1
  } else if prio_a < prio_b {
    -1
  } else if a_spe > b_spe {
    1
  } else if a_spe < b_spe {
    -1
  } else {
    0
  }
}

///|
/// Effective speed of a combatant given a Speed rank `s_rank ∈ [-6, +6]`
/// (caller should already clamp to `[-2, +2]` for payoff-layer states).
/// Matches the in-game stage multiplier for non-HP stats: positive stages
/// scale by `(2 + s)/2`, negative by `2/(2 + |s|)`.
pub fn effective_speed(base_spe : Int, s_rank : Int) -> Int {
  if s_rank >= 0 {
    base_spe * (2 + s_rank) / 2
  } else {
    base_spe * 2 / (2 + -s_rank)
  }
}
