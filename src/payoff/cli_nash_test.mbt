///|
/// Helper: janken (rock-paper-scissors) payoff matrix as a JSON string.
fn janken_json() -> String {
  "{\"matrix\":[[0,1,-1],[-1,0,1],[1,-1,0]],\"labels\":[\"R\",\"P\",\"S\"]}"
}

///|
test "nash_solve_json_matrix_form" {
  let out = @payoff.run_nash_solve(janken_json())
  // Must contain the required top-level fields.
  assert_true(out.contains("\"value\":"))
  assert_true(out.contains("\"row_strategy\":"))
  assert_true(out.contains("\"col_strategy\":"))
  assert_true(out.contains("\"exploitability\":"))
  assert_true(out.contains("\"nash_solver\":"))
  assert_true(out.contains("\"support\":"))
  assert_true(out.contains("\"labels\":"))
}

///|
test "nash_solve_rejects_both_matrix_and_characters" {
  let bad =
    #|{"matrix": [[0, 1], [-1, 0]], "characters": [{"label": "A", "power": 0, "v": {"x": 1, "y": 0}}]}
  try @payoff.run_nash_solve(bad) catch {
    e => assert_true(e is ConflictingInputs)
  } noraise {
    _ => fail("expected run_nash_solve to raise")
  }
}

///|
test "nash_solve_rejects_non_square" {
  let bad = "{\"matrix\":[[0,1,-1],[1,0]]}"
  try @payoff.run_nash_solve(bad) catch {
    e => assert_true(e is NonSquareMatrix(_, _))
  } noraise {
    _ => fail("expected run_nash_solve to raise")
  }
}

