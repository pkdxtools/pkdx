///|
/// Row assignment must be a partition of `0 .. total`: every row once,
/// empty shards allowed when there are more shards than rows.
fn assert_partition(total : Int, n_shards : Int) -> Unit raise {
  let groups = assign_shard_rows(total, n_shards)
  @debug.assert_eq(groups.length(), n_shards)
  let seen = Array::make(total, false)
  let mut count = 0
  for g in groups {
    for row in g {
      if row < 0 || row >= total {
        abort("row index out of range: " + row.to_string())
      }
      if seen[row] {
        abort("duplicate row " + row.to_string())
      }
      seen[row] = true
      count = count + 1
    }
  }
  @debug.assert_eq(count, total)
}

///|
test "assign_shard_rows partitions 18 rows across 4 shards" {
  assert_partition(18, 4)
  let groups = assign_shard_rows(18, 4)
  // Remainder goes to the first shards: 5, 5, 4, 4.
  @debug.assert_eq(groups[0].length(), 5)
  @debug.assert_eq(groups[1].length(), 5)
  @debug.assert_eq(groups[2].length(), 4)
  @debug.assert_eq(groups[3].length(), 4)
  @debug.assert_eq(groups[0][0], 0)
  @debug.assert_eq(groups[3][groups[3].length() - 1], 17)
}

///|
test "assign_shard_rows partitions 60 rows across 2 and 4 shards" {
  assert_partition(60, 2)
  assert_partition(60, 4)
  let g4 = assign_shard_rows(60, 4)
  @debug.assert_eq(g4[0].length(), 15)
  @debug.assert_eq(g4[3].length(), 15)
}

///|
test "assign_shard_rows emits empty shards when parallel exceeds rows" {
  assert_partition(18, 20)
  let groups = assign_shard_rows(18, 20)
  let mut empty = 0
  let mut singletons = 0
  for g in groups {
    if g.length() == 0 {
      empty = empty + 1
    } else if g.length() == 1 {
      singletons = singletons + 1
    } else {
      abort("expected empty or singleton, got " + g.length().to_string())
    }
  }
  @debug.assert_eq(singletons, 18)
  @debug.assert_eq(empty, 2)
}

///|
test "screen row groups reproduce the full matrix bits" {
  let team = Array::make(6, mk_combatant(
    mk_pokemon("P", "ノーマル", "", 100, 90, 80, 70, 70, 80),
    [mk_move("のしかかり", "ノーマル", @model.Physical, 40)],
  ))
  for i in 0..<6 {
    team[i] = mk_combatant(
      mk_pokemon(
        "P" + i.to_string(),
        "ノーマル",
        "",
        100 + i,
        90,
        80,
        70,
        70,
        60 + i * 5,
      ),
      [mk_move("のしかかり", "ノーマル", @model.Physical, 40)],
    )
  }
  let n = combinations_with_lead(6, 3).length()
  let full = screen_phase_rows(
    team, team, Single, 4, 7UL, 0, n, mc_turn_limit=1,
  ) catch {
    e => abort(@debug.to_string(e))
  }
  let check = fn(n_shards : Int) -> Unit raise {
    let groups = assign_shard_rows(n, n_shards)
    let stitched = Array::make(n, ([] : Array[Double]))
    for g in groups {
      if g.length() == 0 {
        continue
      }
      // Compute each assigned row on its own and place it by index,
      // the same contract the parent uses after reading shard JSON.
      for row in g {
        let piece = screen_phase_rows(
          team, team, Single, 4, 7UL, row, row + 1, mc_turn_limit=1,
        ) catch {
          e => abort(@debug.to_string(e))
        }
        stitched[row] = piece[0]
      }
    }
    for i in 0..<n {
      @debug.assert_eq(stitched[i].length(), full[i].length())
      for j in 0..<full[i].length() {
        let a = stitched[i][j].reinterpret_as_uint64()
        let b = full[i][j].reinterpret_as_uint64()
        if a != b {
          abort("cell bits differ at " + i.to_string() + "," + j.to_string())
        }
      }
    }
  }
  check(4)
  check(n + 3)
}
