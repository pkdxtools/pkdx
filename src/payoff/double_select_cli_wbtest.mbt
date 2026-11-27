///|
/// `pkdx select` の入口。`format=double` / `doubles` でモデルを省略すると
/// `double_dp:1` の選出 Nash が返り、`selection_roles` は先発 2 + 控え 2。

///|
fn protect_double_side(prefix : String) -> String {
  let mut s = "["
  for i in 0..<6 {
    if i > 0 {
      s = s + ","
    }
    s = s +
      "{\"name\":\"" +
      prefix +
      i.to_string() +
      "\",\"type1\":\"ノーマル\",\"type2\":\"\",\"hp\":120,\"atk\":80,\"def\":80," +
      "\"spa\":80,\"spd\":80,\"spe\":" +
      (40 + i).to_string() +
      ",\"ability\":\"\",\"item\":\"\",\"tera\":\"\"," +
      "\"moves\":[{\"name\":\"まもる\",\"type\":\"ノーマル\",\"category\":\"変化\",\"power\":0,\"accuracy\":101,\"target\":7}]}"
  }
  s + "]"
}

///|
fn protect_double_json(format : String, extra : String) -> String {
  "{\"team\":" +
  protect_double_side("P") +
  ",\"opponent\":" +
  protect_double_side("Q") +
  ",\"format\":\"" +
  format +
  "\"" +
  extra +
  "}"
}