///|
test "nash_solve_output_json_schema_validates" {
  // Parse the output and verify each required field has the expected type.
  let out = @payoff.run_nash_solve(janken_json())
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("value") {
        Some(Number(_, ..)) => ()
        _ => {
          assert_true(false)
          return
        }
      }
      match m.get("row_strategy") {
        Some(Array(arr)) => assert_true(arr.length() == 3)
        _ => {
          assert_true(false)
          return
        }
      }
      match m.get("col_strategy") {
        Some(Array(arr)) => assert_true(arr.length() == 3)
        _ => {
          assert_true(false)
          return
        }
      }
      match m.get("exploitability") {
        Some(Number(_, ..)) => ()
        _ => assert_true(false)
      }
      match m.get("nash_solver") {
        Some(String(s)) => assert_true(s == "simplex")
        _ => assert_true(false)
      }
      match m.get("support") {
        Some(Object(s)) => {
          assert_true(s.contains("row"))
          assert_true(s.contains("col"))
        }
        _ => assert_true(false)
      }
      match m.get("labels") {
        Some(Array(arr)) => assert_true(arr.length() == 3)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "nash_solve_reproduces_monocycle_nash_janken_e2e" {
  // RPS: value = 0, uniform 1/3 strategy. Check via parsed output.
  let out = @payoff.run_nash_solve(janken_json())
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("value") {
        Some(Number(v, ..)) => assert_true(v.abs() < 1.0e-7)
        _ => assert_true(false)
      }
      match m.get("row_strategy") {
        Some(Array(arr)) =>
          for i in 0..<3 {
            match arr[i] {
              Number(p, ..) => assert_true((p - 1.0 / 3.0).abs() < 1.0e-6)
              _ => assert_true(false)
            }
          }
        _ => assert_true(false)
      }
      match m.get("exploitability") {
        Some(Number(e, ..)) => assert_true(e < 1.0e-6)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "nash_solve_nonzero_exit_on_infeasible" {
  // Invalid JSON triggers InvalidJson error → CLI would exit non-zero.
  try @payoff.run_nash_solve("not json at all") catch {
    e => assert_true(e is InvalidJson(_))
  } noraise {
    _ => fail("expected run_nash_solve to raise")
  }
}

///|

///|
/// Count non-overlapping " -> " occurrences in `s`.
fn count_arrows(s : String) -> Int {
  let mut count = 0
  let mut i = 0
  while i + 3 < s.length() {
    if s[i] == ' ' && s[i + 1] == '-' && s[i + 2] == '>' && s[i + 3] == ' ' {
      count = count + 1
      i = i + 4
    } else {
      i = i + 1
    }
  }
  count
}

///|
test "nash_graph_outputs_dot_with_threshold_filter" {
  let out = @payoff.run_nash_graph(janken_json(), 0.5)
  assert_true(out.contains("digraph payoff"))
  // All RPS off-diagonal entries are ±1, which exceed 0.5 → 6 edges.
  @debug.debug_inspect(count_arrows(out), content="6")
  // With a threshold above max entry magnitude, no edges remain.
  let sparse = @payoff.run_nash_graph(janken_json(), 2.0)
  @debug.debug_inspect(count_arrows(sparse), content="0")
}

///|
test "nash_graph_node_labels_match_input" {
  let out = @payoff.run_nash_graph(janken_json(), 0.5)
  assert_true(out.contains("\"R\""))
  assert_true(out.contains("\"P\""))
  assert_true(out.contains("\"S\""))
  // Without labels, nodes fall back to numeric indices.
  let numbered = @payoff.run_nash_graph(
    "{\"matrix\":[[0,1,-1],[-1,0,1],[1,-1,0]]}", 0.5,
  )
  assert_true(numbered.contains("\"0\""))
  assert_true(numbered.contains("\"2\""))
}

///|
test "nash_solve_rejects_short_labels" {
  let bad = "{\"matrix\":[[0,1],[-1,0]],\"labels\":[\"A\"]}"
  try @payoff.run_nash_solve(bad) catch {
    e => assert_true(e is LabelCountMismatch(2, 1))
  } noraise {
    _ => fail("expected run_nash_solve to raise")
  }
}

///|
test "nash_graph_rejects_short_labels" {
  let bad = "{\"matrix\":[[0,1],[-1,0]],\"labels\":[\"A\"]}"
  try @payoff.run_nash_graph(bad, 0.5) catch {
    e => assert_true(e is LabelCountMismatch(2, 1))
  } noraise {
    _ => fail("expected run_nash_graph to raise")
  }
}

///|
/// Helper: build a team-form `nash graph` JSON. Reuses `build_team_json`
/// (defined in `cli_select_test.mbt` — same package). Speeds default to
/// 100/100 so the input is symmetric and the matrix is antisymmetric only
/// because of the embedding, not random damage skew.
fn build_team_graph_json(
  team_speeds : Array[Int],
  opp_speeds : Array[Int],
  extra : String,
) -> String {
  "{\"team\":" +
  build_team_json(team_speeds.length(), "T", team_speeds) +
  ",\"opponent\":" +
  build_team_json(opp_speeds.length(), "O", opp_speeds) +
  extra +
  "}"
}

///|
test "nash_graph_team_rejects_partial_team_without_opponent" {
  let bad = "{\"team\":" + build_team_json(2, "T", [100, 100]) + "}"
  try @payoff.run_nash_graph(bad, 0.0) catch {
    e => assert_true(e is MissingField(_))
  } noraise {
    _ => fail("expected run_nash_graph to raise")
  }
}

///|
test "nash_graph_team_rejects_opponent_only" {
  let bad = "{\"opponent\":" + build_team_json(2, "O", [100, 100]) + "}"
  try @payoff.run_nash_graph(bad, 0.0) catch {
    e => assert_true(e is MissingField(_))
  } noraise {
    _ => fail("expected run_nash_graph to raise")
  }
}

///|
test "nash_graph_team_rejects_conflict_with_matrix" {
  let bad = "{\"team\":" +
    build_team_json(2, "T", [100, 100]) +
    ",\"opponent\":" +
    build_team_json(2, "O", [100, 100]) +
    ",\"matrix\":[[0,1],[-1,0]]}"
  try @payoff.run_nash_graph(bad, 0.0) catch {
    e => assert_true(e is ConflictingInputs)
  } noraise {
    _ => fail("expected run_nash_graph to raise")
  }
}

///|
test "nash_graph_team_rejects_conflict_with_characters" {
  let bad = "{\"team\":" +
    build_team_json(2, "T", [100, 100]) +
    ",\"opponent\":" +
    build_team_json(2, "O", [100, 100]) +
    ",\"characters\":[{\"label\":\"A\",\"power\":0,\"v\":{\"x\":1,\"y\":0}}]}"
  try @payoff.run_nash_graph(bad, 0.0) catch {
    e => assert_true(e is ConflictingInputs)
  } noraise {
    _ => fail("expected run_nash_graph to raise")
  }
}

///|
test "nash_graph_team_rejects_user_provided_labels" {
  let bad = build_team_graph_json(
    [100, 100],
    [100, 100],
    ",\"labels\":[\"A\",\"B\",\"C\",\"D\"]",
  )
  try @payoff.run_nash_graph(bad, 0.0) catch {
    e => assert_true(e is InvalidJson(_))
  } noraise {
    _ => fail("expected run_nash_graph to raise")
  }
}

///|
test "nash_graph_team_rejects_non_positive_turn_limit" {
  let bad = build_team_graph_json([100, 100], [100, 100], ",\"turn_limit\":0")
  try @payoff.run_nash_graph(bad, 0.0) catch {
    e => assert_true(e is InvalidJson(_))
  } noraise {
    _ => fail("expected run_nash_graph to raise")
  }
}

///|
test "nash_graph_team_emits_stable_node_ids" {
  // Default 2v2, no extra: turn_limit defaults to 1.
  let input = build_team_graph_json([100, 100], [100, 100], "")
  let out = @payoff.run_nash_graph(input, 0.0)
  assert_true(out.contains("digraph payoff"))
  // Both sides should appear with stable identifiers, separate from labels.
  assert_true(out.contains("team_0"))
  assert_true(out.contains("team_1"))
  assert_true(out.contains("opp_0"))
  assert_true(out.contains("opp_1"))
  // Display labels are derived from member names, not the node id.
  assert_true(out.contains("[label=\"T0\"]"))
  assert_true(out.contains("[label=\"O0\"]"))
}

///|
test "nash_graph_team_builds_antisymmetric_fast_path" {
  // Identical T vs O specs → mean_damage_ratio is symmetric, so all pairwise
  // scores collapse to 0 and no edges cross threshold > 0.
  let input = build_team_graph_json([100, 100], [100, 100], "")
  let out = @payoff.run_nash_graph(input, 1.0e-6)
  // Threshold above any possible 0-difference value, so no arrows.
  @debug.debug_inspect(count_arrows(out), content="0")
}

///|
test "nash_graph_team_emits_arrows_when_score_differs" {
  // Asymmetric speed alone does not change damage ratio in this contrived
  // setup, so we instead build a single-side strong-vs-weak setup by
  // overriding move power via a custom JSON.
  let strong = "[{\"name\":\"S0\",\"type1\":\"ノーマル\",\"type2\":\"\"," +
    "\"hp\":100,\"atk\":150,\"def\":80,\"spa\":80,\"spd\":80,\"spe\":100," +
    "\"ability\":\"\",\"item\":\"\",\"tera\":\"\"," +
    "\"moves\":[{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":120}]}]"
  let weak = "[{\"name\":\"W0\",\"type1\":\"ノーマル\",\"type2\":\"\"," +
    "\"hp\":100,\"atk\":50,\"def\":80,\"spa\":80,\"spd\":80,\"spe\":100," +
    "\"ability\":\"\",\"item\":\"\",\"tera\":\"\"," +
    "\"moves\":[{\"name\":\"たいあたり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":40}]}]"
  let input = "{\"team\":" + strong + ",\"opponent\":" + weak + "}"
  let out = @payoff.run_nash_graph(input, 0.01)
  // strong → weak arrow exists, weak → strong arrow exists (antisymmetric).
  @debug.debug_inspect(count_arrows(out), content="2")
  assert_true(out.contains("team_0 -> opp_0"))
  assert_true(out.contains("opp_0 -> team_0"))
}

