///|
/// #91 regression: the L2 disk-backed `mean_damage_cached` must be
/// semantically identical to the in-memory variants-weighted path for
/// multi-hit moves. Before the fix, `mean_damage_via_disk` reduced the
/// cached JSON's top-level `damages` field — which holds only the
/// most-likely variant's roll table — so Triple Axel / Random2to5 /
/// PopulationBomb collapsed to the high-hit-count branch on every L2 hit
/// even though `compute_mean_damage` had already moved to
/// `Σ probability * variant_mean`. This test exercises both the populate
/// (L1+L2 miss → write v3 JSON to disk) and the read (L1 miss + L2 hit →
/// parse variants[]) paths and asserts they agree with the disk-less
/// baseline.

///|
/// Helper: invoke `mean_damage_cached` for the simple 1v1 setup used
/// throughout this file.
fn l2v_mean(
  cache : DamageCache,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> Int {
  let zero_ranks = [0, 0, 0, 0, 0]
  mean_damage_cached(
    cache, true, 0, zero_ranks, 0, zero_ranks, 0, my_team, opp_team,
  )
}

///|
test "mean_damage_cached: L2 hit on Triple Axel returns the variants-weighted mean (#91)" {
  let path = "pkdx_sw_l2_variants_triple_test.sqlite"
  let _ = @db.unlink_file(path)
  guard @damage_cache.open_or_init(path, "0.4.10") is Ok(disk) else {
    fail("open_or_init failed")
  }

  // Triple Axel: 3 variants with probabilities {0.10, 0.09, 0.81} and
  // ramped power per landed hit. The legacy `damages` field captures only
  // the 3-hit branch, so a populate-then-read round-trip is the smallest
  // setup that surfaces the bug. Power 20 is the official base; the
  // engine ramps it across hits.
  let atk = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 200, 100, 100, 100, 120),
    [mk_move("トリプルアクセル", "こおり", @model.Physical, 20)],
  )
  let dfn = mk_combatant(
    mk_pokemon("D", "ノーマル", "", 200, 100, 100, 100, 100, 80),
    [mk_move("mv", "ノーマル", @model.Physical, 80)],
  )
  let my_team = [atk]
  let opp_team = [dfn]

  // Disk-less baseline: drives `compute_mean_damage` directly through
  // L1, which in turn reduces via `compute_damage_variants`. This is the
  // value the L2 path must match exactly.
  let baseline_cache = new_damage_cache()
  let baseline = l2v_mean(baseline_cache, my_team, opp_team)

  // Populate L2: fresh cache + disk → L1+L2 miss → `compute_and_populate_disk`
  // writes v3 JSON to the SQLite cache.
  let populate_cache = new_damage_cache(disk=Some(disk))
  let populate_value = l2v_mean(populate_cache, my_team, opp_team)
  assert_true(populate_cache.disk_misses > 0)
  @debug.assert_eq(populate_cache.disk_hits, 0)
  // Sanity: the populate path returns the same scalar — both must reduce
  // through `r.variants[]`, not `r.damages`.
  @debug.assert_eq(populate_value, baseline)

  // Read L2: brand-new in-memory cache so L1 cannot serve the lookup; the
  // SQLite file persists across DamageCache instances.
  let read_cache = new_damage_cache(disk=Some(disk))
  let read_value = l2v_mean(read_cache, my_team, opp_team)
  assert_true(read_cache.disk_hits > 0)
  // The pre-fix bug: `mean_damage_via_disk` reduced the legacy
  // `damages` field, so this would equal the 3-hit-only mean — distinct
  // from the variants-weighted baseline. Equality here is the regression
  // guard.
  @debug.assert_eq(read_value, baseline)

  @damage_cache.close(disk)
  let _ = @db.unlink_file(path)
}

