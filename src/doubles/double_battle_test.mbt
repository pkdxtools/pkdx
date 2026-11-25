///|
/// 段階 0 の列挙と範囲。ダメージ計算と Nash は呼ばない。

///|
fn full_field() -> @doubles.DoubleField {
  @doubles.DoubleField::{
    my_left: Alive,
    my_right: Alive,
    foe_left: Alive,
    foe_right: Alive,
  }
}

///|
fn bring_key(b : @doubles.DoubleBring) -> String {
  let (l, r) = b.leads
  let (a, c) = b.bench
  l.to_string() +
  "," +
  r.to_string() +
  "/" +
  a.to_string() +
  "," +
  c.to_string()
}

///|
fn bring_ok(b : @doubles.DoubleBring, n : Int, ordered : Bool) -> Bool {
  let (l, r) = b.leads
  let (a, c) = b.bench
  if l < 0 || r < 0 || a < 0 || c < 0 {
    return false
  }
  if l >= n || r >= n || a >= n || c >= n {
    return false
  }
  if l == r || a == c || l == a || l == c || r == a || r == c {
    return false
  }
  if a >= c {
    return false
  }
  if !ordered && l >= r {
    return false
  }
  true
}

///|
fn remember(seen : Map[String, Int], key : String) -> Bool {
  match seen.get(key) {
    Some(_) => false
    None => {
      seen[key] = 1
      true
    }
  }
}

///|
test "double brings: 6 pokemon is 90 unordered and 180 ordered" {
  let brings = @doubles.double_brings(6)
  let ordered = @doubles.double_brings_ordered(6)
  @debug.debug_inspect(brings.length(), content="90")
  @debug.debug_inspect(ordered.length(), content="180")
  let seen : Map[String, Int] = Map([])
  for b in brings {
    assert_true(bring_ok(b, 6, false))
    assert_true(remember(seen, bring_key(b)))
  }
  let seen_ordered : Map[String, Int] = Map([])
  for b in ordered {
    assert_true(bring_ok(b, 6, true))
    assert_true(remember(seen_ordered, bring_key(b)))
    let (l, r) = b.leads
    let (a, c) = b.bench
    let canon = if l < r {
      @doubles.DoubleBring::{ leads: (l, r), bench: (a, c) }
    } else {
      @doubles.DoubleBring::{ leads: (r, l), bench: (a, c) }
    }
    assert_true(remember(seen, bring_key(canon)) == false)
  }
  @debug.debug_inspect(brings[0], content="{ leads: (0, 1), bench: (2, 3) }")
  @debug.debug_inspect(brings[89], content="{ leads: (4, 5), bench: (2, 3) }")
  @debug.debug_inspect(ordered[0], content="{ leads: (0, 1), bench: (2, 3) }")
  @debug.debug_inspect(ordered[6], content="{ leads: (0, 2), bench: (1, 3) }")
  // 同じ先発集合の左右入れ替えが、区別する側に両方ある。
  let swapped = @doubles.DoubleBring::{ leads: (1, 0), bench: (2, 3) }
  assert_true(remember(seen_ordered, bring_key(swapped)) == false)
}

///|
test "double brings: fewer than 4 pokemon is empty" {
  @debug.debug_inspect(@doubles.double_brings(3).length(), content="0")
  @debug.debug_inspect(@doubles.double_brings_ordered(3).length(), content="0")
  @debug.debug_inspect(@doubles.double_brings(0).length(), content="0")
  @debug.debug_inspect(@doubles.double_brings(-1).length(), content="0")
}

///|
fn struck_eq(got : @doubles.DoubleResolved, slots : Array[@doubles.DoubleSlot]) -> Bool {
  match got {
    Struck(xs) => xs == slots
    _ => false
  }
}

