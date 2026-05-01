///|
/// With a fixed key and an initially empty cache, the first iteration is a
/// miss and the remaining iterations are hits.
test "run_bench: fixed-key counts — miss=1, hit=I-1" {
  let path = "pkdx_bench_runner_test_fixed.sqlite"
  let _ = @db.unlink_file(path)
  guard open_or_init(path, "0.4.10") is Ok(cache) else {
    fail("open_or_init failed")
  }
  let report = run_bench(cache, "fixed-key", 5, fn() { "{\"ok\":1}" })
  close(cache)
  let _ = @db.unlink_file(path)
  assert_eq(report.miss_count, 1)
  assert_eq(report.hit_count, 4)
  assert_eq(report.full_miss.count, 1)
  assert_eq(report.full_hit.count, 4)
}

///|
/// seed_dummy_entries populates the requested number of rows.
test "run_bench: seed_dummy_entries inserts N rows" {
  let path = "pkdx_bench_runner_test_seed.sqlite"
  let _ = @db.unlink_file(path)
  guard open_or_init(path, "0.4.10") is Ok(cache) else {
    fail("open_or_init failed")
  }
  guard seed_dummy_entries(cache, 50) is Ok(_) else {
    fail("seed_dummy_entries failed")
  }
  // Every seeded key should be fetchable.
  let v = get(cache, "__bench_seed__|0")
  close(cache)
  let _ = @db.unlink_file(path)
  match v {
    Some(_) => ()
    None => fail("seed entry not found")
  }
}

///|
/// format_bench_report_tsv produces a header plus one row per phase.
test "run_bench: TSV formatter emits 7 lines (1 header + 6 phases)" {
  let path = "pkdx_bench_runner_test_fmt.sqlite"
  let _ = @db.unlink_file(path)
  guard open_or_init(path, "0.4.10") is Ok(cache) else {
    fail("open_or_init failed")
  }
  let report = run_bench(cache, "k", 3, fn() { "v" })
  close(cache)
  let _ = @db.unlink_file(path)
  let tsv = format_bench_report_tsv(report)
  let lines = tsv.split("\n").collect()
  assert_eq(lines.length(), 7)
}
