///|
/// Helper: build a small team JSON with `n` normalised Pokemon distinguished
/// only by speed. `run_select` evaluates them under `SwitchingGame(1)` /
/// `ScreenedSwitchingGame(1)` (the only remaining `team_payoff_model` variants).
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
      "\"moves\":[{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":85}]}"
  }
  s + "]"
}

///|
fn select_input_json(
  team_speeds : Array[Int],
  opp_speeds : Array[Int],
  format : String,
) -> String {
  select_input_json_with_extra(
    team_speeds, opp_speeds, format,
    ",\"team_payoff_model\":\"switching_game:1\"",
  )
}

///|
/// Variant allowing extra JSON fields (e.g. `team_payoff_model`).
/// `extra` is inserted verbatim before the closing brace, and must start with
/// a comma, e.g. `,"team_payoff_model":"switching_game"`.
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
  let out = run_select(
    select_input_json_with_extra(
      team_sp, opp_sp, "single",
      ",\"team_payoff_model\":\"switching_game:1\"",
    ),
  )
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
test "select_6v6_double_format_currently_unsupported" {
  // After removing the pairwise payoff models, both `SwitchingGame(1)` and
  // `ScreenedSwitchingGame(1)` are Single-only. `format = "double"` must raise
  // until a team-level Double model exists.
  let team_sp = [100, 95, 105, 90, 110, 85]
  let opp_sp = [100, 100, 100, 100, 100, 100]
  let errored = try {
    let _ = run_select(select_input_json(team_sp, opp_sp, "double"))
    false
  } catch {
    _ => true
  }
  assert_true(errored)
}

