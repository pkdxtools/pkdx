///|
/// A move (technique) usable by a Pokemon. Move metadata used by the payoff
/// layer (SwitchingGame / team_monte_carlo) travels inline on this struct:
///
/// - `priority ∈ [-7, +5]` — in-game action-order bucket. `0` for regular
///   moves, positive for priority moves (しんそく=+2, バレットパンチ=+1,
///   ねこだまし=+3, まもる=+4).
/// - `stat_effects` — list of `(stat_index, delta)` pairs applied to the
///   user on use. Stat indices: `0=A, 1=B, 2=C, 3=D, 4=S`. つるぎのまい is
///   `[(0, 2)]`, りゅうのまい is `[(0, 1), (4, 1)]`, からをやぶる is
///   `[(0, 2), (2, 2), (4, 2), (1, -1), (3, -1)]`. Empty for damaging-only
///   and unrecognised moves.
/// - `status_effect` — optional `(StatusKind, chance%)` pair for dedicated
///   status moves (鬼火 = `Some((BurnKind, 85))`, どくどく, ねむりごな等).
///   Secondary chances on damaging moves (ほのおのパンチ 10%やけど 等) are
///   not modelled in MVP — only dedicated status moves carry this field.
///
/// All three payoff fields default to `0` / `[]` / `None` so code that
/// constructs `Move` values without the metadata (legacy paths, tests) stays
/// valid; the payoff layer interprets the defaults as "no priority / no
/// boost / no status effect".
pub(all) struct Move {
  name : String
  type_ : String
  category : MoveCategory
  power : Int
  accuracy : Int
  pp : Int
  learn_method : String
  priority : Int
  stat_effects : Array[(Int, Int)]
  status_effect : (StatusKind, Int)?
} derive(Show, Eq)
