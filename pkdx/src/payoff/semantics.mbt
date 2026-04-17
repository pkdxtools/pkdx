///|
/// SwitchingGame DP の turn_limit。3 体選出なので最低 3 ターンは必要。
/// 5 は「素の `switching_game` で実用的に完走しつつ、3 体落としきる
/// 短期決着パスを十分カバーする」既定値。多技構成では tl=4 以上で
/// 急激に重くなるため、長期戦評価は `switching_game:<N>` で個別指定
/// する運用とする。
pub const DP_TURN_LIMIT : Int = 5

///|
/// MC screening rollout の turn_limit。screening は足切り用なので
/// 決着を待たず、5 ターン程度で HP ratio 差に収束させる。
pub const MC_TURN_LIMIT : Int = 5

///|
/// Team-level payoff model for converting Pokemon team matchups into zero-sum
/// selection matrices.
///
/// - `SwitchingGame(turn_limit)` evaluates each (selection, selection) cell as
///   an extensive-form game with switching (precise, deterministic). CLI 既定は
///   `DP_TURN_LIMIT` (5)。`switching_game:<N>` で個別に上書き可能。
/// - `ScreenedSwitchingGame(mc_trials, mc_seed, keep_top_quantile)` runs a
///   team-level Monte Carlo screening pass (rollout turn limit
///   `MC_TURN_LIMIT` = 5) over the full selection matrix, prunes rows/columns
///   below `keep_top_quantile` (by mean screening value), then evaluates only
///   the retained sub-matrix with SwitchingGame DP (`DP_TURN_LIMIT`).
///   `keep_top_quantile >= 1.0` short-circuits to the plain SwitchingGame path.
pub(all) enum TeamPayoffModel {
  SwitchingGame(Int)
  ScreenedSwitchingGame(Int, UInt64, Double, Int)
} derive(Show, Eq)

///|
/// A single-Pokemon combatant with moves and equipment. The underlying
/// `Pokemon` carries base stats; `stat_system` controls Lv50 stat realisation
/// (Standard EV252/IV31 or Champions SP).
pub(all) struct Combatant {
  pokemon : @model.Pokemon
  moves : Array[@model.Move]
  ability : String
  item : String
  tera_type : String
  stat_system : @model.StatSystem
  // メガ進化後のステータス差分。`None` なら mega 不可。`Some(_)` なら
  // `SwitchingGame` の `Mega` アクションで mega_form 値に切り替わる。
  mega_form : @model.MegaForm?
} derive(Show)

///|
pub suberror PayoffError {
  EmptyCombatants
  EmptyMoves(String)
  UnsupportedFormat(String)
} derive(Show)
