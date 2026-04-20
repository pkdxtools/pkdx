///|
/// Confirm the SQLite-backed L2 disk cache is actually wired in to
/// `switching_game_winrate`. Two sequential runs with the same teams but
/// separate `DamageCache` instances: the first populates L2, the second
/// should see at least one disk-hit.
test "switching_game_winrate: L2 disk cache survives across DamageCache instances" {
  let path = "/tmp/pkdx_sw_l2_test.sqlite"
  let _ = @db.unlink_file(path)
  guard
    @damage_cache.open_or_init(path, "0.4.10", "head-a") is Ok(disk) else {
    fail("open_or_init failed")
  }

  // Two simple teams with a physical move so the 16-roll reducer is
  // exercised and pre-burn means land in L2.
  let team_a = [
    mk_combatant(
      mk_pokemon("A", "ノーマル", "", 100, 150, 100, 100, 100, 120),
      [mk_move("mv", "ノーマル", @model.Physical, 80)],
    ),
  ]
  let team_b = [
    mk_combatant(
      mk_pokemon("B", "ノーマル", "", 100, 100, 100, 100, 100, 80),
      [mk_move("mv", "ノーマル", @model.Physical, 80)],
    ),
  ]

  // First run: L1 + L2 both empty → every miss populates both layers.
  let (_v1, _, dmg1) = switching_game_winrate_stats(
    team_a, team_b, 3, disk=Some(disk),
  )
  assert_true(dmg1.disk_misses > 0)
  assert_eq(dmg1.disk_hits, 0)

  // Second run: fresh L1 but L2 persists in the SQLite file → disk
  // lookups hit for the same matchups.
  let (_v2, _, dmg2) = switching_game_winrate_stats(
    team_a, team_b, 3, disk=Some(disk),
  )
  assert_true(dmg2.disk_hits > 0)

  @damage_cache.close(disk)
  let _ = @db.unlink_file(path)

}
