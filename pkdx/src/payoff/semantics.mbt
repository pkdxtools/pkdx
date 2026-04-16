///|
/// Team-level payoff model for converting Pokemon team matchups into zero-sum
/// selection matrices.
///
/// - `SwitchingGame(turn_limit)` evaluates each (selection, selection) cell as
///   an extensive-form game with switching (precise, deterministic).
/// - `ScreenedSwitchingGame(mc_trials, mc_seed, keep_top_quantile,
///   refine_turn_limit)` runs a team-level Monte Carlo screening pass over the
///   full selection matrix, prunes rows/columns below `keep_top_quantile`
///   (by mean screening value), then evaluates only the retained sub-matrix
///   with `SwitchingGame(refine_turn_limit)`. `keep_top_quantile >= 1.0`
///   short-circuits to the plain `SwitchingGame(refine_turn_limit)` path.
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
