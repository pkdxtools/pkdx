///|
/// Phase 10: skill-integration smoke tests. These exercise the CLI handler
/// functions with realistic inputs that the skills are expected to produce,
/// verifying end-to-end shape without running the actual pkdx binary.

///|
test "nash_skill_end_to_end_janken_smoke" {
  // Skill flow: user describes a 3-character monocycle meta. Skill builds the
  // characters JSON and pipes it into `pkdx nash solve`.
  let input =
    #|{
    #|  "characters": [
    #|    {"label": "A", "power": 0, "v": {"x": 2, "y": 0}},
    #|    {"label": "B", "power": 0, "v": {"x": -1, "y": 1.7}},
    #|    {"label": "C", "power": 0, "v": {"x": -1, "y": -1.7}}
    #|  ]
    #|}
  let out = run_nash_solve(input)
  // The skill expects to find the RPS-like cyclic equilibrium: value 0,
  // uniform 1/3 strategy. Parse and spot-check.
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("value") {
        Some(Number(v, ..)) => assert_true(v.abs() < 1.0e-6)
        _ => assert_true(false)
      }
      match m.get("row_strategy") {
        Some(Array(arr)) => {
          assert_true(arr.length() == 3)
          for x in arr {
            match x {
              Number(p, ..) => assert_true((p - 1.0 / 3.0).abs() < 1.0e-5)
              _ => assert_true(false)
            }
          }
        }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "team_builder_phase7_invokes_select_smoke" {
  // Skill flow: team-builder Phase 7 has both team and opponent fully
  // specified. It pipes `{"team":..., "opponent":..., "format":...}` into
  // `pkdx select`. We verify the handler produces a well-formed distribution.
  let team =
    #|[
    #|  {"name":"P0","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":80,"spa":80,"spd":80,"spe":100,"ability":"","item":"","tera":"","moves":[{"name":"のしかかり","type":"ノーマル","category":"物理","power":85}]},
    #|  {"name":"P1","type1":"ノーマル","type2":"","hp":100,"atk":105,"def":80,"spa":80,"spd":80,"spe":95,"ability":"","item":"","tera":"","moves":[{"name":"のしかかり","type":"ノーマル","category":"物理","power":85}]},
    #|  {"name":"P2","type1":"ノーマル","type2":"","hp":100,"atk":110,"def":80,"spa":80,"spd":80,"spe":90,"ability":"","item":"","tera":"","moves":[{"name":"のしかかり","type":"ノーマル","category":"物理","power":85}]},
    #|  {"name":"P3","type1":"ノーマル","type2":"","hp":100,"atk":95,"def":80,"spa":80,"spd":80,"spe":105,"ability":"","item":"","tera":"","moves":[{"name":"のしかかり","type":"ノーマル","category":"物理","power":85}]},
    #|  {"name":"P4","type1":"ノーマル","type2":"","hp":100,"atk":100,"def":80,"spa":80,"spd":80,"spe":110,"ability":"","item":"","tera":"","moves":[{"name":"のしかかり","type":"ノーマル","category":"物理","power":85}]},
    #|  {"name":"P5","type1":"ノーマル","type2":"","hp":100,"atk":90,"def":80,"spa":80,"spd":80,"spe":85,"ability":"","item":"","tera":"","moves":[{"name":"のしかかり","type":"ノーマル","category":"物理","power":85}]}
    #|]
  let input = "{\"team\":" + team + ",\"opponent\":" + team + ",\"format\":\"single\",\"team_payoff_model\":\"switching_game:1\"}"
  let out = run_select(input)
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("format") {
        Some(String(s)) => assert_true(s == "single")
        _ => assert_true(false)
      }
      match m.get("row_strategy") {
        Some(Array(arr)) => {
          assert_true(arr.length() == 20)
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