///|
test "select_favours_faster_side_in_speed_asymmetric_lineup" {
  let team_sp = [150, 150, 150, 150, 150, 150]
  let opp_sp = [50, 50, 50, 50, 50, 50]
  let out = run_select(
    select_input_json_with_extra(
      team_sp, opp_sp, "single",
      ",\"team_payoff_model\":\"switching_game:2\"",
    ),
  )
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("value") {
        Some(Number(v, ..)) => assert_true(v > 0.0)
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
    select_input_json_with_extra(
      [100, 100, 100, 100, 100, 100],
      [100, 100, 100, 100, 100, 100],
      "single",
      ",\"team_payoff_model\":\"switching_game:1\"",
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
  let input = select_input_json_with_extra(
    [100, 100, 100, 100, 100, 100],
    [100, 100, 100, 100, 100, 100],
    "single",
    ",\"team_payoff_model\":\"switching_game:1\"",
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
  let r = compute_select_with_team_model(team, opp, Single, SwitchingGame(1))
  let md = render_select_markdown(r)
  assert_true(md.contains("# Selection Report"))
  assert_true(md.contains("- format: single"))
  assert_true(md.contains("| probability | members |"))
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
test "parse_move_json_reads_priority_and_stat_effects" {
  // Move metadata rides inline on the JSON payload — skills forward
  // `priority` / `stat_effects` from `pkdx moves` output straight through.
  let raw =
    #|{
    #|  "team": [
    #|    {"name":"A0","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"バレットパンチ","type":"はがね","category":"物理","power":40,"priority":1}]},
    #|    {"name":"A1","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"つるぎのまい","type":"ノーマル","category":"変化","power":0,"priority":0,"stat_effects":[[0,2]]}]},
    #|    {"name":"A2","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"じしん","type":"じめん","category":"物理","power":100}]}
    #|  ]
    #|}
  let parsed = match @json.parse(raw) {
    Object(m) =>
      match m.get("team") {
        Some(t) => parse_team_array(t, "team")
        _ => {
          assert_true(false)
          return
        }
      }
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(parsed[0].moves[0].priority, 1)
  assert_eq(parsed[1].moves[0].priority, 0)
  assert_eq(parsed[1].moves[0].stat_effects.length(), 1)
  let eff = parsed[1].moves[0].stat_effects[0]
  assert_eq(eff.stat, 0)
  assert_eq(eff.delta, 2)
  // Legacy 2-element form parses as self-target (0).
  assert_eq(eff.target, 0)
  // Missing optional fields default to 0 / []
  assert_eq(parsed[2].moves[0].priority, 0)
  assert_eq(parsed[2].moves[0].stat_effects.length(), 0)
}

///|
/// Phase 3 contract: 3-element `stat_effects` entries parse with the declared
/// target flag (0=self, 1=opp), and post-hit scalar fields (recoil_num/den,
/// self_ko, recharge) round-trip with their declared values.
test "parse_move_json_3elem_stat_effects_and_posthit_fields" {
  let raw =
    #|{
    #|  "team": [
    #|    {"name":"A","type1":"フェアリー","type2":"","hp":100,"atk":100,"def":100,"spa":100,"spd":100,"spe":200,
    #|     "moves":[{"name":"あまえる","type":"フェアリー","category":"変化","power":0,"priority":0,"stat_effects":[[0,-2,1]]}]},
    #|    {"name":"B","type1":"いわ","type2":"","hp":200,"atk":150,"def":100,"spa":100,"spd":100,"spe":120,
    #|     "moves":[{"name":"もろはのずつき","type":"いわ","category":"物理","power":150,"recoil_num":1,"recoil_den":2}]},
    #|    {"name":"C","type1":"ノーマル","type2":"","hp":100,"atk":150,"def":100,"spa":100,"spd":100,"spe":100,
    #|     "moves":[{"name":"じばく","type":"ノーマル","category":"物理","power":250,"self_ko":true}]},
    #|    {"name":"D","type1":"ノーマル","type2":"","hp":200,"atk":100,"def":100,"spa":200,"spd":100,"spe":120,
    #|     "moves":[{"name":"はかいこうせん","type":"ノーマル","category":"特殊","power":150,"recharge":true}]}
    #|  ]
    #|}
  let parsed = match @json.parse(raw) {
    Object(m) =>
      match m.get("team") {
        Some(t) => parse_team_array(t, "team")
        _ => {
          assert_true(false)
          return
        }
      }
    _ => {
      assert_true(false)
      return
    }
  }
  // Amaeru: opp-target -2 Atk
  let amaeru_eff = parsed[0].moves[0].stat_effects[0]
  assert_eq(amaeru_eff.stat, 0)
  assert_eq(amaeru_eff.delta, -2)
  assert_eq(amaeru_eff.target, 1)
  // Head Smash: 1/2 recoil
  assert_eq(parsed[1].moves[0].recoil_num, 1)
  assert_eq(parsed[1].moves[0].recoil_den, 2)
  assert_eq(parsed[1].moves[0].self_ko, false)
  assert_eq(parsed[1].moves[0].recharge, false)
  // Self-destruct
  assert_eq(parsed[2].moves[0].self_ko, true)
  assert_eq(parsed[2].moves[0].recoil_num, 0)
  // Hyper Beam
  assert_eq(parsed[3].moves[0].recharge, true)
  assert_eq(parsed[3].moves[0].self_ko, false)
}

///|
/// Phase 14: ScreenedSwitchingGame(1) returns a SelectResult whose `selections`
/// / `selection_names` / `row_strategy` are filtered down to retained rows
/// only. `C(4, 3) = 4` selections on each side × `keep_top = 0.5` → 2 rows
/// / 2 cols retained.
test "run_select_with_screened_switching_game_returns_retained_shape" {
  let input = select_input_json_with_extra(
    [100, 100, 100, 100],
    [100, 100, 100, 100],
    "single",
    ",\"team_payoff_model\":\"screened_switching_game:10:42:0.5:1\"",
  )
  let out = run_select(input)
  // Parse the output JSON to read selection-array lengths.
  let root = match @json.parse(out) {
    Object(m) => m
    _ => {
      assert_true(false)
      return
    }
  }
  let selections = match root.get("selections") {
    Some(Array(arr)) => arr
    _ => {
      assert_true(false)
      return
    }
  }
  let opp_selections = match root.get("opp_selections") {
    Some(Array(arr)) => arr
    _ => {
      assert_true(false)
      return
    }
  }
  let row_strategy = match root.get("row_strategy") {
    Some(Array(arr)) => arr
    _ => {
      assert_true(false)
      return
    }
  }
  // 4 selections × keep_top=0.5 → ceil(4 * 0.5) = 2 retained on each axis.
  assert_eq(selections.length(), 2)
  assert_eq(opp_selections.length(), 2)
  // row_strategy must track retained selection shape.
  assert_eq(row_strategy.length(), selections.length())
}

///|
test "run_select_rejects_screened_switching_game_with_double_format" {
  let input = select_input_json_with_extra(
    [100, 100, 100, 100, 100],
    [100, 100, 100, 100, 100],
    "double",
    ",\"team_payoff_model\":\"screened_switching_game:10:42:0.5:1\"",
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
test "select_accepts_team_builder_member_format" {
  let mk = fn(name : String, speed : Int) -> String {
    "{\"name\":\"" + name + "\",\"types\":[\"ノーマル\"],\"base_stats\":{\"h\":100,\"a\":100,\"b\":80,\"c\":80,\"d\":80,\"s\":" + speed.to_string() + "},\"ability\":\"\",\"item\":\"\",\"role\":\"軸\",\"moves\":[{\"name\":\"のしかかり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":85}]}"
  }
  let team = "[" + mk("T0", 100) + "," + mk("T1", 95) + "," + mk("T2", 105) + "," + mk("T3", 90) + "," + mk("T4", 110) + "," + mk("T5", 85) + "]"
  let input = "{\"team\":" + team + ",\"opponent\":" + team + ",\"format\":\"single\",\"team_payoff_model\":\"switching_game:1\"}"
  let out = run_select(input)
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("row_strategy") {
        Some(Array(arr)) => assert_true(arr.length() == 20)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}
