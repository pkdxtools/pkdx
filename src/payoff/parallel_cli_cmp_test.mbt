///|
/// Byte-compare `pkdx select --matrix-bits` at parallel 1 / 2 / 4 by
/// spawning the same native binary three times. Parallel 1 is in-process
/// inside that binary; 2 and 4 re-exec it as `__select-shard`.

///|
fn cmp_pkdx_bin() -> String {
  match @env.get_env_var("PKDX_CMP_BIN") {
    Some(p) =>
      if @db.file_exists(p) {
        return p
      } else {
        abort("PKDX_CMP_BIN does not exist: " + p)
      }
    None => ()
  }
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
    "pkdx binary not found. Build src/main before this test, or set PKDX_CMP_BIN.",
  )
}

///|
fn cmp_run_select(
  bin : String,
  parallel : Int,
  input_path : String,
  output_path : String,
  timeout_ms : Int,
) -> String raise @process.RunShardsError {
  let prev = @env.get_env_var("PKDX_SELF_EXEC")
  @env.set_env_var("PKDX_SELF_EXEC", "/bin/sh")
  let script = "env -u PKDX_SELF_EXEC PKDX_DAMAGE_CACHE=/tmp/pkdx_cmp_nocache.sqlite " +
    bin +
    " select --matrix-bits --parallel=" +
    parallel.to_string() +
    " < " +
    input_path +
    " > " +
    output_path
  let results = @process.run_parallel_shards(
    [["/bin/sh", "-c", script]],
    timeout_ms~,
  )
  match prev {
    Some(p) => @env.set_env_var("PKDX_SELF_EXEC", p)
    None => @env.set_env_var("PKDX_SELF_EXEC", "")
  }
  match results[0] {
    Ok => ()
    Exit(code) =>
      abort("pkdx select exited " + code.to_string() + " parallel=" + parallel.to_string())
    Failed =>
      abort("pkdx select failed to spawn, parallel=" + parallel.to_string())
  }
  match @db.read_file(output_path) {
    Some(s) => s
    None => abort("missing select output " + output_path)
  }
}

///|
fn cmp_three(label : String, json : String, timeout_ms : Int) -> Unit raise @process.RunShardsError {
  if !@db.file_exists("/bin/sh") {
    return
  }
  let bin = cmp_pkdx_bin()
  let in_path = "/tmp/pkdx_cmp_" + label + ".json"
  match @db.write_file_str(in_path, json) {
    Ok(_) => ()
    Err(e) => abort("write input failed: " + e)
  }
  let a = cmp_run_select(bin, 1, in_path, "/tmp/pkdx_cmp_" + label + "_p1.json", timeout_ms)
  let b = cmp_run_select(bin, 2, in_path, "/tmp/pkdx_cmp_" + label + "_p2.json", timeout_ms)
  let c = cmp_run_select(bin, 4, in_path, "/tmp/pkdx_cmp_" + label + "_p4.json", timeout_ms)
  if a != b || b != c {
    abort(label + " JSON diverged across parallel 1/2/4")
  }
  if !a.contains("\"matrix_bits\":") {
    abort(label + " output is missing matrix_bits")
  }
}

///|
fn cmp_scale_team(prefix : String, nmoves : Int) -> String {
  let types = [
    "ノーマル", "ほのお", "みず", "くさ", "かくとう", "エスパー",
  ]
  let mut s = "["
  for i in 0..<6 {
    if i > 0 {
      s = s + ","
    }
    let spe = 40 + i * 15
    s = s +
      "{\"name\":\"" +
      prefix +
      i.to_string() +
      "\",\"type1\":\"" +
      types[i % 6] +
      "\",\"type2\":\"\",\"hp\":160,\"atk\":110,\"def\":100,\"spa\":80,\"spd\":90,\"spe\":" +
      spe.to_string() +
      ",\"ability\":\"\",\"item\":\"\",\"tera\":\"\",\"moves\":[" +
      "{\"name\":\"たいあたり\",\"type\":\"" +
      types[i % 6] +
      "\",\"category\":\"物理\",\"power\":70,\"accuracy\":100}"
    if nmoves >= 2 {
      s = s +
        ",{\"name\":\"しんそく\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":40,\"accuracy\":100,\"priority\":2}"
    }
    s = s + "]}"
  }
  s + "]"
}

///|
fn cmp_screened_json(nmoves : Int, model : String, mc_tl : Int) -> String {
  "{\"stat_system\":\"standard\",\"format\":\"single\",\"team\":" +
  cmp_scale_team("S", nmoves) +
  ",\"opponent\":" +
  cmp_scale_team("S", nmoves) +
  ",\"team_payoff_model\":\"" +
  model +
  "\",\"mc_turn_limit\":" +
  mc_tl.to_string() +
  "}"
}

///|
test "screened_small JSON matches at parallel 1/2/4" {
  cmp_three(
    "small",
    cmp_screened_json(1, "screened_switching_game:8:42:0.3:1", 1),
    180_000,
  ) catch {
    e => abort(@debug.to_string(e))
  }
}

///|
test "screened_prod JSON matches at parallel 1/2/4" {
  match @env.get_env_var("PKDX_CMP_PROD") {
    Some("1") => ()
    _ => return
  }
  cmp_three(
    "prod",
    cmp_screened_json(2, "screened_switching_game:1000:42:0.3:5", 5),
    7_200_000,
  ) catch {
    e => abort(@debug.to_string(e))
  }
}

///|
test "screened select rejects non-positive mc_turn_limit" {
  let input = cmp_screened_json(1, "screened_switching_game:8:42:0.3:1", 0)
  try @payoff.run_select(input, parallel=2) catch {
    e => assert_true(e is InvalidJson(_))
  } noraise {
    _ => fail("expected run_select to raise")
  }
}

///|
/// A shard worker that exits 0 without writing its output must surface as
/// an error, not as a silently empty matrix. `/bin/true` stands in for the
/// worker binary; the parent's `PKDX_SELF_EXEC` override is restored after.
test "parallel screened select raises when shard workers write no output" {
  if !@db.file_exists("/bin/true") {
    return
  }
  let prev = @env.get_env_var("PKDX_SELF_EXEC")
  @env.set_env_var("PKDX_SELF_EXEC", "/bin/true")
  let input = cmp_screened_json(1, "screened_switching_game:8:42:0.3:1", 1)
  let outcome = try @payoff.run_select(input, parallel=2) catch {
    _ => "raised"
  }
  match prev {
    Some(p) => @env.set_env_var("PKDX_SELF_EXEC", p)
    None => @env.set_env_var("PKDX_SELF_EXEC", "")
  }
  @debug.assert_eq(outcome, "raised")
}
