///|
fn dr_pair(
  name : String,
  hp : Int,
  atk : Int,
  spe : Int,
  moves : Array[@model.Move],
) -> Combatant {
  mk_combatant(mk_pokemon(name, "ノーマル", "", hp, atk, 80, 80, 80, spe), moves)
}

///|
fn dr_status_move() -> @model.Move {
  mk_move("まもる", "ノーマル", @model.Status, 0)
}

///|
fn dr_all_use() -> @doubles.DoubleAction? {
  Some(@doubles.Use(0))
}

///|
test "double rollout turn_limit 1 matches the one-turn joint value" {
  let wave = mk_move("なみのり", "みず", @model.Special, 120)
  let l = dt_mon("L", "みず", 200, 80, 80, 180, 80, 150, wave)
  let r = dt_mon("R", "みず", 200, 80, 80, 170, 80, 140, wave)
  let bench = dt_status("B", 20, 200)
  let foe = dt_status("F", 40, 1)
  let foe2 = dt_status("G", 30, 1)
  let ob = dt_status("OB", 15, 200)
  let my = [l, r, bench, bench]
  let opp = [foe, foe2, ob, ob]
  let my_t = [[5], [5], [7], [7]]
  let opp_t = [[7], [7], [7], [7]]
  let cache = new_double_eval()
  let exact = joint_matrix_value(
    cache, my, opp, my_t, opp_t, NashSolverConfig::default(),
  )
  let rolled = double_joint_rollout_value(
    cache,
    my,
    opp,
    my_t,
    opp_t,
    NashSolverConfig::default(),
    seeded_rng(9UL),
    4,
    1,
    1.0,
  )
  assert_true(exact == 0.25)
  assert_true(rolled == exact)
}

///|
test "a fainted foe is replaced and attacks on the next rollout turn" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 200)
  let fast = dt_mon("Fast", "ノーマル", 80, 300, 80, 80, 80, 130, hit)
  let ally = dt_status("Ally", 40, 200)
  let pad = dt_status("Pad", 11, 200)
  let frail = dt_status("Frail", 15, 20)
  let wall = dt_status("Wall", 25, 400)
  let revenge = dt_mon("Rev", "ノーマル", 200, 400, 80, 80, 80, 220, hit)
  let other = dt_status("Other", 8, 200)
  let my = [fast, ally, pad, pad]
  let opp = [frail, wall, revenge, other]
  let my_t = [[0], [7], [7], [7]]
  let opp_t = [[7], [7], [0], [7]]
  let cache = new_double_eval()
  let (v1, _, _) = scripted_value_and_hp(
    cache,
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    dr_all_use(),
    dr_all_use(),
    dr_all_use(),
  )
  fn rolled(seed : UInt64) -> Double {
    double_scripted_rollout(
      cache,
      my,
      opp,
      my_t,
      opp_t,
      Some(@doubles.UseOn(0, @doubles.FoeLeft)),
      dr_all_use(),
      dr_all_use(),
      dr_all_use(),
      seeded_rng(seed),
      1,
      2,
      0.0,
    )
  }
  let v2 = rolled(1UL)
  assert_true(v1 > 0.05)
  assert_true(v2 < v1)
  assert_true(rolled(1UL) == v2)
  assert_true(rolled(99UL) == v2)
}

///|
test "a voluntary switch does not attack until the following rollout turn" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 200)
  let attacker = dt_mon("Atk", "ノーマル", 200, 300, 80, 80, 80, 150, hit)
  let my = [
    dt_status("L", 50, 200),
    dt_status("R", 45, 200),
    attacker,
    dt_status("B", 9, 200),
  ]
  let opp = [
    dt_status("FL", 20, 40),
    dt_status("FR", 18, 400),
    dt_status("OB0", 12, 200),
    dt_status("OB1", 10, 200),
  ]
  let my_t = [[7], [7], [0], [7]]
  let opp_t = [[7], [7], [7], [7]]
  let cache = new_double_eval()
  fn value_at(turns : Int) -> Double {
    double_scripted_rollout(
      cache,
      my,
      opp,
      my_t,
      opp_t,
      dr_all_use(),
      dr_all_use(),
      dr_all_use(),
      dr_all_use(),
      seeded_rng(4UL),
      1,
      turns,
      0.0,
    )
  }
  let v1 = value_at(1)
  let v2 = value_at(2)
  let v3 = value_at(3)
  assert_true(v1 == 0.0)
  assert_true(v2 == v1)
  assert_true(v3 > v2)
}