///|
test "target 4 strikes the ally and target 5 does not" {
  let field = full_field()
  let quake = @doubles.double_slots_hit(89, 4, MyLeft, None, field, false)
  let slide = @doubles.double_slots_hit(157, 5, MyLeft, None, field, false)
  assert_true(struck_eq(quake, [MyRight, FoeLeft, FoeRight]))
  assert_true(struck_eq(slide, [FoeLeft, FoeRight]))
  // 相手側から撃っても、target 4 は味方に当たり target 5 は当たらない。
  let quake_foe = @doubles.double_slots_hit(89, 4, FoeLeft, None, field, false)
  let slide_foe = @doubles.double_slots_hit(157, 5, FoeLeft, None, field, false)
  assert_true(struck_eq(quake_foe, [MyLeft, MyRight, FoeRight]))
  assert_true(struck_eq(slide_foe, [MyLeft, MyRight]))
}

///|
test "waza.json target 0 through 14 maps onto a doubles range" {
  let expect : Array[@doubles.DoubleMoveRange] = [
    ChooseFoe, ChooseSelfOrAlly, ChooseAlly, UnusedTarget, AllExceptUser,
    AllOpponents, UserAndAlly, UserOnly, AllPokemon, RageRandom, FieldWhole,
    FieldFoe, FieldAlly, DamageReflect, ChooseAdjacentAlly,
  ]
  for i in 0..<15 {
    match @doubles.double_move_range(i) {
      Some(r) => assert_true(r == expect[i])
      None => fail("target " + i.to_string() + " should map")
    }
  }
  assert_true(@doubles.double_move_range(-1) == None)
  assert_true(@doubles.double_move_range(15) == None)
  assert_true(@doubles.double_target_chooses(0))
  assert_true(@doubles.double_target_chooses(1))
  assert_true(@doubles.double_target_chooses(2))
  assert_true(!@doubles.double_target_chooses(3))
  assert_true(!@doubles.double_target_chooses(4))
  assert_true(!@doubles.double_target_chooses(5))
  assert_true(@doubles.double_target_chooses(14))
  assert_true(!@doubles.double_target_chooses(13))
}

///|
test "remaining ranges: self and ally, everyone, random foe, field, reflect" {
  let field = full_field()
  assert_true(
    struck_eq(@doubles.double_slots_hit(215, 6, MyLeft, None, field, false), [MyLeft, MyRight]),
  )
  assert_true(
    struck_eq(
      @doubles.double_slots_hit(195, 8, MyLeft, None, field, false),
      [MyLeft, MyRight, FoeLeft, FoeRight],
    ),
  )
  assert_true(
    @doubles.double_slots_hit(37, 9, MyLeft, None, field, false) ==
      RandomOne([FoeLeft, FoeRight]),
  )
  assert_true(@doubles.double_slots_hit(114, 10, MyLeft, None, field, false) == Battlefield(FieldWhole))
  assert_true(@doubles.double_slots_hit(191, 11, MyLeft, None, field, false) == Battlefield(FieldFoe))
  assert_true(@doubles.double_slots_hit(68, 13, MyLeft, None, field, false) == Battlefield(DamageReflect))
  assert_true(@doubles.double_slots_hit(0, 3, MyLeft, None, field, false) == NoStrike)
  let faint_ally = @doubles.DoubleField::{
    my_left: Alive,
    my_right: Fainted,
    foe_left: Alive,
    foe_right: Vacant,
  }
  assert_true(struck_eq(@doubles.double_slots_hit(215, 6, MyLeft, None, faint_ally, false), [MyLeft]))
  assert_true(
    @doubles.double_slots_hit(37, 9, MyLeft, None, faint_ally, false) == RandomOne([FoeLeft]),
  )
}

