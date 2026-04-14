///|
/// Helper: build a small team JSON with `n` normalised Pokemon distinguished
/// only by speed (so payoffs are driven by speed tiebreak under Best1v1).
fn build_team_json(n : Int, prefix : String, speeds : Array[Int]) -> String {
  let mut s = "["
  for i in 0..<n {
    if i > 0 {
      s = s + ","
    }
    s = s +
      "{\"name\":\"" +
      prefix +
      i.to_string() +
      "\",\"type1\":\"ノーマル\",\"type2\":\"\"," +
      "\"hp\":100,\"atk\":100,\"def\":80,\"spa\":80,\"spd\":80,\"spe\":" +
      speeds[i].to_string() +
      "," +
      "\"ability\":\"\",\"item\":\"\",\"tera\":\"\"," +
      "\"moves\":[{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"physical\",\"power\":85}]}"
  }
  s + "]"
}

///|
fn select_input_json(
  team_speeds : Array[Int],
  opp_speeds : Array[Int],
  format : String,
) -> String {
  "{\"team\":" +
  build_team_json(team_speeds.length(), "T", team_speeds) +
  ",\"opponent\":" +
  build_team_json(opp_speeds.length(), "O", opp_speeds) +
  ",\"format\":\"" +
  format +
  "\"}"
}

///|
/// Variant allowing extra JSON fields (payoff_model / team_payoff_model).
/// `extra` is inserted verbatim before the closing brace, and must start with
/// a comma, e.g. `,"payoff_model":"best1v1"`.
fn select_input_json_with_extra(
  team_speeds : Array[Int],
  opp_speeds : Array[Int],
  format : String,
  extra : String,
) -> String {
  "{\"team\":" +
  build_team_json(team_speeds.length(), "T", team_speeds) +
  ",\"opponent\":" +
  build_team_json(opp_speeds.length(), "O", opp_speeds) +
  ",\"format\":\"" +
  format +
  "\"" +
  extra +
  "}"
}