///|
test "a move aimed at a foe koed earlier redirects during the rollout" {
  let status = dr_status_move()
  let big = mk_move("たいあたり", "ノーマル", @model.Physical, 200)
  let chip = mk_move("でんこうせっか", "ノーマル", @model.Physical, 40)
  let miss = mk_move("からげんき", "ノーマル", @model.Physical, 40, accuracy=0)
  let fast = dr_pair("Fast", 200, 300, 180, [status, big])
  let slow_hit = dr_pair("Slow", 200, 200, 60, [status, chip])
  let slow_miss = dr_pair("Miss", 200, 200, 60, [status, miss])
  let foe_l = dt_status("FL", 10, 15)
  let foe_r = dt_status("FR", 12, 400)
  let bench = dt_status("B", 6, 200)
  let opp = [foe_l, foe_r, bench, dt_status("B2", 5, 200)]
  let my_t = [[7, 0], [7, 0], [7], [7]]
  let opp_t = [[7], [7], [7], [7]]
  fn value_of(slow : Combatant) -> Double {
    double_scripted_rollout(
      new_double_eval(),
      [fast, slow, bench, bench],
      opp,
      my_t,
      opp_t,
      dr_all_use(),
      dr_all_use(),
      dr_all_use(),
      dr_all_use(),
      seeded_rng(2UL),
      1,
      2,
      0.0,
    )
  }
  assert_true(double_move_mean(slow_hit, foe_r, chip) > 0)
  assert_true(value_of(slow_hit) > value_of(slow_miss))
}

///|
test "rollout accuracy samples depend on the seed and repeat" {
  let status = dr_status_move()
  let shaky = mk_move("のしかかり", "ノーマル", @model.Physical, 200, accuracy=50)
  let fast = dr_pair("Fast", 200, 300, 160, [status, shaky])
  let ally = dt_status("Ally", 40, 200)
  let pad = dt_status("Pad", 9, 200)
  let frail = dt_status("Frail", 15, 30)
  let wall = dt_status("Wall", 14, 300)
  let my = [fast, ally, pad, pad]
  let opp = [frail, wall, pad, pad]
  let my_t = [[7, 0], [7], [7], [7]]
  let opp_t = [[7], [7], [7], [7]]
  fn value_of(seed : UInt64) -> Double {
    double_scripted_rollout(
      new_double_eval(),
      my,
      opp,
      my_t,
      opp_t,
      dr_all_use(),
      dr_all_use(),
      dr_all_use(),
      dr_all_use(),
      seeded_rng(seed),
      1,
      2,
      0.0,
    )
  }
  assert_true(value_of(7UL) == value_of(7UL))
  let mut lo = 2.0
  let mut hi = -2.0
  for s in 1..<21 {
    let v = value_of(s.to_uint64())
    if v < lo {
      lo = v
    }
    if v > hi {
      hi = v
    }
  }
  assert_true(hi > lo)
}

///|
test "double rollout select of four status mons is a zero matrix" {
  let mons : Array[Combatant] = []
  let targets : Array[Array[Int]] = []
  for i in 0..<4 {
    mons.push(dt_status("S" + i.to_string(), 20 + i, 100))
    targets.push([7])
  }
  let m = double_selection_matrix(
    mons,
    mons,
    targets,
    targets,
    Rollout(1, 3UL, 2),
    NashSolverConfig::default(),
  )
  assert_true(m.rows() == 6)
  assert_true(m.cols() == 6)
  assert_true(m.at(0, 0) == 0.0)
  assert_true(m.at(5, 4) == 0.0)
}

///|
test "double_rollout on format single is rejected" {
  let errored = try {
    let _ = run_select(
      "{\"team\":[],\"opponent\":[],\"format\":\"single\",\"team_payoff_model\":\"double_rollout:1:1:1\"}",
    )
    false
  } catch {
    _ => true
  }
  assert_true(errored)
}
