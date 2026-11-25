///|
fn dt_mon(
  name : String,
  type1 : String,
  hp : Int,
  atk : Int,
  def_ : Int,
  spa : Int,
  spd : Int,
  spe : Int,
  mv : @model.Move,
) -> Combatant {
  mk_combatant(mk_pokemon(name, type1, "", hp, atk, def_, spa, spd, spe), [mv])
}

///|
fn dt_status(name : String, spe : Int, hp : Int) -> Combatant {
  dt_mon(
    name,
    "ノーマル",
    hp,
    50,
    80,
    50,
    80,
    spe,
    mk_move("まもる", "ノーマル", @model.Status, 0),
  )
}

///|
test "double move mean applies the spread modifier" {
  let eq = mk_move("じしん", "じめん", @model.Physical, 100)
  let outrage = mk_move("げきりん", "ドラゴン", @model.Physical, 120)
  let atk = dt_mon("Atk", "じめん", 200, 180, 100, 80, 90, 100, eq)
  let def = dt_mon("Def", "ノーマル", 180, 100, 110, 80, 90, 80, eq)
  let spread = double_move_mean(atk, def, eq)
  let single = compute_mean_damage(atk, def, eq, 0, 0)
  assert_true(spread > 0 && single > spread)
  let ratio = spread.to_double() / single.to_double()
  assert_true(ratio > 0.70 && ratio < 0.80)
  let out_atk = dt_mon("Out", "ドラゴン", 200, 180, 100, 80, 90, 100, outrage)
  assert_true(
    double_move_mean(out_atk, def, outrage) ==
    compute_mean_damage(out_atk, def, outrage, 0, 0),
  )
}

///|
test "earthquake hits the ally for the doubles mean" {
  let eq = mk_move("じしん", "じめん", @model.Physical, 100)
  let user = dt_mon("User", "じめん", 300, 160, 100, 70, 90, 200, eq)
  let ally = dt_status("Ally", 40, 300)
  let foe_l = dt_status("FoeL", 30, 300)
  let foe_r = dt_status("FoeR", 20, 300)
  let bench = dt_status("Bench", 10, 300)
  let my = [user, ally, bench, bench]
  let opp = [foe_l, foe_r, bench, bench]
  let targets = [[4], [7], [7], [7]]
  let mean = double_move_mean(user, ally, eq)
  let (_, my_hp, opp_hp) = scripted_value_and_hp(
    new_double_eval(),
    my,
    opp,
    targets,
    targets,
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
  )
  assert_true(my_hp[0] == 300)
  assert_true(my_hp[1] == 300 - mean)
  assert_true(opp_hp[0] == 300 - double_move_mean(user, foe_l, eq))
}

///|
test "a pokemon koed earlier does not act" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 200)
  let back = mk_move("たいあたり", "ノーマル", @model.Physical, 120)
  let attacker = dt_mon("Fast", "ノーマル", 400, 200, 100, 80, 80, 200, hit)
  let ally = dt_status("Ally", 15, 200)
  let victim = dt_mon("Slow", "ノーマル", 30, 180, 40, 80, 40, 40, back)
  let other = dt_status("Other", 10, 200)
  let my = [attacker, ally, other, other]
  let opp = [victim, other, other, other]
  let targets = [[0], [7], [7], [7]]
  let (_, my_hp, opp_hp) = scripted_value_and_hp(
    new_double_eval(),
    my,
    opp,
    targets,
    targets,
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(opp_hp[0] == 0)
  assert_true(my_hp[0] == 400)
}

///|
test "fainted chosen foe redirects to the other living foe" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 200)
  let fast = dt_mon("Fast", "ノーマル", 200, 200, 100, 80, 80, 180, hit)
  let slow = dt_mon("Slow", "ノーマル", 200, 140, 100, 80, 80, 90, hit)
  let dead = dt_mon("Dead", "ノーマル", 1, 40, 40, 40, 40, 20, hit)
  let living = dt_status("Live", 10, 400)
  let my = [fast, slow, living, living]
  let opp = [dead, living, living, living]
  let targets = [[0], [0], [7], [7]]
  let before = double_move_mean(slow, living, hit)
  let (_, _, opp_hp) = scripted_value_and_hp(
    new_double_eval(),
    my,
    opp,
    targets,
    targets,
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    None,
    None,
  )
  assert_true(opp_hp[0] == 0)
  assert_true(before > 0)
  assert_true(opp_hp[1] == 400 - before)
}