///|
test "representative move ranges: じしん いわなだれ てだすけ まもる ワイドガード ワイドフォース" {
  // champout 50e7233 の waza.json（available = 1）。
  // じしん 89 → 4、いわなだれ 157 → 5、てだすけ 270 → 2、
  // まもる 182 → 7、ワイドガード 469 → 12、ワイドフォース 797 → 0。
  let field = full_field()
  assert_true(@doubles.double_move_range(4) == Some(AllExceptUser))
  assert_true(@doubles.double_move_range(5) == Some(AllOpponents))
  assert_true(@doubles.double_move_range(2) == Some(ChooseAlly))
  assert_true(@doubles.double_move_range(7) == Some(UserOnly))
  assert_true(@doubles.double_move_range(12) == Some(FieldAlly))
  assert_true(@doubles.double_move_range(0) == Some(ChooseFoe))
  assert_true(
    struck_eq(
      @doubles.double_slots_hit(89, 4, MyLeft, None, field, false, name="じしん"),
      [MyRight, FoeLeft, FoeRight],
    ),
  )
  assert_true(
    struck_eq(
      @doubles.double_slots_hit(157, 5, MyLeft, None, field, false, name="いわなだれ"),
      [FoeLeft, FoeRight],
    ),
  )
  assert_true(
    struck_eq(
      @doubles.double_slots_hit(
        270, 2, MyLeft, Some(MyRight), field, false, name="てだすけ",
      ),
      [MyRight],
    ),
  )
  assert_true(
    @doubles.double_slots_hit(270, 2, MyLeft, Some(MyLeft), field, false, name="てだすけ") ==
      NoStrike,
  )
  assert_true(
    struck_eq(
      @doubles.double_slots_hit(182, 7, MyLeft, None, field, false, name="まもる"),
      [MyLeft],
    ),
  )
  assert_true(
    @doubles.double_slots_hit(469, 12, MyLeft, None, field, false, name="ワイドガード") ==
      Battlefield(FieldAlly),
  )
  assert_true(
    struck_eq(
      @doubles.double_slots_hit(
        @doubles.EXPANDING_FORCE_MOVE_ID, 0, MyLeft, Some(FoeRight), field, false,
        name=@doubles.EXPANDING_FORCE_NAME,
      ),
      [FoeRight],
    ),
  )
  assert_true(
    struck_eq(
      @doubles.double_slots_hit(
        @doubles.EXPANDING_FORCE_MOVE_ID, 0, MyLeft, Some(FoeRight), field, true,
        name=@doubles.EXPANDING_FORCE_NAME,
      ),
      [FoeLeft, FoeRight],
    ),
  )
  // 名前だけでも同じ例外。id が 797 でない単体技はサイコフィールドでも単体。
  assert_true(
    struck_eq(
      @doubles.double_slots_hit(
        0, 0, MyLeft, None, field, true,
        name=@doubles.EXPANDING_FORCE_NAME,
      ),
      [FoeLeft, FoeRight],
    ),
  )
  assert_true(
    struck_eq(
      @doubles.double_slots_hit(1, 0, MyLeft, Some(FoeLeft), field, true, name="はたく"),
      [FoeLeft],
    ),
  )
}

///|
fn protect() -> @doubles.DoubleMoveSpec {
  @doubles.DoubleMoveSpec::{ id: 182, name: "まもる", target: 7 }
}

///|
fn active(moves : Array[@doubles.DoubleMoveSpec]) -> @doubles.DoubleActive {
  @doubles.DoubleActive::{ occupant: Alive, moves }
}

///|
fn idle(occ : @doubles.DoubleOccupant) -> @doubles.DoubleActive {
  @doubles.DoubleActive::{ occupant: occ, moves: [] }
}

///|
fn joint_has(
  acts : Array[@doubles.DoubleJointAction],
  left : @doubles.DoubleAction?,
  right : @doubles.DoubleAction?,
) -> Bool {
  let mut found = false
  for a in acts {
    if a.left == left && a.right == right {
      found = true
    }
  }
  found
}

