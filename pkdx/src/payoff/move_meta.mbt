///|
/// Static move metadata for the payoff module.
///
/// `pokedex.db` does not currently carry move priority or stat-boost effect
/// data, so the payoff layer keeps a small curated table of the moves that
/// matter most for extensive-form evaluation (SwitchingGame) and ε-greedy
/// rollouts (MonteCarloSim). The table is intentionally narrow — only the
/// commonly-played priority and self-boost moves are listed; unknown names
/// fall through to `priority = 0` / `stat_boost_effect = None`, which
/// matches the default no-priority / no-boost behaviour.
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
/// Priority of a move (Japanese name). Returns 0 for unknown / normal-
/// priority moves. Values mirror the in-game +N bucket (e.g. しんそく = +2,
/// バレットパンチ = +1, ねこだまし = +3, まもる = +4).
pub fn move_priority(name : String) -> Int {
  match name {
    "しんそく" | "ファーストブラッド" => 2
    "バレットパンチ"
    | "こおりのつぶて"
    | "アクアジェット"
    | "かげうち"
    | "マッハパンチ"
    | "みずしゅりけん"
    | "でんこうせっか"
    | "しんくうは"
    | "ふいうち" => 1
    "ねこだまし" | "ファストガード" => 3
    "まもる" | "みきり" => 4
    _ => 0
  }
}

///|
/// Self stat-boost effect of a move (Japanese name). `Some(deltas)` returns a
/// list of `(stat_index, delta)` pairs applied to the user on use; deltas are
/// clamped to `[-2, +2]` by the consumer. `None` means the move has no
/// self-boost effect tracked by the payoff layer (damaging moves included).
///
/// Only covers the common setup moves that dominate SwitchingGame dynamics:
/// つるぎのまい (A+2), りゅうのまい (A+1/S+1), めいそう (C+1/D+1), わるだくみ
/// (C+2), てっぺき (B+2), ちょうのまい (C+1/D+1/S+1), からをやぶる (A+2/C+2/
/// S+2/B-1/D-1). Extending the table is safe — the only contract is that the
/// first tuple element is in `[0, 5)`.
pub fn stat_boost_effect(name : String) -> Array[(Int, Int)]? {
  match name {
    "つるぎのまい" => Some([(0, 2)])
    "りゅうのまい" => Some([(0, 1), (4, 1)])
    "めいそう" => Some([(2, 1), (3, 1)])
    "わるだくみ" => Some([(2, 2)])
    "てっぺき" | "バリアー" => Some([(1, 2)])
    "ちょうのまい" => Some([(2, 1), (3, 1), (4, 1)])
    "からをやぶる" =>
      Some([(0, 2), (2, 2), (4, 2), (1, -1), (3, -1)])
    "ロックカット" | "こうそくいどう" | "アジリティ" => Some([(4, 2)])
    "ビルドアップ" => Some([(0, 1), (1, 1)])
    "いかりのこな" => None
    _ => None
  }
}

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