///|
test "nash_graph_team_accepts_asymmetric_sizes" {
  // team=3, opponent=2: matrix is 5x5, with intra-side blocks all zero.
  let input = build_team_graph_json([100, 100, 100], [100, 100], "")
  let out = @payoff.run_nash_graph(input, 0.0)
  assert_true(out.contains("team_0"))
  assert_true(out.contains("team_1"))
  assert_true(out.contains("team_2"))
  assert_true(out.contains("opp_0"))
  assert_true(out.contains("opp_1"))
  // 5 nodes total, intra-side blocks are zero (2x2 + 3x3 = 13 zeros plus
  // diagonal). All pairwise cross-side scores are 0 in this symmetric
  // damage setup, so no arrow exceeds threshold > 0.
  @debug.debug_inspect(count_arrows(out), content="0")
}

///|
test "nash_graph_team_respects_stat_system_override" {
  let champions = build_team_graph_json(
    [100],
    [100],
    ",\"stat_system\":\"champions\"",
  )
  let standard = build_team_graph_json(
    [100],
    [100],
    ",\"stat_system\":\"standard\"",
  )
  // Both must produce valid DOT without raising.
  let _ = @payoff.run_nash_graph(champions, 0.0)
  let _ = @payoff.run_nash_graph(standard, 0.0)
  let out_c = @payoff.run_nash_graph(champions, 0.0)
  assert_true(out_c.contains("digraph payoff"))
}

