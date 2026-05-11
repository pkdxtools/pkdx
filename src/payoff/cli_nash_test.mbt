///|
/// Helper: janken (rock-paper-scissors) payoff matrix as a JSON string.
fn janken_json() -> String {
  "{\"matrix\":[[0,1,-1],[-1,0,1],[1,-1,0]],\"labels\":[\"R\",\"P\",\"S\"]}"
}

///|
test "nash_solve_json_matrix_form" {
  let out = run_nash_solve(janken_json())
  // Must contain the required top-level fields.
  assert_true(out.contains("\"value\":"))
  assert_true(out.contains("\"row_strategy\":"))
  assert_true(out.contains("\"col_strategy\":"))
  assert_true(out.contains("\"exploitability\":"))
  assert_true(out.contains("\"support\":"))
  assert_true(out.contains("\"labels\":"))
}

///|
test "nash_solve_rejects_both_matrix_and_characters" {
  let bad =
    #|{"matrix": [[0, 1], [-1, 0]], "characters": [{"label": "A", "power": 0, "v": {"x": 1, "y": 0}}]}
  let err = try? run_nash_solve(bad)
  assert_true(err is Err(ConflictingInputs))
}

///|
test "nash_solve_rejects_non_square" {
  let bad = "{\"matrix\":[[0,1,-1],[1,0]]}"
  let err = try? run_nash_solve(bad)
  assert_true(err is Err(NonSquareMatrix(_, _)))
}

///|
test "nash_solve_output_json_schema_validates" {
  // Parse the output and verify each required field has the expected type.
  let out = run_nash_solve(janken_json())
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
  let out = run_nash_solve(janken_json())
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
  let err = try? run_nash_solve("not json at all")
  assert_true(err is Err(InvalidJson(_)))
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
  let out = run_nash_graph(janken_json(), 0.5)
  assert_true(out.contains("digraph payoff"))
  // All RPS off-diagonal entries are ±1, which exceed 0.5 → 6 edges.
  inspect(count_arrows(out), content="6")
  // With a threshold above max entry magnitude, no edges remain.
  let sparse = run_nash_graph(janken_json(), 2.0)
  inspect(count_arrows(sparse), content="0")
}

///|
test "nash_graph_node_labels_match_input" {
  let out = run_nash_graph(janken_json(), 0.5)
  assert_true(out.contains("\"R\""))
  assert_true(out.contains("\"P\""))
  assert_true(out.contains("\"S\""))
  // Without labels, nodes fall back to numeric indices.
  let numbered = run_nash_graph(
    "{\"matrix\":[[0,1,-1],[-1,0,1],[1,-1,0]]}", 0.5,
  )
  assert_true(numbered.contains("\"0\""))
  assert_true(numbered.contains("\"2\""))
}

///|
test "nash_solve_rejects_short_labels" {
  let bad = "{\"matrix\":[[0,1],[-1,0]],\"labels\":[\"A\"]}"
  let err = try? run_nash_solve(bad)
  assert_true(err is Err(LabelCountMismatch(2, 1)))
}

///|
test "nash_graph_rejects_short_labels" {
  let bad = "{\"matrix\":[[0,1],[-1,0]],\"labels\":[\"A\"]}"
  let err = try? run_nash_graph(bad, 0.5)
  assert_true(err is Err(LabelCountMismatch(2, 1)))
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
  let err = try? run_nash_graph(bad, 0.0)
  assert_true(err is Err(MissingField(_)))
}

///|
test "nash_graph_team_rejects_opponent_only" {
  let bad = "{\"opponent\":" + build_team_json(2, "O", [100, 100]) + "}"
  let err = try? run_nash_graph(bad, 0.0)
  assert_true(err is Err(MissingField(_)))
}

///|
test "nash_graph_team_rejects_conflict_with_matrix" {
  let bad = "{\"team\":" +
    build_team_json(2, "T", [100, 100]) +
    ",\"opponent\":" +
    build_team_json(2, "O", [100, 100]) +
    ",\"matrix\":[[0,1],[-1,0]]}"
  let err = try? run_nash_graph(bad, 0.0)
  assert_true(err is Err(ConflictingInputs))
}

