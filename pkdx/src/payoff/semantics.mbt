///|
/// Payoff semantics for converting Pokemon matchups into zero-sum payoff
/// matrices.
///
/// - `Best1v1`: each combatant selects its best move (maximum expected damage),
///   and winrate is decided by KO turn count with speed as tiebreaker. Fast
///   and model-free; ignores switching, multi-turn effects, and mixed move
///   choice.
/// - `NashResponses`: for each (i, j) cell, build the inner move-vs-move game
///   and return its Nash value as the payoff. Captures the commitment problem
///   where attacker and defender simultaneously choose moves.

///|
pub(all) enum PayoffModel {
  Best1v1
  NashResponses
  MonteCarloSim(Int, UInt64)
} derive(Show, Eq)

///|
/// Team-level payoff model. `Pairwise` wraps any pairwise `PayoffModel`
/// (Phase 0-12 behaviour); `SwitchingGame(turn_limit)` evaluates each
/// (selection, selection) cell as an extensive-form game with switching.
pub(all) enum TeamPayoffModel {
  Pairwise(PayoffModel)
  SwitchingGame(Int)
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
} derive(Show)

///|
pub suberror PayoffError {
  EmptyCombatants
  EmptyMoves(String)
} derive(Show)