///|
test "nash_graph_team_handles_support_only_combatant" {
  // Combatant with only a status move (power 0) yields mean_damage_ratio = 0
  // for both directions, so the resulting score is 0 and no edges appear.
  let support = "[{\"name\":\"X\",\"type1\":\"ノーマル\",\"type2\":\"\"," +
    "\"hp\":100,\"atk\":100,\"def\":80,\"spa\":80,\"spd\":80,\"spe\":100," +
    "\"ability\":\"\",\"item\":\"\",\"tera\":\"\"," +
    "\"moves\":[{\"name\":\"でんじは\",\"type\":\"でんき\",\"category\":\"変化\",\"power\":0}]}]"
  let input = "{\"team\":" + support + ",\"opponent\":" + support + "}"
  let out = @payoff.run_nash_graph(input, 0.0)
  assert_true(out.contains("digraph payoff"))
  @debug.debug_inspect(count_arrows(out), content="0")
}

///|
test "nash_graph_team_heavy_path_runs" {
  // turn_limit=2 routes through switching_game_winrate. Smoke-test only:
  // the call must succeed and produce a valid DOT string.
  let input = build_team_graph_json([100, 100], [100, 100], ",\"turn_limit\":2")
  let out = @payoff.run_nash_graph(input, 0.0)
  assert_true(out.contains("digraph payoff"))
}

///|
test "nash_solve_rejects_team_input_as_unsupported" {
  // The shared parser must keep rejecting team input so `pkdx nash solve`
  // continues to refuse this shape after the graph extension.
  let team_form = build_team_graph_json([100, 100], [100, 100], "")
  try @payoff.run_nash_solve(team_form) catch {
    e => assert_true(e is MissingField(_))
  } noraise {
    _ => fail("expected run_nash_solve to raise")
  }
}

///|
///|
fn solve_obj(input : String) -> Map[String, Json] raise @payoff.NashCliError {
  let out = @payoff.run_nash_solve(input)
  let parsed = @json.parse(out) catch {
    _ => abort("nash solve output is not json")
  }
  match parsed {
    Object(m) => m
    _ => abort("nash solve output is not an object")
  }
}

///|
fn num_field(m : Map[String, Json], key : String) -> Double {
  match m.get(key) {
    Some(Number(n, ..)) => n
    _ => abort("missing number field " + key)
  }
}

///|
fn str_field(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(String(s)) => s
    _ => abort("missing string field " + key)
  }
}

///|
fn num_array_field(m : Map[String, Json], key : String) -> Array[Double] {
  match m.get(key) {
    Some(Array(arr)) => {
      let out = Array::make(arr.length(), 0.0)
      for i in 0..<arr.length() {
        match arr[i] {
          Number(n, ..) => out[i] = n
          _ => abort(key + " element is not a number")
        }
      }
      out
    }
    _ => abort("missing array field " + key)
  }
}

///|
fn assert_near(got : Double, want : Double) -> Unit raise {
  assert_true((got - want).abs() < 1.0e-6)
}

///|
fn assert_dist(xs : Array[Double]) -> Unit raise {
  let mut s = 0.0
  for x in xs {
    assert_true(x >= -1.0e-12)
    s = s + x
  }
  assert_true((s - 1.0).abs() < 1.0e-6)
}

///|
fn assert_pure(xs : Array[Double], idx : Int) -> Unit raise {
  assert_true(idx >= 0 && idx < xs.length())
  for i in 0..<xs.length() {
    let want = if i == idx { 1.0 } else { 0.0 }
    assert_near(xs[i], want)
  }
}