///|
test "same speed ohko orders average to zero" {
  let hit = mk_move("たいあたり", "ノーマル", @model.Physical, 250)
  let me = dt_mon("Me", "ノーマル", 100, 220, 40, 40, 40, 100, hit)
  let opp = dt_mon("Opp", "ノーマル", 100, 220, 40, 40, 40, 100, hit)
  let pad = dt_status("Pad", 10, 100)
  let mine = [me, pad, pad, pad]
  let theirs = [opp, pad, pad, pad]
  let targets = [[0], [7], [7], [7]]
  let (v, _, _) = scripted_value_and_hp(
    new_double_eval(),
    mine,
    theirs,
    targets,
    targets,
    Some(@doubles.UseOn(0, @doubles.FoeLeft)),
    None,
    Some(@doubles.UseOn(0, @doubles.MyLeft)),
    None,
  )
  assert_true(v == 0.0)
}

///|
test "small double joint nash values the forced ko" {
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
  let (switched, _, _) = scripted_value_and_hp(
    cache,
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.BenchTo(0)),
    Some(@doubles.BenchTo(1)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
  )
  let (attacked, _, _) = scripted_value_and_hp(
    cache,
    my,
    opp,
    my_t,
    opp_t,
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
    Some(@doubles.Use(0)),
  )
  assert_true(switched == 0.0)
  assert_true(attacked == 0.25)
  let v = joint_matrix_value(
    cache, my, opp, my_t, opp_t, NashSolverConfig::default(),
  )
  assert_true(v == 0.25)
}

///|
test "double select is a 90 by 90 bring matrix" {
  let mut mons = ""
  for i in 0..<6 {
    if i > 0 {
      mons = mons + ","
    }
    mons = mons +
      "{\"name\":\"P" +
      i.to_string() +
      "\",\"type1\":\"ノーマル\",\"type2\":\"\",\"hp\":120,\"atk\":80,\"def\":80," +
      "\"spa\":80,\"spd\":80,\"spe\":" +
      (40 + i).to_string() +
      ",\"ability\":\"\",\"item\":\"\",\"tera\":\"\"," +
      "\"moves\":[{\"name\":\"まもる\",\"type\":\"ノーマル\",\"category\":\"変化\",\"power\":0,\"target\":7}]}"
  }
  let input = "{\"team\":[" +
    mons +
    "],\"opponent\":[" +
    mons +
    "],\"format\":\"double\",\"team_payoff_model\":\"double_turn\"}"
  let out = run_select(input)
  let parsed = @json.parse(out)
  match parsed {
    Object(obj) => {
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
      match obj.get("selection_names") {
        Some(Array(rows)) =>
          match rows[0] {
            Array(names) => assert_true(names.length() == 4)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
      match obj.get("selection_roles") {
        Some(Array(roles)) => assert_true(roles.length() == 4)
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
      match obj.get("value") {
        Some(Number(v, ..)) => assert_true(v == 0.0)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "singles cache key stays is_double false" {
  let mv = mk_move("じしん", "じめん", @model.Physical, 100)
  let atk = dt_mon("Atk", "じめん", 180, 150, 100, 80, 80, 100, mv)
  let def = dt_mon("Def", "ノーマル", 180, 100, 110, 70, 90, 80, mv)
  let key = combatant_to_cache_key_input(atk, def, mv, 0, 0)
  assert_true(key.is_double == false)
  let flipped = { ..key, is_double: true }
  match (
    @damage_cache.build_cache_key(key),
    @damage_cache.build_cache_key(flipped),
  ) {
    (Ok(single), Ok(double)) => assert_true(single != double)
    _ => assert_true(false)
  }
}

///|
test "double_turn on format single is rejected" {
  let errored = try {
    let _ = run_select(
      "{\"team\":[],\"opponent\":[],\"format\":\"single\",\"team_payoff_model\":\"double_turn\"}",
    )
    false
  } catch {
    _ => true
  }
  assert_true(errored)
}

///|
fn read_double_example() -> String {
  match @db.read_file("tests/fixtures/nash_select_input_double_6v6.json") {
    Some(s) => s
    None =>
      match @db.read_file("../../tests/fixtures/nash_select_input_double_6v6.json") {
        Some(s) => s
        None => ""
      }
  }
}

///|
test "double example 6v6 spread select returns a 90 strategy" {
  let input = read_double_example()
  assert_true(input.length() > 0)
  let out = run_select(input)
  let parsed = @json.parse(out)
  match parsed {
    Object(obj) => {
      match obj.get("row_strategy") {
        Some(Array(ps)) => assert_true(ps.length() == 90)
        _ => assert_true(false)
      }
      match obj.get("format") {
        Some(String(s)) => assert_true(s == "double")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}
