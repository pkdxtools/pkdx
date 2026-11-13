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
/// Clamp a stat stage to the real game range `[-6, +6]`. Used only for the
/// rank arrays of まけんき / かちき holders (see `clamp_rank_for`).
pub fn clamp_stat_stage(r : Int) -> Int {
  if r > 6 {
    6
  } else if r < -6 {
    -6
  } else {
    r
  }
}

///|
/// Clamp a rank write by the holder's ability. Holders of まけんき / かちき
/// are tracked over the real `[-6, +6]` range, because their reaction fires
/// only when a drop actually lands: a drop must stop at the real floor for
/// the "did not land at -6" case to be exact. そうしょく holders use the same
/// range, so the absorb boost stops at +6 as in Showdown. Every other holder
/// keeps the reduced `[-2, +2]` range (`clamp_rank`), so existing results are
/// unchanged.
pub fn clamp_rank_for(owner_ability : String, raw : Int) -> Int {
  if ability_tracks_full_stages(owner_ability) {
    clamp_stat_stage(raw)
  } else {
    clamp_rank(raw)
  }
}

///|
/// Compare two combatants' turn order accounting for move priority. Returns
/// `+1` if `a` acts before `b`, `-1` if after, `0` on a full tie. Priority
/// dominates; speed is the tie-breaker (matches in-game rules).
///
/// `prio_a` / `prio_b` are effective priorities. Callers apply
/// `effective_priority` (いたずらごころ / はやてのつばさ) before this
/// comparison. The combatant arguments stay for a later modifier that needs
/// more than the integer; this function only compares the numbers it is given.
pub fn turn_order_sign(
  a : Combatant,
  prio_a : Int,
  a_spe : Int,
  b : Combatant,
  prio_b : Int,
  b_spe : Int,
) -> Int {
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
