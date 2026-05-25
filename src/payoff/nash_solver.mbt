///|
/// Pkdx-side wrapper around `@nash.solve_zero_sum` with approximate-Nash
/// fallbacks.
///
/// CLI-bound only: recursive DP callsites in `switching_game_turn.mbt`
/// intentionally stay on `@nash.solve_zero_sum` directly — their per-node
/// value-cache semantics differ and the silent-degrade behavior is tracked
/// separately via `silent_dp_fallback_count` (Stage 3).
///
/// Stage 1b: primary simplex with a fictitious_play fallback for the
/// `SimplexFailure` case. The `mwu` fallback and `NashFallbackExhausted`
/// suberror are added in Stage 1c.

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
/// Try the `@nash.fictitious_play` fallback. Returns `Some((p, q, expl))` when
/// the iterative solution lands within `tol` of the equilibrium; `None` when
/// the result is above tolerance and the caller should escalate further.
fn try_fictitious(
  matrix : @nash.FiniteMatrix,
  iterations : Int,
  tol : Double,
) -> (@nash.MixedStrategy, @nash.MixedStrategy, Double)? {
  let (p, q) = @nash.fictitious_play(matrix, iterations)
  let expl = @nash.exploitability(matrix, p, q)
  if expl < tol {
    Some((p, q, expl))
  } else {
    None
  }
}

///|
/// Solve a zero-sum game with the pkdx fallback chain.
///
/// Stage 1b: primary simplex, then a `fictitious_play` retry when the
/// underlying LP raises `SimplexFailure`. If the iterative result exceeds
/// `config.tol`, the original simplex error is re-raised as `InnerError`.
/// Stage 1c will add the `mwu` retry and a dedicated `NashFallbackExhausted`
/// suberror.
pub fn solve_with_fallback(
  matrix : @nash.FiniteMatrix,
  config~ : NashSolverConfig = NashSolverConfig::default(),
) -> NashSolverResult raise NashCliError {
  let lp = try @nash.solve_zero_sum(matrix) catch {
    @nash.SimplexFailure(_) as simplex_err =>
      // Fallback 1: fictitious_play. Accept only when exploitability is
      // within `config.tol`; otherwise re-raise so the CLI surfaces the
      // original simplex failure rather than silently degrading.
      match try_fictitious(matrix, config.iterations, config.tol) {
        Some((p, q, expl)) => {
          let v = @nash.expected_payoff(p, matrix, q)
          return {
            value: v,
            row_strategy: p,
            col_strategy: q,
            exploitability: expl,
            solver_path: FictitiousPlay,
          }
        }
        None => raise InnerError(simplex_err.to_string())
      }
    other => raise InnerError(other.to_string())
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