///|
test "joint actions drop two switches into the same bench slot" {
  let bench : Array[@doubles.DoubleOccupant] = [Alive, Alive]
  let acts = @doubles.double_joint_actions(
    active([protect()]),
    active([protect()]),
    bench,
    Alive,
    Alive,
    false,
  )
  @debug.debug_inspect(acts.length(), content="7")
  assert_true(joint_has(acts, Some(Use(0)), Some(Use(0))))
  assert_true(joint_has(acts, Some(Use(0)), Some(BenchTo(0))))
  assert_true(joint_has(acts, Some(Use(0)), Some(BenchTo(1))))
  assert_true(joint_has(acts, Some(BenchTo(0)), Some(Use(0))))
  assert_true(joint_has(acts, Some(BenchTo(0)), Some(BenchTo(1))))
  assert_true(joint_has(acts, Some(BenchTo(1)), Some(Use(0))))
  assert_true(joint_has(acts, Some(BenchTo(1)), Some(BenchTo(0))))
  assert_true(!joint_has(acts, Some(BenchTo(0)), Some(BenchTo(0))))
  assert_true(!joint_has(acts, Some(BenchTo(1)), Some(BenchTo(1))))
  // 生きている控えが 1 体なら、両方交代は残らない。
  let one : Array[@doubles.DoubleOccupant] = [Alive, Fainted, Vacant]
  let fewer = @doubles.double_joint_actions(
    active([protect()]),
    active([protect()]),
    one,
    Alive,
    Alive,
    false,
  )
  @debug.debug_inspect(fewer.length(), content="3")
  assert_true(!joint_has(fewer, Some(BenchTo(0)), Some(BenchTo(0))))
  assert_true(joint_has(fewer, Some(BenchTo(0)), Some(Use(0))))
  assert_true(joint_has(fewer, Some(Use(0)), Some(BenchTo(0))))
}

///|
test "only targets 0, 1, 2, and 14 choose a slot" {
  let moves = [
    @doubles.DoubleMoveSpec::{ id: 1, name: "はたく", target: 0 },
    @doubles.DoubleMoveSpec::{ id: 208, name: "ミルクのみ", target: 1 },
    @doubles.DoubleMoveSpec::{ id: 270, name: "てだすけ", target: 2 },
    @doubles.DoubleMoveSpec::{ id: 811, name: "コーチング", target: 14 },
  ]
  let acts = @doubles.double_joint_actions(
    active(moves),
    idle(Fainted),
    [],
    Alive,
    Alive,
    false,
  )
  // 0: 相手 2 体。1: 自分と味方は味方がひんしなので自分だけ。2 と 14 は味方待ちで出ない。
  @debug.debug_inspect(acts.length(), content="3")
  assert_true(joint_has(acts, Some(UseOn(0, FoeLeft)), None))
  assert_true(joint_has(acts, Some(UseOn(0, FoeRight)), None))
  assert_true(joint_has(acts, Some(UseOn(1, MyLeft)), None))
  let both = @doubles.double_joint_actions(
    active(moves),
    active([protect()]),
    [],
    Alive,
    Fainted,
    false,
  )
  // 左: 相手は左だけ、自分、味方、てだすけ、コーチング。右: まもる。5。
  @debug.debug_inspect(both.length(), content="5")
  assert_true(joint_has(both, Some(UseOn(0, FoeLeft)), Some(Use(0))))
  assert_true(!joint_has(both, Some(UseOn(0, FoeRight)), Some(Use(0))))
  assert_true(joint_has(both, Some(UseOn(1, MyLeft)), Some(Use(0))))
  assert_true(joint_has(both, Some(UseOn(1, MyRight)), Some(Use(0))))
  assert_true(joint_has(both, Some(UseOn(2, MyRight)), Some(Use(0))))
  assert_true(joint_has(both, Some(UseOn(3, MyRight)), Some(Use(0))))
}

///|
test "fainted and vacant slots do not act and are not struck" {
  let field = @doubles.DoubleField::{
    my_left: Alive,
    my_right: Fainted,
    foe_left: Vacant,
    foe_right: Alive,
  }
  assert_true(
    struck_eq(@doubles.double_slots_hit(89, 4, MyLeft, None, field, false), [FoeRight]),
  )
  assert_true(
    struck_eq(@doubles.double_slots_hit(157, 5, MyLeft, None, field, false), [FoeRight]),
  )
  assert_true(
    @doubles.double_slots_hit(270, 2, MyLeft, Some(MyRight), field, false) == NoStrike,
  )
  let acts = @doubles.double_joint_actions(
    active([protect()]),
    idle(Fainted),
    [Vacant, Fainted],
    Vacant,
    Alive,
    false,
  )
  @debug.debug_inspect(acts.length(), content="1")
  assert_true(joint_has(acts, Some(Use(0)), None))
  let none = @doubles.double_joint_actions(
    idle(Vacant),
    idle(Fainted),
    [Alive],
    Alive,
    Alive,
    false,
  )
  @debug.debug_inspect(none.length(), content="0")
  // 味方がひんしで、てだすけしか無い。交代先も無いので同時行動は空。
  let stuck = @doubles.double_joint_actions(
    active([@doubles.DoubleMoveSpec::{ id: 270, name: "てだすけ", target: 2 }]),
    idle(Fainted),
    [],
    Alive,
    Alive,
    false,
  )
  @debug.debug_inspect(stuck.length(), content="0")
}