///|
test "nash_graph_team_rejects_conflict_with_characters" {
  let bad = "{\"team\":" +
    build_team_json(2, "T", [100, 100]) +
    ",\"opponent\":" +
    build_team_json(2, "O", [100, 100]) +
    ",\"characters\":[{\"label\":\"A\",\"power\":0,\"v\":{\"x\":1,\"y\":0}}]}"
  let err = try? run_nash_graph(bad, 0.0)
  assert_true(err is Err(ConflictingInputs))
}

///|
test "nash_graph_team_rejects_user_provided_labels" {
  let bad = build_team_graph_json([100, 100], [100, 100], ",\"labels\":[\"A\",\"B\",\"C\",\"D\"]")
  let err = try? run_nash_graph(bad, 0.0)
  assert_true(err is Err(InvalidJson(_)))
}

///|
test "nash_graph_team_rejects_non_positive_turn_limit" {
  let bad = build_team_graph_json([100, 100], [100, 100], ",\"turn_limit\":0")
  let err = try? run_nash_graph(bad, 0.0)
  assert_true(err is Err(InvalidJson(_)))
}

///|
test "nash_graph_team_emits_stable_node_ids" {
  // Default 2v2, no extra: turn_limit defaults to 1.
  let input = build_team_graph_json([100, 100], [100, 100], "")
  let out = run_nash_graph(input, 0.0)
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
  let out = run_nash_graph(input, 1.0e-6)
  // Threshold above any possible 0-difference value, so no arrows.
  inspect(count_arrows(out), content="0")
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
  let out = run_nash_graph(input, 0.01)
  // strong → weak arrow exists, weak → strong arrow exists (antisymmetric).
  inspect(count_arrows(out), content="2")
  assert_true(out.contains("team_0 -> opp_0"))
  assert_true(out.contains("opp_0 -> team_0"))
}

///|
test "nash_graph_team_accepts_asymmetric_sizes" {
  // team=3, opponent=2: matrix is 5x5, with intra-side blocks all zero.
  let input = build_team_graph_json([100, 100, 100], [100, 100], "")
  let out = run_nash_graph(input, 0.0)
  assert_true(out.contains("team_0"))
  assert_true(out.contains("team_1"))
  assert_true(out.contains("team_2"))
  assert_true(out.contains("opp_0"))
  assert_true(out.contains("opp_1"))
  // 5 nodes total, intra-side blocks are zero (2x2 + 3x3 = 13 zeros plus
  // diagonal). All pairwise cross-side scores are 0 in this symmetric
  // damage setup, so no arrow exceeds threshold > 0.
  inspect(count_arrows(out), content="0")
}

///|
test "nash_graph_team_respects_stat_system_override" {
  let champions = build_team_graph_json([100], [100], ",\"stat_system\":\"champions\"")
  let standard = build_team_graph_json([100], [100], ",\"stat_system\":\"standard\"")
  // Both must produce valid DOT without raising.
  let _ = run_nash_graph(champions, 0.0)
  let _ = run_nash_graph(standard, 0.0)
  let out_c = run_nash_graph(champions, 0.0)
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
  let out = run_nash_graph(input, 0.0)
  assert_true(out.contains("digraph payoff"))
  inspect(count_arrows(out), content="0")
}

///|
test "nash_graph_team_heavy_path_runs" {
  // turn_limit=2 routes through switching_game_winrate. Smoke-test only:
  // the call must succeed and produce a valid DOT string.
  let input = build_team_graph_json([100, 100], [100, 100], ",\"turn_limit\":2")
  let out = run_nash_graph(input, 0.0)
  assert_true(out.contains("digraph payoff"))
}

///|
test "nash_solve_rejects_team_input_as_unsupported" {
  // The shared parser must keep rejecting team input so `pkdx nash solve`
  // continues to refuse this shape after the graph extension.
  let team_form = build_team_graph_json([100, 100], [100, 100], "")
  let err = try? run_nash_solve(team_form)
  assert_true(err is Err(MissingField(_)))
}

///|
test "nash_graph_escapes_control_chars_in_labels" {
  // Label contains a literal newline, tab, and carriage return.
  let with_ctrl =
    "{\"matrix\":[[0,1,-1],[-1,0,1],[1,-1,0]],\"labels\":[\"A\\nX\",\"B\\tY\",\"C\\rZ\"]}"
  let out = run_nash_graph(with_ctrl, 0.5)
  // Must emit escaped sequences, never raw control chars inside quoted ids.
  assert_true(out.contains("\"A\\nX\""))
  assert_true(out.contains("\"B\\tY\""))
  assert_true(out.contains("\"C\\rZ\""))
}