///|
fn assert_double_bring_json(out : String) -> Unit raise {
  assert_true(out.contains("\"selection_roles\":[\"lead\",\"lead\",\"bench\",\"bench\"]"))
  let parsed = @json.parse(out)
  match parsed {
    Object(obj) => {
      match obj.get("format") {
        Some(String(s)) => assert_true(s == "double")
        _ => assert_true(false)
      }
      match obj.get("selection_roles") {
        Some(Array(roles)) => {
          assert_true(roles.length() == 4)
          match (roles[0], roles[1], roles[2], roles[3]) {
            (String(a), String(b), String(c), String(d)) =>
              assert_true(
                a == "lead" && b == "lead" && c == "bench" && d == "bench",
              )
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
      match obj.get("selections") {
        Some(Array(rows)) => {
          assert_true(rows.length() == 90)
          match rows[0] {
            Array(cols) => {
              assert_true(cols.length() == 4)
              match (cols[0], cols[1], cols[2], cols[3]) {
                (Number(a, ..), Number(b, ..), Number(c, ..), Number(d, ..)) =>
                  assert_true(
                    a.to_int() == 0 &&
                    b.to_int() == 1 &&
                    c.to_int() == 2 &&
                    d.to_int() == 3,
                  )
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
      match obj.get("row_strategy") {
        Some(Array(ps)) => {
          assert_true(ps.length() == 90)
          let mut sum = 0.0
          for p in ps {
            match p {
              Number(x, ..) => sum = sum + x
              _ => assert_true(false)
            }
          }
          let gap = if sum > 1.0 { sum - 1.0 } else { 1.0 - sum }
          assert_true(gap < 0.000001)
        }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
fn invalid_json_message(input : String) -> String {
  try {
    let _ = run_select(input)
    ""
  } catch {
    InvalidJson(msg) => msg
    _ => "other"
  }
}

///|
test "format double without a model uses double_dp:1" {
  let omitted = protect_double_json("double", "")
  let explicit = protect_double_json(
    "double",
    ",\"team_payoff_model\":\"double_dp:" +
    DOUBLE_DEFAULT_DP_TURN_LIMIT.to_string() +
    "\"",
  )
  let out = run_select(omitted)
  assert_double_bring_json(out)
  let pinned = run_select(explicit)
  assert_true(out == pinned)
}

///|
test "format doubles is an alias and keeps selection_roles" {
  let out = run_select(protect_double_json("doubles", ""))
  assert_double_bring_json(out)
  let single_word = run_select(protect_double_json("double", ""))
  assert_true(out == single_word)
}

///|
test "switching_game on format double names the single-only model" {
  let msg = invalid_json_message(
    "{\"team\":[],\"opponent\":[],\"format\":\"double\",\"team_payoff_model\":\"switching_game\"}",
  )
  assert_true(msg.contains("switching_game does not support double format"))
  assert_true(msg.contains("double_dp"))
}

///|
test "screened_switching_game on format doubles names the single-only model" {
  let msg = invalid_json_message(
    "{\"team\":[],\"opponent\":[],\"format\":\"doubles\",\"team_payoff_model\":\"screened_switching_game:8:1:0.3\"}",
  )
  assert_true(
    msg.contains("screened_switching_game does not support double format"),
  )
}

///|
test "double_dp on format single names the double-only model" {
  let msg = invalid_json_message(
    "{\"team\":[],\"opponent\":[],\"format\":\"single\",\"team_payoff_model\":\"double_dp:1\"}",
  )
  assert_true(msg.contains("support only format double"))
  assert_true(msg.contains("switching_game"))
}

///|
test "double_rollout on format singles names the double-only model" {
  let msg = invalid_json_message(
    "{\"team\":[],\"opponent\":[],\"format\":\"singles\",\"team_payoff_model\":\"double_rollout:1:1:1\"}",
  )
  assert_true(msg.contains("support only format double"))
}

///|
test "parse_format accepts singles and doubles" {
  match parse_format("singles") {
    Single => ()
    _ => assert_true(false)
  }
  match parse_format("doubles") {
    Double => ()
    _ => assert_true(false)
  }
  match default_team_payoff_model(Double) {
    DoubleTurnGame(Exact(n)) =>
      @debug.assert_eq(n, DOUBLE_DEFAULT_DP_TURN_LIMIT)
    _ => assert_true(false)
  }
  match default_team_payoff_model(Single) {
    SwitchingGame(n) => @debug.assert_eq(n, DP_TURN_LIMIT)
    _ => assert_true(false)
  }
}

///|
fn double_select_bin() -> String {
  let cands = [
    "_build/native/release/build/src/main/main.exe",
    "_build/native/debug/build/src/main/main.exe",
  ]
  for c in cands {
    if @db.file_exists(c) {
      return c
    }
  }
  abort(
    "pkdx binary not found. Build src/main before this test.",
  )
}

///|
fn run_select_binary(bin : String, input : String) -> String raise @process.RunShardsError {
  let in_path = "/tmp/pkdx_double_select_cli.json"
  let out_path = "/tmp/pkdx_double_select_cli_out.json"
  match @db.write_file_str(in_path, input) {
    Ok(_) => ()
    Err(e) => abort("write input failed: " + e)
  }
  let prev = @env.get_env_var("PKDX_SELF_EXEC")
  @env.set_env_var("PKDX_SELF_EXEC", "/bin/sh")
  let script = "env -u PKDX_SELF_EXEC PKDX_DAMAGE_CACHE=/tmp/pkdx_double_select_nocache.sqlite " +
    bin +
    " select --parallel=1 < " +
    in_path +
    " > " +
    out_path
  let results = @process.run_parallel_shards(
    [["/bin/sh", "-c", script]],
    timeout_ms=120_000,
  )
  match prev {
    Some(p) => @env.set_env_var("PKDX_SELF_EXEC", p)
    None => @env.set_env_var("PKDX_SELF_EXEC", "")
  }
  match results[0] {
    Ok => ()
    Exit(code) => abort("pkdx select exited " + code.to_string())
    Failed => abort("pkdx select failed to spawn")
  }
  match @db.read_file(out_path) {
    Some(s) => s
    None => abort("missing select output")
  }
}

///|
test "pkdx select CLI prints double selection_roles" {
  if !@db.file_exists("/bin/sh") {
    return
  }
  let bin = double_select_bin()
  let out = run_select_binary(bin, protect_double_json("double", "")) catch {
    e => abort(@debug.to_string(e))
  }
  let trimmed = out.trim(chars="\r\n").to_owned()
  assert_double_bring_json(trimmed)
  let via_handler = run_select(protect_double_json("doubles", ""))
  assert_true(trimmed == via_handler)
}