///|
test "expanding force under psychic terrain does not choose a target" {
  let wide = @doubles.DoubleMoveSpec::{
    id: @doubles.EXPANDING_FORCE_MOVE_ID,
    name: @doubles.EXPANDING_FORCE_NAME,
    target: 0,
  }
  let normal = @doubles.double_joint_actions(
    active([wide]),
    idle(Vacant),
    [],
    Alive,
    Alive,
    false,
  )
  @debug.debug_inspect(normal.length(), content="2")
  assert_true(joint_has(normal, Some(UseOn(0, FoeLeft)), None))
  assert_true(joint_has(normal, Some(UseOn(0, FoeRight)), None))
  let spread = @doubles.double_joint_actions(
    active([wide]),
    idle(Vacant),
    [],
    Alive,
    Alive,
    true,
  )
  @debug.debug_inspect(spread.length(), content="1")
  assert_true(joint_has(spread, Some(Use(0)), None))
}

///|
test "move target table keeps waza target off model.Move" {
  let rows = [
    ["じしん", "4"],
    ["いわなだれ", "5"],
    ["てだすけ", "2"],
    ["まもる", "7"],
    ["ワイドガード", "12"],
    ["ワイドフォース", "0"],
    ["壊れた行"],
    ["不明", "x"],
  ]
  let table = @doubles.move_target_table_from_rows(rows)
  assert_true(table.get("じしん") == Some(4))
  assert_true(table.get("いわなだれ") == Some(5))
  assert_true(table.get("てだすけ") == Some(2))
  assert_true(table.get("まもる") == Some(7))
  assert_true(table.get("ワイドガード") == Some(12))
  assert_true(table.get("ワイドフォース") == Some(0))
  assert_true(table.get("不明") == None)
  assert_true(table.get("壊れた行") == None)
  let path = "pkdx_double_target_test.db"
  let _ = @db.unlink_file(path)
  let db = match @db.open_rwc(path) {
    Ok(d) => d
    Err(e) => fail("open_rwc failed: " + e)
  }
  let created = @db.exec(
    db,
    "CREATE TABLE move (waza TEXT PRIMARY KEY, target INTEGER NOT NULL)",
  )
  match created {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      fail("create move failed: " + e)
    }
  }
  let inserted = @db.exec(
    db,
    "INSERT INTO move (waza, target) VALUES ('じしん', 4), ('いわなだれ', 5), ('てだすけ', 2), ('まもる', 7), ('ワイドガード', 12), ('ワイドフォース', 0)",
  )
  match inserted {
    Ok(_) => ()
    Err(e) => {
      @db.close(db)
      let _ = @db.unlink_file(path)
      fail("insert move failed: " + e)
    }
  }
  let loaded = match @doubles.load_move_target_table(db) {
    Ok(t) => t
    Err(e) => {
      @db.close(db)
      let _ = @db.unlink_file(path)
      fail("@doubles.load_move_target_table failed: " + e)
    }
  }
  @db.close(db)
  let _ = @db.unlink_file(path)
  assert_true(loaded.get("じしん") == Some(4))
  assert_true(loaded.get("いわなだれ") == Some(5))
  assert_true(loaded.get("てだすけ") == Some(2))
  assert_true(loaded.get("まもる") == Some(7))
  assert_true(loaded.get("ワイドガード") == Some(12))
  assert_true(loaded.get("ワイドフォース") == Some(0))
  match loaded.get("じしん") {
    Some(code) => assert_true(@doubles.double_move_range(code) == Some(AllExceptUser))
    None => fail("じしん missing from loaded table")
  }
  match loaded.get("ワイドフォース") {
    Some(code) => assert_true(@doubles.double_move_range(code) == Some(ChooseFoe))
    None => fail("ワイドフォース missing from loaded table")
  }
}
