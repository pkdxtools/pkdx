///|
/// Single-phase timing statistics collected across repeated calls.
/// `count` is the sample size — hit and miss phases have different sample
/// sizes because only the first iteration is a miss (with a fixed key).
pub(all) struct BenchStats {
  count : Int
  median_ms : Double
  p99_ms : Double
}

///|
/// Full bench report. `full` stats cover the entire per-iteration time;
/// `lookup` isolates the cache.get call; `compute` is only populated on
/// misses and covers the user-supplied closure (which does the heavy
/// DB query + calc + format in practice).
pub(all) struct BenchReport {
  miss_count : Int
  hit_count : Int
  full_miss : BenchStats
  full_hit : BenchStats
  lookup_miss : BenchStats
  lookup_hit : BenchStats
  compute_miss : BenchStats
  put_miss : BenchStats
}

///|
/// Compute median / p99 from an unsorted array of milliseconds. Returns
/// zeros for an empty sample (avoids a panic when, e.g., miss_count == 0).
fn summarize(samples : Array[Double]) -> BenchStats {
  if samples.length() == 0 {
    return { count: 0, median_ms: 0.0, p99_ms: 0.0 }
  }
  // Copy so the caller's array is not mutated.
  let sorted : Array[Double] = []
  for i = 0; i < samples.length(); i = i + 1 {
    sorted.push(samples[i])
  }
  sorted.sort()
  let n = sorted.length()
  let median_idx = n / 2
  // p99 index: ceil(0.99 * (n-1)). For small n this collapses toward max.
  let p99_idx_raw = (n - 1) * 99 / 100
  let p99_idx = if p99_idx_raw < 0 { 0 } else { p99_idx_raw }
  { count: n, median_ms: sorted[median_idx], p99_ms: sorted[p99_idx] }
}

///|
/// Seed `count` synthetic entries in the cache to inflate the
/// `damage_cache_entries` table for load-scale measurements. Each key is
/// prefixed so we never collide with a real cache key from `build_cache_key`.
pub fn seed_dummy_entries(
  cache : DamageDiskCache,
  count : Int,
) -> Result[Unit, String] {
  let value = "{\"__bench\":true}"
  for i = 0; i < count; i = i + 1 {
    let key = "__bench_seed__|" + i.to_string()
    match put(cache, key, value) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
/// Run `iterations` iterations against the cache with `key`. Each
/// iteration: lookup → hit? emit : miss → compute → put. The `compute`
/// closure stands in for the real damage computation so the logic is
/// testable in isolation (tests pass a constant closure).
///
/// First iteration is always a miss (with a fresh / fixed key); subsequent
/// iterations are hits. So for `iterations = I`, `miss_count = 1` and
/// `hit_count = I - 1` when the cache was empty of this key on entry.
pub fn run_bench(
  cache : DamageDiskCache,
  key : String,
  iterations : Int,
  compute : () -> String,
) -> BenchReport {
  let full_miss : Array[Double] = []
  let full_hit : Array[Double] = []
  let lookup_miss : Array[Double] = []
  let lookup_hit : Array[Double] = []
  let compute_miss : Array[Double] = []
  let put_miss : Array[Double] = []
  let mut miss_count = 0
  let mut hit_count = 0
  for i = 0; i < iterations; i = i + 1 {
    let t_full_start = now_ns()
    let t_lookup_start = now_ns()
    match get(cache, key) {
      Some(_) => {
        let t_lookup = elapsed_ms(t_lookup_start)
        let t_full = elapsed_ms(t_full_start)
        lookup_hit.push(t_lookup)
        full_hit.push(t_full)
        hit_count = hit_count + 1
      }
      None => {
        let t_lookup = elapsed_ms(t_lookup_start)
        let t_compute_start = now_ns()
        let value = compute()
        let t_compute = elapsed_ms(t_compute_start)
        let t_put_start = now_ns()
        match put(cache, key, value) {
          Ok(_) => ()
          // put errors propagate as the caller sees the cache, but for
          // bench purposes we just record 0 and keep going.
          Err(_) => ()
        }
        let t_put = elapsed_ms(t_put_start)
        let t_full = elapsed_ms(t_full_start)
        lookup_miss.push(t_lookup)
        compute_miss.push(t_compute)
        put_miss.push(t_put)
        full_miss.push(t_full)
        miss_count = miss_count + 1
      }
    }
    let _ = i
  }
  {
    miss_count,
    hit_count,
    full_miss: summarize(full_miss),
    full_hit: summarize(full_hit),
    lookup_miss: summarize(lookup_miss),
    lookup_hit: summarize(lookup_hit),
    compute_miss: summarize(compute_miss),
    put_miss: summarize(put_miss),
  }
}

///|
/// Format a `BenchReport` as tab-separated lines for stderr consumption.
pub fn format_bench_report_tsv(report : BenchReport) -> String {
  let rows : Array[String] = [
    "phase\tcount\tmedian_ms\tp99_ms",
    "full_miss\t" +
    report.full_miss.count.to_string() +
    "\t" +
    report.full_miss.median_ms.to_string() +
    "\t" +
    report.full_miss.p99_ms.to_string(),
    "full_hit\t" +
    report.full_hit.count.to_string() +
    "\t" +
    report.full_hit.median_ms.to_string() +
    "\t" +
    report.full_hit.p99_ms.to_string(),
    "lookup_miss\t" +
    report.lookup_miss.count.to_string() +
    "\t" +
    report.lookup_miss.median_ms.to_string() +
    "\t" +
    report.lookup_miss.p99_ms.to_string(),
    "lookup_hit\t" +
    report.lookup_hit.count.to_string() +
    "\t" +
    report.lookup_hit.median_ms.to_string() +
    "\t" +
    report.lookup_hit.p99_ms.to_string(),
    "compute_miss\t" +
    report.compute_miss.count.to_string() +
    "\t" +
    report.compute_miss.median_ms.to_string() +
    "\t" +
    report.compute_miss.p99_ms.to_string(),
    "put_miss\t" +
    report.put_miss.count.to_string() +
    "\t" +
    report.put_miss.median_ms.to_string() +
    "\t" +
    report.put_miss.p99_ms.to_string(),
  ]
  rows.join("\n")
}
