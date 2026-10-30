///|
/// Black-box smoke for the public select-bench API. Wall-clock thresholds
/// are intentionally absent. Status-node comparison lives in the white-box
/// test so it can call the private cell helper.

///|
test "select-bench smoke tier is deterministic and profiles DP" {
  let ids = @payoff.select_bench_case_ids("smoke")
  assert_eq(ids.length(), 4)
  assert_eq(ids[0], "nash_rps_3")
  for id in ids {
    let a = @payoff.run_select_bench_case(id, repeats=1)
    let b = @payoff.run_select_bench_case(id, repeats=1)
    assert_true(a.value == b.value)
    assert_true(a.solver == b.solver)
    assert_eq(a.dp_nodes, b.dp_nodes)
    assert_eq(a.dp_lp, b.dp_lp)
    assert_eq(a.screen_lp, b.screen_lp)
    assert_true(a.wall_ms_median >= 0.0)
    assert_true(a.vm_hwm_kb == -1 || a.vm_hwm_kb > 0)
  }
  let rps = @payoff.run_select_bench_case("nash_rps_3", repeats=1)
  inspect(rps.solver, content="simplex")
  inspect(rps.value, content="0")
  assert_eq(rps.dp_nodes, 0)
  assert_eq(rps.dp_lp, 0)
  let shallow = @payoff.run_select_bench_case("select_3v3_tl1", repeats=1)
  assert_true(shallow.dp_nodes > 0)
  assert_true(shallow.cells > 0)
  assert_true(shallow.phases.contains("dp-full"))
  assert_true(shallow.phases.contains("select-nash"))
  let screened = @payoff.run_select_bench_case("select_screened_3v3", repeats=1)
  assert_true(screened.screen_lp >= 1)
  assert_true(screened.phases.contains("screening"))
  assert_true(!@payoff.dp_profile_enabled.val)
}

///|
test "select-bench registers the status-heavy case and TSV columns" {
  let ids = @payoff.select_bench_case_ids("default")
  let mut found = false
  let mut pair = false
  for id in ids {
    if id == "select_status_heavy" {
      found = true
    }
    if id == "select_4v4_tl2" {
      pair = true
    }
  }
  assert_true(found)
  assert_true(pair)
  let full = @payoff.select_bench_case_ids("full")
  assert_true(full.length() > ids.length())
  let row = @payoff.run_select_bench_case("nash_rps_3", repeats=1)
  let tsv = @payoff.format_select_bench_tsv([row])
  assert_true(tsv.contains("dp_nodes"))
  assert_true(tsv.contains("dp_lp"))
  assert_true(tsv.contains("screen_lp"))
  assert_true(tsv.contains("nash_rps_3"))
}

///|
test "status cell expands more DP nodes than the stripped pair" {
  let (v1, n1, lp1) = @payoff.profile_status_cell(true)
  let (v2, n2, lp2) = @payoff.profile_status_cell(true)
  assert_true(v1 == v2)
  assert_eq(n1, n2)
  assert_eq(lp1, lp2)
  assert_true(n1 > 0)
  let (_v_plain, n_plain, _lp_plain) = @payoff.profile_status_cell(false)
  assert_true(n1 > n_plain)
  assert_true(!@payoff.dp_profile_enabled.val)
}

///|
test "parse_vm_hwm_kb reads Linux VmHWM and misses cleanly" {
  assert_eq(
    @payoff.parse_vm_hwm_kb("Name:\tfoo\nVmHWM:\t12345 kB\nVmRSS:\t9 kB\n"),
    12345,
  )
  assert_eq(@payoff.parse_vm_hwm_kb("Name:\tfoo\n"), -1)
}

///|
test "select-bench rejects an unknown case" {
  try @payoff.run_select_bench_case("not-a-case") catch {
    InvalidJson(_) => ()
    _ => fail("expected InvalidJson")
  } noraise {
    _ => fail("expected InvalidJson, solver returned")
  }
}