///|
/// Simplex succeeds on these closed-form games, so `nash_solver` stays
/// `"simplex"` and the value / equilibrium match the known solution.
test "nash_solve_simplex_games_keep_known_equilibria" {
  // Rock-paper-scissors: value 0, uniform 1/3.
  let rps = solve_obj(janken_json())
  assert_true(str_field(rps, "nash_solver") == "simplex")
  assert_near(num_field(rps, "value"), 0.0)
  assert_true(num_field(rps, "exploitability") < 1.0e-6)
  let rps_row = num_array_field(rps, "row_strategy")
  let rps_col = num_array_field(rps, "col_strategy")
  let third = 1.0 / 3.0
  for i in 0..<3 {
    assert_near(rps_row[i], third)
    assert_near(rps_col[i], third)
  }
  // Matching pennies: value 0, uniform 1/2.
  let pennies = solve_obj("{\"matrix\":[[1,-1],[-1,1]]}")
  assert_true(str_field(pennies, "nash_solver") == "simplex")
  assert_near(num_field(pennies, "value"), 0.0)
  assert_true(num_field(pennies, "exploitability") < 1.0e-6)
  let pen_row = num_array_field(pennies, "row_strategy")
  let pen_col = num_array_field(pennies, "col_strategy")
  assert_near(pen_row[0], 0.5)
  assert_near(pen_row[1], 0.5)
  assert_near(pen_col[0], 0.5)
  assert_near(pen_col[1], 0.5)
  // 2x2 closed form: v = 2.5, p0 = 0.5, q0 = 0.75.
  let closed = solve_obj("{\"matrix\":[[3,1],[2,4]]}")
  assert_true(str_field(closed, "nash_solver") == "simplex")
  assert_near(num_field(closed, "value"), 2.5)
  assert_true(num_field(closed, "exploitability") < 1.0e-6)
  let closed_row = num_array_field(closed, "row_strategy")
  let closed_col = num_array_field(closed, "col_strategy")
  assert_near(closed_row[0], 0.5)
  assert_near(closed_row[1], 0.5)
  assert_near(closed_col[0], 0.75)
  assert_near(closed_col[1], 0.25)
  // Pure saddle at (0, 0), value 2. Reported as simplex: the saddle fast
  // path lives inside solve_zero_sum.
  let saddle = solve_obj("{\"matrix\":[[2,3,5],[1,2,4],[0,1,3]]}")
  assert_true(str_field(saddle, "nash_solver") == "simplex")
  assert_near(num_field(saddle, "value"), 2.0)
  assert_true(num_field(saddle, "exploitability") < 1.0e-6)
  assert_pure(num_array_field(saddle, "row_strategy"), 0)
  assert_pure(num_array_field(saddle, "col_strategy"), 0)
  // Constant matrix. Every pure profile is an equilibrium; the saddle
  // detector returns the first row and first column.
  let flat = solve_obj(
    "{\"matrix\":[[0.25,0.25,0.25,0.25],[0.25,0.25,0.25,0.25],[0.25,0.25,0.25,0.25],[0.25,0.25,0.25,0.25]]}",
  )
  assert_true(str_field(flat, "nash_solver") == "simplex")
  assert_near(num_field(flat, "value"), 0.25)
  assert_true(num_field(flat, "exploitability") < 1.0e-6)
  assert_pure(num_array_field(flat, "row_strategy"), 0)
  assert_pure(num_array_field(flat, "col_strategy"), 0)
  // Shapley 3x3 is a pure saddle at (0, 0) with value 0.
  let shapley = solve_obj("{\"matrix\":[[0,0,1],[0,0,-1],[-1,1,0]]}")
  assert_true(str_field(shapley, "nash_solver") == "simplex")
  assert_near(num_field(shapley, "value"), 0.0)
  assert_true(num_field(shapley, "exploitability") < 1.0e-6)
  assert_pure(num_array_field(shapley, "row_strategy"), 0)
  assert_pure(num_array_field(shapley, "col_strategy"), 0)
  // Each RPS action duplicated once. Class totals stay 1/3; which copy
  // carries the mass is not unique.
  let dup = solve_obj(
    "{\"matrix\":[[0,0,-1,-1,1,1],[0,0,-1,-1,1,1],[1,1,0,0,-1,-1],[1,1,0,0,-1,-1],[-1,-1,1,1,0,0],[-1,-1,1,1,0,0]]}",
  )
  assert_true(str_field(dup, "nash_solver") == "simplex")
  assert_near(num_field(dup, "value"), 0.0)
  assert_true(num_field(dup, "exploitability") < 1.0e-6)
  let dup_row = num_array_field(dup, "row_strategy")
  let dup_col = num_array_field(dup, "col_strategy")
  assert_dist(dup_row)
  assert_dist(dup_col)
  assert_near(dup_row[0] + dup_row[1], third)
  assert_near(dup_row[2] + dup_row[3], third)
  assert_near(dup_row[4] + dup_row[5], third)
  assert_near(dup_col[0] + dup_col[1], third)
  assert_near(dup_col[2] + dup_col[3], third)
  assert_near(dup_col[4] + dup_col[5], third)
  // Identical rows. Column plays the minimizing entry (index 1, payoff -2).
  let tied = solve_obj(
    "{\"matrix\":[[1,-2,3,0],[1,-2,3,0],[1,-2,3,0],[1,-2,3,0]]}",
  )
  assert_true(str_field(tied, "nash_solver") == "simplex")
  assert_near(num_field(tied, "value"), -2.0)
  assert_true(num_field(tied, "exploitability") < 1.0e-6)
  assert_pure(num_array_field(tied, "row_strategy"), 0)
  assert_pure(num_array_field(tied, "col_strategy"), 1)
}