///|
test "mean_damage_cached: L2 hit on Random2to5 returns the variants-weighted mean (#91)" {
  let path = "pkdx_sw_l2_variants_random_test.sqlite"
  let _ = @db.unlink_file(path)
  guard @damage_cache.open_or_init(path, "0.4.10") is Ok(disk) else {
    fail("open_or_init failed")
  }

  // Random2to5: 4 variants {2,3,4,5} with {0.375, 0.375, 0.125, 0.125}.
  // Without Skill Link the engine emits all 4; legacy `damages` is the
  // most-likely branch, which differs from the probability-weighted
  // mean over all four — a second multi-hit class beyond Triple Axel
  // covering the Random2to5 distribution.
  let atk = mk_combatant(
    mk_pokemon("A", "ノーマル", "", 100, 200, 100, 100, 100, 120),
    [mk_move("ロックブラスト", "いわ", @model.Physical, 25)],
  )
  let dfn = mk_combatant(
    mk_pokemon("D", "ノーマル", "", 200, 100, 100, 100, 100, 80),
    [mk_move("mv", "ノーマル", @model.Physical, 80)],
  )
  let my_team = [atk]
  let opp_team = [dfn]

  let baseline = l2v_mean(new_damage_cache(), my_team, opp_team)

  let populate_cache = new_damage_cache(disk=Some(disk))
  let _ = l2v_mean(populate_cache, my_team, opp_team)
  assert_true(populate_cache.disk_misses > 0)

  let read_cache = new_damage_cache(disk=Some(disk))
  let read_value = l2v_mean(read_cache, my_team, opp_team)
  assert_true(read_cache.disk_hits > 0)
  @debug.assert_eq(read_value, baseline)

  @damage_cache.close(disk)
  let _ = @db.unlink_file(path)
}

///|
/// 反射技 (カウンター / ミラーコート / メタルバースト / ほうふく) は
/// `@damage.calc_damage` を incoming=None で叩くと 0 が返るため、L2 disk
/// cache を素直に populate / read すると同じ (matchup, ranks) キーで以後
/// 永続的に 0 が読み出されてしまう (poison)。修正後は `mean_damage_via_disk`
/// が反射技を検知して disk を経由せず compute_mean_damage に丸投げするため、
/// scalar 経路でも 0 が返らない。
test "mean_damage_cached: reflect move does not poison L2 disk with zero" {
  let path = "pkdx_sw_l2_reflect_test.sqlite"
  let _ = @db.unlink_file(path)
  guard @damage_cache.open_or_init(path, "0.4.10") is Ok(disk) else {
    fail("open_or_init failed")
  }

  // Counter (Physical reflect) holder vs a pure-physical opponent. Power
  // is 1 to bypass the `mv.power <= 0` early return — mirrors the DB
  // migration that overrides reflect move power to 1.
  let counter_user = mk_combatant(
    mk_pokemon("user", "ノーマル", "", 200, 50, 100, 50, 100, 50),
    [mk_move("カウンター", "かくとう", @model.Physical, 1)],
  )
  let physical_atk = mk_combatant(
    mk_pokemon("atk", "ノーマル", "", 200, 200, 100, 50, 100, 100),
    [mk_move("たいあたり", "ノーマル", @model.Physical, 40)],
  )
  let my_team = [counter_user]
  let opp_team = [physical_atk]

  // Disk-less baseline: drives reflect_damage_outcomes directly. Non-zero
  // because the opponent has a valid physical candidate.
  let baseline = l2v_mean(new_damage_cache(), my_team, opp_team)
  assert_true(baseline > 0)

  // Disk-backed populate path: must NOT call compute_and_populate_disk
  // for reflect moves. The short-circuit in mean_damage_via_disk keeps
  // disk_misses at 0 and returns the proper variants-based value.
  let populate_cache = new_damage_cache(disk=Some(disk))
  let populate_value = l2v_mean(populate_cache, my_team, opp_team)
  @debug.assert_eq(populate_value, baseline)
  @debug.assert_eq(populate_cache.disk_misses, 0)
  @debug.assert_eq(populate_cache.disk_hits, 0)

  // Disk-backed read path: fresh in-memory cache, same SQLite file.
  // Even if a prior session somehow wrote a zero entry under this key,
  // mean_damage_via_disk now short-circuits BEFORE the disk lookup, so
  // the reflected value is always recomputed and stays non-zero.
  let read_cache = new_damage_cache(disk=Some(disk))
  let read_value = l2v_mean(read_cache, my_team, opp_team)
  @debug.assert_eq(read_value, baseline)
  @debug.assert_eq(read_cache.disk_hits, 0)
  @debug.assert_eq(read_cache.disk_misses, 0)

  @damage_cache.close(disk)
  let _ = @db.unlink_file(path)
}
