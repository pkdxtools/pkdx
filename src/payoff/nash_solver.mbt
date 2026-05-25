///|
/// Pkdx-side wrapper around `@nash.solve_zero_sum` with approximate-Nash
/// fallbacks.
///
/// CLI-bound only: recursive DP callsites in `switching_game_turn.mbt`
/// intentionally stay on `@nash.solve_zero_sum` directly — their per-node
/// value-cache semantics differ and the silent-degrade behavior is tracked
/// separately via `silent_dp_fallback_count` (Stage 3).
///
/// Stage 1c: primary simplex with a two-step iterative fallback chain.
/// On `SimplexFailure`, retry with `fictitious_play`; if its exploitability
/// still exceeds `config.tol`, retry once more with `mwu` (learning rate
/// `η = sqrt(ln(max(rows,cols))/iterations)` per Freund & Schapire). When
/// both iterative learners exceed tol, raise `NashFallbackExhausted` with
/// the original simplex error and both observed exploitabilities so the CLI
/// can report how close each approximate solver came.

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
/// Try the `@nash.fictitious_play` fallback. Returns `Ok((p, q, expl))` when
/// the iterative solution lands within `tol` of the equilibrium; `Err(expl)`
/// carries the observed exploitability when the result is above tolerance, so
/// the caller can surface it via `NashFallbackExhausted` after escalating.
fn try_fictitious(
  matrix : @nash.FiniteMatrix,
  iterations : Int,
  tol : Double,
) -> Result[(@nash.MixedStrategy, @nash.MixedStrategy, Double), Double] {
  let (p, q) = @nash.fictitious_play(matrix, iterations)
  let expl = @nash.exploitability(matrix, p, q)
  if expl < tol {
    Ok((p, q, expl))
  } else {
    Err(expl)
  }
}

///|
/// Try the `@nash.mwu` (Multiplicative Weights Update) fallback. Same
/// `Ok((p, q, expl))` / `Err(expl)` contract as `try_fictitious`. Learning rate
/// follows Freund & Schapire: `η = sqrt(ln(max(rows, cols)) / iterations)`,
/// which trades off exploration vs. convergence for finite-horizon MWU.
fn try_mwu(
  matrix : @nash.FiniteMatrix,
  iterations : Int,
  tol : Double,
) -> Result[(@nash.MixedStrategy, @nash.MixedStrategy, Double), Double] {
  let max_dim = if matrix.rows() > matrix.cols() {
    matrix.rows()
  } else {
    matrix.cols()
  }
  let eta = (@math.ln(max_dim.to_double()) / iterations.to_double()).sqrt()
  let (p, q) = @nash.mwu(matrix, iterations, eta)
  let expl = @nash.exploitability(matrix, p, q)
  if expl < tol {
    Ok((p, q, expl))
  } else {
    Err(expl)
  }
}

///|
/// Solve a zero-sum game with the pkdx fallback chain.
///
/// Stage 1c: primary simplex, then a two-step iterative chain on
/// `SimplexFailure`: `fictitious_play` first, `mwu` second. The first solver
/// whose exploitability is below `config.tol` wins. If both exceed tol, raise
/// `NashFallbackExhausted` carrying the original simplex error message and
/// both observed exploitabilities.
pub fn solve_with_fallback(
  matrix : @nash.FiniteMatrix,
  config~ : NashSolverConfig = NashSolverConfig::default(),
) -> NashSolverResult raise NashCliError {
  let lp = try @nash.solve_zero_sum(matrix) catch {
    @nash.SimplexFailure(_) as simplex_err => {
      // Fallback 1: fictitious_play.
      let fp_expl = match try_fictitious(matrix, config.iterations, config.tol) {
        Ok((p, q, expl)) => {
          let v = @nash.expected_payoff(p, matrix, q)
          return {
            value: v,
            row_strategy: p,
            col_strategy: q,
            exploitability: expl,
            solver_path: FictitiousPlay,
          }
        }
        Err(expl) => expl
      }
      // Fallback 2: mwu.
      let mwu_expl = match try_mwu(matrix, config.iterations, config.tol) {
        Ok((p, q, expl)) => {
          let v = @nash.expected_payoff(p, matrix, q)
          return {
            value: v,
            row_strategy: p,
            col_strategy: q,
            exploitability: expl,
            solver_path: Mwu,
          }
        }
        Err(expl) => expl
      }
      raise NashFallbackExhausted(
        simplex_err=simplex_err.to_string(),
        fp_expl~,
        mwu_expl~,
      )
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