///|
fn degenerate_60_input(extra : String) -> String {
  let raw = match
    @db.read_file("tests/fixtures/nash_simplex_failure_60x60.json") {
    Some(s) => s
    None => abort("missing tests/fixtures/nash_simplex_failure_60x60.json")
  }
  "{\"matrix\":" + raw + extra + "}"
}

///|
test "nash_solve_degenerate_60x60_uses_fictitious_play_fallback" {
  let m = solve_obj(degenerate_60_input(""))
  assert_true(str_field(m, "nash_solver") == "fictitious_play")
  let v = num_field(m, "value")
  assert_true(v >= -0.23 && v <= 0.28)
  let expl = num_field(m, "exploitability")
  assert_true(expl < 0.05)
  let row = num_array_field(m, "row_strategy")
  let col = num_array_field(m, "col_strategy")
  assert_eq(row.length(), 60)
  assert_eq(col.length(), 60)
  assert_dist(row)
  assert_dist(col)
}

///|
test "nash_solve_degenerate_60x60_tight_tol_raises_fallback_exhausted" {
  let input = degenerate_60_input(
    ",\"nash_solver_config\":{\"tol\":1e-10,\"iterations\":100}",
  )
  try @payoff.run_nash_solve(input) catch {
    NashFallbackExhausted(simplex_err~, fp_expl~, mwu_expl~) => {
      assert_true(simplex_err.length() > 0)
      assert_true(fp_expl >= 1.0e-10)
      assert_true(mwu_expl >= 1.0e-10)
    }
    _ => fail("expected NashFallbackExhausted")
  } noraise {
    _ => fail("expected run_nash_solve to raise")
  }
}

///|
fn assert_invalid_config(input : String, needle : String) -> Unit raise {
  try @payoff.run_nash_solve(input) catch {
    InvalidJson(msg) => assert_true(msg.contains(needle))
    _ => fail("expected InvalidJson")
  } noraise {
    _ => fail("expected run_nash_solve to raise")
  }
}

///|
test "nash_solve_rejects_bad_nash_solver_config" {
  let base = "{\"matrix\":[[0,1],[-1,0]]"
  assert_invalid_config(
    base + ",\"nash_solver_config\":{\"tol\":\"loose\"}}",
    "nash_solver_config.tol must be a number",
  )
  assert_invalid_config(
    base + ",\"nash_solver_config\":{\"tol\":0}}",
    "nash_solver_config.tol must be > 0",
  )
  assert_invalid_config(
    base + ",\"nash_solver_config\":{\"tol\":-0.1}}",
    "nash_solver_config.tol must be > 0",
  )
  assert_invalid_config(
    base + ",\"nash_solver_config\":{\"iterations\":1.5}}",
    "nash_solver_config.iterations must be a positive integer",
  )
  assert_invalid_config(
    base + ",\"nash_solver_config\":{\"iterations\":0}}",
    "nash_solver_config.iterations must be > 0",
  )
  assert_invalid_config(
    base + ",\"nash_solver_config\":[]}",
    "nash_solver_config must be an object",
  )
}

///|
test "nash_graph_escapes_control_chars_in_labels" {
  // Label contains a literal newline, tab, and carriage return.
  let with_ctrl = "{\"matrix\":[[0,1,-1],[-1,0,1],[1,-1,0]],\"labels\":[\"A\\nX\",\"B\\tY\",\"C\\rZ\"]}"
  let out = @payoff.run_nash_graph(with_ctrl, 0.5)
  // Must emit escaped sequences, never raw control chars inside quoted ids.
  assert_true(out.contains("\"A\\nX\""))
  assert_true(out.contains("\"B\\tY\""))
  assert_true(out.contains("\"C\\rZ\""))
}
