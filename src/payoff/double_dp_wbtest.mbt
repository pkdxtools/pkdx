///|
fn dd_gap(a : Double, b : Double) -> Double {
  (a - b).abs()
}

///|
fn dd_surf(power : Int, acc : Int) -> @model.Move {
  mk_move("なみのり", "みず", @model.Special, power, accuracy=acc)
}

///|
fn dd_status_side(spe0 : Int) -> (Array[Combatant], Array[Array[Int]]) {
  let mons : Array[Combatant] = []
  let targets : Array[Array[Int]] = []
  for i in 0..<4 {
    mons.push(dt_status("S" + i.to_string(), spe0 + i * 3, 220))
    targets.push([7])
  }
  (mons, targets)
}

///|
fn dd_joints_same(
  a : Array[@doubles.DoubleJointAction],
  b : Array[@doubles.DoubleJointAction],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for x in a {
    let mut found = false
    for y in b {
      if x == y {
        found = true
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
test "double_dp opening joints match the stage-1 action set" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let l = dt_mon("L", "ノーマル", 180, 140, 90, 80, 90, 120, hit)
  let r = dt_mon("R", "ノーマル", 180, 130, 90, 80, 90, 110, hit)
  let b0 = dt_status("B0", 40, 180)
  let b1 = dt_status("B1", 30, 180)
  let my = [l, r, b0, b1]
  let targets = [[0], [0], [7], [7]]
  let cache = new_double_eval()
  let state = fresh_field(my, my)
  let mine = joints_for(cache, state, true, false, my, my, targets)
  let expect = side_joints(l, r, targets[0], targets[1])
  assert_true(dd_joints_same(mine, expect))
  let flipped : Array[@doubles.DoubleJointAction] = []
  let opp_raw = side_joints(l, r, targets[0], targets[1])
  for j in opp_raw {
    flipped.push(translate_joint(j))
  }
  let theirs = joints_for(cache, state, false, false, my, my, targets)
  assert_true(dd_joints_same(theirs, flipped))
  assert_true(mine.length() > 4)
}

///|
test "double_dp turn_limit 1 matches the one-turn joint value" {
  let surf = dd_surf(90, 100)
  let l = dt_mon("L", "みず", 200, 80, 90, 160, 90, 150, surf)
  let r = dt_mon("R", "みず", 190, 80, 90, 150, 90, 140, surf)
  let (bench, _) = dd_status_side(20)
  let my = [l, r, bench[0], bench[1]]
  let (opp, opp_t) = dd_status_side(30)
  let my_t = [[5], [5], [7], [7]]
  let cache = new_double_eval()
  let config = NashSolverConfig::default()
  let exact = joint_matrix_value(cache, my, opp, my_t, opp_t, config)
  let dp = double_dp_cell(cache, my, opp, my_t, opp_t, config, 1)
  assert_true(exact > 0.0)
  assert_true(dd_gap(exact, dp) == 0.0)
}

///|
test "double_dp selection at turn_limit 1 matches double_turn" {
  let surf = dd_surf(80, 100)
  let mons : Array[Combatant] = []
  let targets : Array[Array[Int]] = []
  for i in 0..<4 {
    mons.push(
      dt_mon(
        "P" + i.to_string(),
        "みず",
        180,
        70,
        80,
        140 + i,
        80,
        100 + i * 5,
        surf,
      ),
    )
    targets.push([5])
  }
  let config = NashSolverConfig::default()
  let dp = double_selection_matrix(mons, mons, targets, targets, Exact(1), config)
  let turn = double_selection_matrix(
    mons, mons, targets, targets, AllTargets, config,
  )
  assert_true(dp.rows() == 6 && dp.cols() == 6)
  for i in 0..<6 {
    for j in 0..<6 {
      assert_true(dp.at(i, j) == turn.at(i, j))
    }
  }
}

///|
test "double_dp two exact turns agree with a deterministic rollout" {
  let surf = dd_surf(90, 100)
  let l = dt_mon("L", "みず", 240, 70, 100, 170, 100, 160, surf)
  let r = dt_mon("R", "みず", 230, 70, 100, 155, 100, 150, surf)
  let pad = dt_status("Pad", 20, 240)
  let my = [l, r, pad, dt_status("Pad2", 18, 240)]
  let (opp, opp_t) = dd_status_side(40)
  let my_t = [[5], [5], [7], [7]]
  let cache = new_double_eval()
  let config = NashSolverConfig::default()
  let dp1 = double_dp_cell(cache, my, opp, my_t, opp_t, config, 1)
  let dp2 = double_dp_cell(
    new_double_eval(), my, opp, my_t, opp_t, config, 2,
  )
  let rolled = double_joint_rollout_value(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    config,
    seeded_rng(11UL),
    8,
    2,
    0.0,
  )
  assert_true(dp2 > dp1)
  assert_true(dd_gap(dp2, rolled) < 1.0e-6)
  let again = double_dp_cell(
    new_double_eval(), my, opp, my_t, opp_t, config, 2,
  )
  assert_true(again == dp2)
}

///|
test "double_dp keeps a dominated spread from changing the two-turn value" {
  let weak = dd_surf(40, 100)
  let strong = dd_surf(90, 100)
  fn pack(moves : Array[@model.Move]) -> Array[Combatant] {
    let lead = mk_combatant(
      mk_pokemon("Lead", "みず", "", 260, 70, 110, 180, 110, 170),
      moves,
    )
    let ally = dt_status("Ally", 80, 260)
    [lead, ally, dt_status("B0", 20, 260), dt_status("B1", 16, 260)]
  }
  let (opp, opp_t) = dd_status_side(25)
  let wide = [[5, 5], [7], [7], [7]]
  let one = [[5], [7], [7], [7]]
  let config = NashSolverConfig::default()
  let both = double_dp_cell(
    new_double_eval(), pack([weak, strong]), opp, wide, opp_t, config, 2,
  )
  let only = double_dp_cell(
    new_double_eval(), pack([strong]), opp, one, opp_t, config, 2,
  )
  let rolled = double_joint_rollout_value(
    new_double_eval(),
    pack([weak, strong]),
    opp,
    wide,
    opp_t,
    config,
    seeded_rng(3UL),
    4,
    2,
    0.0,
  )
  assert_true(dd_gap(both, only) < 1.0e-6)
  assert_true(dd_gap(both, rolled) < 1.0e-6)
}

///|
test "double_dp accuracy expectation is near a large rollout" {
  let shaky = dd_surf(120, 50)
  let l = dt_mon("L", "みず", 220, 70, 100, 180, 100, 180, shaky)
  let r = dt_status("R", 90, 220)
  let my = [l, r, dt_status("B0", 15, 220), dt_status("B1", 12, 220)]
  let (opp, opp_t) = dd_status_side(28)
  let my_t = [[5], [7], [7], [7]]
  let config = NashSolverConfig::default()
  let dp = double_dp_cell(
    new_double_eval(), my, opp, my_t, opp_t, config, 2,
  )
  let rolled = double_joint_rollout_value(
    new_double_eval(),
    my,
    opp,
    my_t,
    opp_t,
    config,
    seeded_rng(21UL),
    400,
    2,
    0.0,
  )
  assert_true(dp > 0.0)
  assert_true(dd_gap(dp, rolled) < 0.06)
}

///|
test "double_dp replaces a koed foe before the next exact turn" {
  // 先発を倒すと、次のターンの行動前に控えが出て、そのターンに技を出す。
  // 補充先の方が速いので先に削り、こちらは後から倒す。段階 2 の ε=0 と同じ線。
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 200)
  let fast = dt_mon("Fast", "ノーマル", 200, 200, 120, 70, 120, 100, hit)
  let ally = dt_status("Ally", 40, 200)
  let my = [fast, ally, dt_status("MB0", 12, 200), dt_status("MB1", 11, 200)]
  let frail = dt_status("Frail", 30, 40)
  let wall = dt_mon(
    "Wall",
    "ゴースト",
    300,
    40,
    80,
    40,
    80,
    20,
    mk_move("まもる", "ノーマル", @model.Status, 0),
  )
  let revenge = dt_mon("Rev", "ノーマル", 90, 80, 40, 40, 40, 140, hit)
  let quiet = dt_status("Quiet", 8, 200)
  let my_t = [[0], [7], [7], [7]]
  let opp_t = [[7], [7], [0], [7]]
  let config = NashSolverConfig::default()
  let with_rev = [frail, wall, revenge, quiet]
  let no_rev = [frail, wall, quiet, dt_status("Quiet2", 7, 200)]
  let dp_rev = double_dp_cell(
    new_double_eval(), my, with_rev, my_t, opp_t, config, 2,
  )
  let dp_quiet = double_dp_cell(
    new_double_eval(), my, no_rev, my_t, opp_t, config, 2,
  )
  let rolled = double_joint_rollout_value(
    new_double_eval(),
    my,
    with_rev,
    my_t,
    opp_t,
    config,
    seeded_rng(8UL),
    4,
    2,
    0.0,
  )
  assert_true(double_move_mean(fast, wall, hit) == 0)
  assert_true(double_move_mean(fast, frail, hit) > frail.pokemon.hp)
  assert_true(double_move_mean(fast, revenge, hit) > revenge.pokemon.hp)
  assert_true(double_move_mean(revenge, fast, hit) < fast.pokemon.hp)
  assert_true(dp_quiet > dp_rev)
  // 補充の Nash と段階 2 の貪欲は、犠牲交代の評価でわずかに分かれる。
  assert_true(dd_gap(dp_rev, rolled) < 0.02)
}

///|
test "double_dp line value is skew symmetric" {
  let surf = dd_surf(90, 100)
  let mine = [
    dt_mon("A", "みず", 200, 80, 90, 170, 90, 160, surf),
    dt_mon("B", "みず", 190, 80, 90, 150, 90, 120, surf),
    dt_status("C", 40, 200),
    dt_status("D", 30, 200),
  ]
  let opp = [
    dt_mon("E", "ほのお", 210, 150, 90, 80, 90, 100, mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)),
    dt_status("F", 80, 210),
    dt_status("G", 20, 210),
    dt_status("H", 18, 210),
  ]
  let my_t = [[5], [5], [7], [7]]
  let opp_t = [[5], [7], [7], [7]]
  let config = NashSolverConfig::default()
  let cache = new_double_eval()
  let v = double_dp_cell(cache, mine, opp, my_t, opp_t, config, 2)
  let (back, _, _) = double_dp_cell_stats(
    cache, opp, mine, opp_t, my_t, config, 2,
  )
  assert_true(dd_gap(v + back, 0.0) == 0.0)
}

///|
test "double_dp on format single is rejected" {
  let errored = try {
    let _ = run_select(
      "{\"team\":[],\"opponent\":[],\"format\":\"single\",\"team_payoff_model\":\"double_dp:2\"}",
    )
    false
  } catch {
    _ => true
  }
  assert_true(errored)
}

///|
fn dd_bench_side(
  label : String,
  mons : Array[Combatant],
  targets : Array[Array[Int]],
  config : NashSolverConfig,
  brings : Array[@doubles.DoubleBring],
  cell_limits : Array[Int],
) -> Unit raise NashCliError {
  let (one_my, one_tg) = take4(mons, targets, brings[0])
  for limit in cell_limits {
    let cache = new_double_eval()
    let t0 = @damage_cache.now_ns()
    let (v, nodes, hits) = double_dp_cell_stats(
      cache, one_my, one_my, one_tg, one_tg, config, limit,
    )
    let ms = (@damage_cache.now_ns() - t0).to_double() / 1_000_000.0
    println(
      label +
      " cell_tl" +
      limit.to_string() +
      "_ms=" +
      ms.to_string() +
      " value=" +
      v.to_string() +
      " nodes=" +
      nodes.to_string() +
      " hits=" +
      hits.to_string(),
    )
  }
  let row_cache = new_double_eval()
  let (row_my, row_tg) = take4(mons, targets, brings[0])
  let trow = @damage_cache.now_ns()
  for j in 0..<brings.length() {
    let (op, op_tg) = take4(mons, targets, brings[j])
    let _ = double_dp_cell(
      row_cache, row_my, op, row_tg, op_tg, config, 2,
    )
  }
  let row_ms = (@damage_cache.now_ns() - trow).to_double() / 1_000_000.0
  println(label + " row90_tl2_ms=" + row_ms.to_string())
  let started1 = @damage_cache.now_ns()
  let matrix1 = double_selection_matrix(
    mons, mons, targets, targets, Exact(1), config,
  )
  let ms1 = (@damage_cache.now_ns() - started1).to_double() / 1_000_000.0
  println(
    label +
    " matrix90_tl1_ms=" +
    ms1.to_string() +
    " rows=" +
    matrix1.rows().to_string() +
    " v00=" +
    matrix1.at(0, 0).to_string(),
  )
  // 1 行が 12 秒を超えるときは 90×90 を回さず、対称性で半分にした外挿を残す。
  // ユニークな組は (90*90+90)/2 = 4095。1 行は 90 組。
  // PKDX_DOUBLE_DP_FULL=1 のときは単体技でも全体を測る。
  let force_full = match @env.get_env_var("PKDX_DOUBLE_DP_FULL") {
    Some("1") => true
    _ => false
  }
  if row_ms <= 12000.0 || force_full {
    let started2 = @damage_cache.now_ns()
    let matrix2 = double_selection_matrix(
      mons, mons, targets, targets, Exact(2), config,
    )
    let ms2 = (@damage_cache.now_ns() - started2).to_double() / 1_000_000.0
    println(
      label +
      " matrix90_tl2_ms=" +
      ms2.to_string() +
      " rows=" +
      matrix2.rows().to_string() +
      " v00=" +
      matrix2.at(0, 0).to_string(),
    )
  } else {
    let extrapolated = row_ms * 4095.0 / 90.0
    println(
      label + " matrix90_tl2_extrapolated_ms=" + extrapolated.to_string(),
    )
  }
}

///|
fn dd_bench_spread(
  config : NashSolverConfig,
  brings : Array[@doubles.DoubleBring],
) -> Unit raise NashCliError {
  let surf = dd_surf(90, 100)
  let quake = mk_move("じしん", "じめん", @model.Physical, 100)
  let mons : Array[Combatant] = []
  let targets : Array[Array[Int]] = []
  for i in 0..<6 {
    let mv = if i % 2 == 0 { surf } else { quake }
    let code = if i % 2 == 0 { 5 } else { 4 }
    mons.push(
      dt_mon(
        "S" + i.to_string(),
        "ノーマル",
        170 + i,
        120 + i,
        90,
        130 + i,
        90,
        80 + i * 7,
        mv,
      ),
    )
    targets.push([code])
  }
  dd_bench_side("spread", mons, targets, config, brings, [1, 2, 3])
}

///|
fn dd_bench_single_target(
  config : NashSolverConfig,
  brings : Array[@doubles.DoubleBring],
) -> Unit raise NashCliError {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 80)
  let mons : Array[Combatant] = []
  let targets : Array[Array[Int]] = []
  for i in 0..<6 {
    mons.push(
      dt_mon(
        "T" + i.to_string(),
        "ノーマル",
        160 + i,
        140 + i,
        90,
        70,
        90,
        70 + i * 9,
        hit,
      ),
    )
    targets.push([0])
  }
  // 単体技の深さ 3 は 1 セルでも行動積が重すぎるので、ここでは深さ 2 まで。
  dd_bench_side("single", mons, targets, config, brings, [1, 2])
}

///|
test "double_dp bench" {
  match @env.get_env_var("PKDX_DOUBLE_DP_BENCH") {
    Some("1") => {
      let config = NashSolverConfig::default()
      let brings = @doubles.double_brings(6)
      dd_bench_spread(config, brings)
      dd_bench_single_target(config, brings)
      assert_true(true)
    }
    _ => ()
  }
}