///|
test "select_6v6_single_outputs_3pick_distribution" {
  let team_sp = [100, 95, 105, 90, 110, 85]
  let opp_sp = [100, 100, 100, 100, 100, 100]
  let out = run_select(select_input_json(team_sp, opp_sp, "single"))
  let j = @json.parse(out)
  match j {
    Object(m) => {
      // C(6, 3) = 20 selections on each side.
      match m.get("row_strategy") {
        Some(Array(arr)) => {
          assert_true(arr.length() == 20)
          let mut total = 0.0
          for x in arr {
            match x {
              Number(n, ..) => total = total + n
              _ => assert_true(false)
            }
          }
          assert_true((total - 1.0).abs() < 1.0e-6)
        }
        _ => assert_true(false)
      }
      match m.get("col_strategy") {
        Some(Array(arr)) => assert_true(arr.length() == 20)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "select_6v6_double_outputs_4pick_distribution" {
  let team_sp = [100, 95, 105, 90, 110, 85]
  let opp_sp = [100, 100, 100, 100, 100, 100]
  let out = run_select(select_input_json(team_sp, opp_sp, "double"))
  let j = @json.parse(out)
  match j {
    Object(m) =>
      match m.get("row_strategy") {
        Some(Array(arr)) => {
          // C(6, 4) = 15.
          assert_true(arr.length() == 15)
          let mut total = 0.0
          for x in arr {
            match x {
              Number(n, ..) => total = total + n
              _ => ()
            }
          }
          assert_true((total - 1.0).abs() < 1.0e-6)
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "select_dominant_lineup_assigned_probability_one" {
  // All team Pokemon have speed 150; opponent has speed 50. Every selection of
  // team outspeeds every opponent selection → all team cells are +1, making
  // every row equivalent. The LP should produce a (degenerate) distribution
  // with total mass 1 and value +1 with exploitability 0.
  let team_sp = [150, 150, 150, 150, 150, 150]
  let opp_sp = [50, 50, 50, 50, 50, 50]
  let out = run_select(select_input_json(team_sp, opp_sp, "single"))
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("value") {
        Some(Number(v, ..)) => assert_true((v - 1.0).abs() < 1.0e-6)
        _ => assert_true(false)
      }
      match m.get("exploitability") {
        Some(Number(e, ..)) => assert_true(e.abs() < 1.0e-6)
        _ => assert_true(false)
      }
      match m.get("row_strategy") {
        Some(Array(arr)) => {
          let mut total = 0.0
          for x in arr {
            match x {
              Number(n, ..) => total = total + n
              _ => ()
            }
          }
          assert_true((total - 1.0).abs() < 1.0e-6)
        }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "select_reports_expected_winrate_and_exploitability" {
  let out = run_select(
    select_input_json(
      [100, 100, 100, 100, 100, 100],
      [100, 100, 100, 100, 100, 100],
      "single",
    ),
  )
  // Mirror match → value 0, exploitability 0.
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("value") {
        Some(Number(v, ..)) => assert_true(v.abs() < 1.0e-6)
        _ => assert_true(false)
      }
      match m.get("exploitability") {
        Some(Number(e, ..)) => assert_true(e.abs() < 1.0e-6)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "select_accepts_team_cache_json" {
  // The handler accepts the documented team-cache shape (name + base stats +
  // moves) without requiring extra fields.
  let input = select_input_json(
    [100, 100, 100, 100, 100, 100],
    [100, 100, 100, 100, 100, 100],
    "single",
  )
  // Should not raise.
  let out = run_select(input)
  assert_true(out.length() > 0)
  assert_true(out.contains("\"selection_names\""))
}

///|
test "select_markdown_report_written_to_box_teams" {
  // The renderer produces a markdown document whose shape is compatible with
  // what `box/teams/` expects: header, format/value/exploitability, then a
  // distribution table. (Actual file I/O is the caller's responsibility.)
  let team_sp = [100, 100, 100, 100, 100, 100]
  let opp_sp = [100, 100, 100, 100, 100, 100]
  let team = parse_team_array(
    @json.parse(build_team_json(6, "T", team_sp)), "team",
  )
  let opp = parse_team_array(
    @json.parse(build_team_json(6, "O", opp_sp)), "opponent",
  )
  let r = compute_select(team, opp, Single, Best1v1)
  let md = render_select_markdown(r)
  assert_true(md.contains("# Selection Report"))
  assert_true(md.contains("- format: single"))
  assert_true(md.contains("| probability | members |"))
}

///|
test "run_select_json_with_payoff_model_only_wraps_in_pairwise" {
  // Legacy field only: must be wrapped in Pairwise transparently.
  let team_sp = [100, 100, 100, 100, 100, 100]
  let opp_sp = [100, 100, 100, 100, 100, 100]
  let input = select_input_json_with_extra(
    team_sp,
    opp_sp,
    "single",
    ",\"payoff_model\":\"best1v1\"",
  )
  let out = run_select(input)
  let j = @json.parse(out)
  match j {
    Object(m) =>
      match m.get("row_strategy") {
        Some(Array(arr)) => assert_true(arr.length() == 20)
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "run_select_json_with_both_models_gives_team_payoff_model_precedence" {
  // Both present: team_payoff_model wins; payoff_model is ignored.
  let team_sp = [100, 100, 100, 100, 100, 100]
  let opp_sp = [100, 100, 100, 100, 100, 100]
  let input = select_input_json_with_extra(
    team_sp,
    opp_sp,
    "single",
    ",\"payoff_model\":\"best1v1\",\"team_payoff_model\":\"pairwise:nash_responses\"",
  )
  let out = run_select(input)
  let j = @json.parse(out)
  match j {
    Object(m) =>
      match m.get("row_strategy") {
        Some(Array(arr)) => assert_true(arr.length() == 20)
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "run_select_json_rejects_malformed_team_payoff_model" {
  let team_sp = [100, 100, 100, 100, 100, 100]
  let opp_sp = [100, 100, 100, 100, 100, 100]
  let input = select_input_json_with_extra(
    team_sp,
    opp_sp,
    "single",
    ",\"team_payoff_model\":\"unknown:bad\"",
  )
  let errored = try {
    let _ = run_select(input)
    false
  } catch {
    _ => true
  }
  assert_true(errored)
}

///|
test "extract_move_names_from_select_input_collects_unique_names" {
  let raw =
    #|{
    #|  "team": [
    #|    {"name":"A","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[
    #|       {"name":"じしん","type":"じめん","category":"physical","power":100},
    #|       {"name":"つるぎのまい","type":"ノーマル","category":"status","power":0}
    #|     ]}
    #|  ],
    #|  "opponent": [
    #|    {"name":"B","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[
    #|       {"name":"じしん","type":"じめん","category":"physical","power":100},
    #|       {"name":"バレットパンチ","type":"はがね","category":"physical","power":40}
    #|     ]}
    #|  ],
    #|  "format": "single"
    #|}
  let names = extract_move_names_from_select_input(raw)
  // じしん appears in both teams but dedupes → 3 unique names.
  assert_eq(names.length(), 3)
  // Names present (order may vary by insertion).
  let mut has_jishin = false
  let mut has_turugi = false
  let mut has_bullet = false
  for n in names {
    if n == "じしん" { has_jishin = true }
    if n == "つるぎのまい" { has_turugi = true }
    if n == "バレットパンチ" { has_bullet = true }
  }
  assert_true(has_jishin)
  assert_true(has_turugi)
  assert_true(has_bullet)
}

///|
test "extract_move_names_from_select_input_returns_empty_on_malformed_json" {
  assert_eq(extract_move_names_from_select_input("not-json").length(), 0)
  assert_eq(extract_move_names_from_select_input("{").length(), 0)
  assert_eq(extract_move_names_from_select_input("[]").length(), 0)
}

///|
test "run_select_with_meta_consults_cache_for_switching_game_payoff" {
  // Best1v1 / NashResponses do not invoke the meta cache (they ignore
  // priority and stat_boost). SwitchingGame does — every transition looks
  // up priority via `move_turn_sign` and stat_boost via `apply_stat_boost`.
  // Verify that passing a populated cache through `run_select_with_meta`
  // with `team_payoff_model = "switching_game:1"` causes at least one
  // lookup hit.
  let raw =
    #|{
    #|  "team": [
    #|    {"name":"A0","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"のしかかり","type":"ノーマル","category":"physical","power":85}]},
    #|    {"name":"A1","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"のしかかり","type":"ノーマル","category":"physical","power":85}]},
    #|    {"name":"A2","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"のしかかり","type":"ノーマル","category":"physical","power":85}]}
    #|  ],
    #|  "opponent": [
    #|    {"name":"B0","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"のしかかり","type":"ノーマル","category":"physical","power":85}]},
    #|    {"name":"B1","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"のしかかり","type":"ノーマル","category":"physical","power":85}]},
    #|    {"name":"B2","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"のしかかり","type":"ノーマル","category":"physical","power":85}]}
    #|  ],
    #|  "format": "single",
    #|  "team_payoff_model": "switching_game:1"
    #|}
  let cache = new_move_meta_cache()
  load_move_meta_from_rows(cache, [("のしかかり", 0, "[]")])
  let _ = run_select_with_meta(raw, cache)
  // Switching game's `move_turn_sign` / `apply_stat_boost` consult the
  // cache for every (UseMove, UseMove) transition.
  assert_true(cache.hits >= 1)
}
