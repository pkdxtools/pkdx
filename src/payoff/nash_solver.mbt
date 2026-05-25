///|
/// Pkdx-side wrapper around `@nash.solve_zero_sum` with approximate-Nash
/// fallbacks.
///
/// CLI-bound only: recursive DP callsites in `switching_game_turn.mbt`
/// intentionally stay on `@nash.solve_zero_sum` directly — their per-node
/// value-cache semantics differ and the silent-degrade behavior is tracked
/// separately via `silent_dp_fallback_count` (Stage 3).
///
/// Stage 1a: primary simplex passthrough only. The fictitious_play / mwu
/// fallback chain and the `NashFallbackExhausted` suberror are added in Stage
/// 1b and 1c.

///|
pub(all) enum NashSolverPath {
  Simplex
  FictitiousPlay
  Mwu
} derive(Eq)

///|
/// Manual Show impl so callers can `inspect` / interpolate solver paths
/// without dragging Debug requirements through transitive fields.
pub impl Show for NashSolverPath with output(self, logger) {
  match self {
    Simplex => logger.write_string("Simplex")
    FictitiousPlay => logger.write_string("FictitiousPlay")
    Mwu => logger.write_string("Mwu")
  }
}

///|
/// Tuning knobs for the fallback chain. `tol` is the exploitability tolerance
/// (winrate units) used to accept an approximate solution; `iterations` is the
/// per-solver iteration budget. Defaults are chosen for `pkdx select`-grade
/// matrices (few-dozen rows/cols, winrate-scaled payoffs).
pub(all) struct NashSolverConfig {
  tol : Double
  iterations : Int
}

///|
pub fn NashSolverConfig::default() -> NashSolverConfig {
  { tol: 0.05, iterations: 10000 }
}

///|
/// Result of a fallback solve. `solver_path` records which solver actually
/// produced the strategies, and `exploitability` is the `@nash.exploitability`
/// of `(row_strategy, col_strategy)` on `matrix`. For the primary simplex
/// path this is exactly zero by construction.
pub(all) struct NashSolverResult {
  value : Double
  row_strategy : @nash.MixedStrategy
  col_strategy : @nash.MixedStrategy
  exploitability : Double
  solver_path : NashSolverPath
}

///|
/// JSON-stable lowercase tag for a solver path. Used by CLI emitters to
/// surface which fallback path was taken.
pub fn solver_path_string(p : NashSolverPath) -> String {
  match p {
    Simplex => "simplex"
    FictitiousPlay => "fictitious_play"
    Mwu => "mwu"
  }
}

///|
/// Solve a zero-sum game with the pkdx fallback chain.
///
/// Stage 1a: primary simplex only. On `SolverError` the wrapper raises
/// `InnerError(...)` — fictitious_play / mwu fallbacks land in Stage 1b/1c.
pub fn solve_with_fallback(
  matrix : @nash.FiniteMatrix,
  config~ : NashSolverConfig = NashSolverConfig::default(),
) -> NashSolverResult raise NashCliError {
  // `config` is unused in Stage 1a but pinned in the signature so the
  // fallback-aware callers do not need to migrate again in Stage 1b/1c.
  ignore(config)
  let lp = try @nash.solve_zero_sum(matrix) catch {
    err => raise InnerError(err.to_string())
  }
  match lp {
    Optimal(value~, row_strategy~, col_strategy~) =>
      {
        value,
        row_strategy,
        col_strategy,
        exploitability: 0.0,
        solver_path: Simplex,
      }
    Infeasible => raise InfeasibleGame
    Unbounded => raise UnboundedGame
  }
}
