///|
/// 免疫の命中スキップは、技が着弾するポケモン (交代先) で判定する。
/// 出ていくポケモンが無効でも、交代先が受けるなら外れ枝が残る。
/// 残ったまま無効な相手へ撃つダメージ技は外れ枝を作らない。

///|
fn isw_jump() -> @model.Move {
  mk_move("とびひざげり", "かくとう", @model.Physical, 130, accuracy=90)
}

///|
fn isw_splash() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
fn isw_quake() -> @model.Move {
  mk_move("じしん", "じめん", @model.Physical, 100)
}

///|
fn isw_outs(
  mine : Array[Combatant],
  opp : Array[Combatant],
  my_action : ActionKind,
  opp_action : ActionKind,
) -> Array[(Double, SwitchingGameState)] {
  let st = im_state(my_hps=[200], opp_hps=[200, 200])
  attempt_turn_with_cache(st, my_action, opp_action, mine, opp, new_damage_cache())
}

///|
fn isw_near(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
fn isw_champ(
  name : String,
  t1 : String,
  t2 : String,
  ability : String,
  hp : Int,
  atk : Int,
  def_ : Int,
  spa : Int,
  spd : Int,
  spe : Int,
  moves : Array[@model.Move],
) -> Combatant {
  let p = {
    ..im_pokemon(name, hp=hp, atk=atk, def_=def_, spe=spe),
    type1: t1,
    type2: t2,
    spa,
    spd,
  }
  let c = im_combatant(p, moves, ability=ability)
  { ..c, stat_system: @model.Champions, actual_stats: None }
}

///|
test "immune accuracy: a ghost that stays in has no miss branch for jump kick" {
  let mine = [crash_mon("HJK", [isw_jump(), isw_splash()], 200, type1="かくとう", spe=120)]
  let ghost = crash_mon("Ghost", [isw_splash()], 200, type1="ゴースト", spe=100)
  let ground = crash_mon("Ground", [isw_quake()], 200, type1="じめん", spe=80)
  let outs = isw_outs(mine, [ghost, ground], UseMove(0), UseMove(0))
  @debug.assert_eq(outs.length(), 1)
  assert_true(isw_near(outs[0].0, 1.0))
  @debug.assert_eq(outs[0].1.my_hps[0], 100)
  @debug.assert_eq(outs[0].1.opp_hps[0], 200)
  @debug.assert_eq(outs[0].1.opp_active, 0)
}

///|
test "immune accuracy: jump kick into a ghost switching to ground keeps the miss" {
  let mine = [crash_mon("HJK", [isw_jump(), isw_splash()], 200, type1="かくとう", spe=120)]
  let ghost = crash_mon("Ghost", [isw_splash()], 200, type1="ゴースト", spe=100)
  let ground = crash_mon("Ground", [isw_quake()], 200, type1="じめん", spe=80)
  let outs = isw_outs(mine, [ghost, ground], UseMove(0), Switch(1))
  @debug.assert_eq(outs.length(), 2)
  let mut saw_hit = false
  let mut saw_miss = false
  for o in outs {
    let (p, s) = o
    if isw_near(p, 0.9) {
      saw_hit = true
      @debug.assert_eq(s.opp_active, 1)
      @debug.assert_eq(s.opp_hps[0], 200)
      assert_true(s.opp_hps[1] < 200)
      @debug.assert_eq(s.my_hps[0], 200)
    } else if isw_near(p, 0.1) {
      saw_miss = true
      @debug.assert_eq(s.opp_active, 1)
      @debug.assert_eq(s.opp_hps[0], 200)
      @debug.assert_eq(s.opp_hps[1], 200)
      @debug.assert_eq(s.my_hps[0], 100)
    }
  }
  assert_true(saw_hit)
  assert_true(saw_miss)
}

///|
test "immune accuracy: switching into a second ghost still has no miss branch" {
  let mine = [crash_mon("HJK", [isw_jump(), isw_splash()], 200, type1="かくとう", spe=120)]
  let ghost = crash_mon("Ghost", [isw_splash()], 200, type1="ゴースト", spe=100)
  let ghost2 = crash_mon("GhostB", [isw_splash()], 200, type1="ゴースト", spe=90)
  let outs = isw_outs(mine, [ghost, ghost2], UseMove(0), Switch(1))
  @debug.assert_eq(outs.length(), 1)
  assert_true(isw_near(outs[0].0, 1.0))
  @debug.assert_eq(outs[0].1.opp_active, 1)
  @debug.assert_eq(outs[0].1.opp_hps[1], 200)
  @debug.assert_eq(outs[0].1.my_hps[0], 100)
}

///|
test "immune accuracy: a ground lead switching to a ghost does not roll jump kick accuracy" {
  let mine = [crash_mon("HJK", [isw_jump(), isw_splash()], 200, type1="かくとう", spe=120)]
  let ground = crash_mon("Ground", [isw_quake()], 200, type1="じめん", spe=80)
  let ghost = crash_mon("Ghost", [isw_splash()], 200, type1="ゴースト", spe=100)
  let outs = isw_outs(mine, [ground, ghost], UseMove(0), Switch(1))
  @debug.assert_eq(outs.length(), 1)
  assert_true(isw_near(outs[0].0, 1.0))
  @debug.assert_eq(outs[0].1.opp_active, 1)
  @debug.assert_eq(outs[0].1.opp_hps[1], 200)
  @debug.assert_eq(outs[0].1.my_hps[0], 100)
}

///|
/// The #223 select regression on crash_reckless_6v6_t3 was this cell. The
/// ghost bench switches in and back out; jump kick must still be able to miss
/// the ground it actually hits. The value is the pre-#223 `pkdx select` cell.
test "immune accuracy: reckless HJK cell matches the pre-regression select value" {
  let hjk = isw_jump()
  let splash = isw_splash()
  let axe = mk_move("かかとおとし", "かくとう", @model.Physical, 120, accuracy=90)
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40)
  let ball = mk_move("シャドーボール", "ゴースト", @model.Special, 80)
  let diveg = mk_move("シャドーダイブ", "ゴースト", @model.Physical, 80)
  let quake = isw_quake()
  let mine = [
    isw_champ("HJK", "かくとう", "", "すてみ", 200, 120, 100, 110, 100, 120, [hjk, splash]),
    isw_champ("AxeK", "かくとう", "", "", 200, 120, 100, 110, 100, 110, [axe, tackle]),
    isw_champ("Plain", "ノーマル", "", "", 200, 100, 100, 110, 100, 90, [tackle, splash]),
  ]
  let opp = [
    isw_champ("GroundB", "じめん", "", "", 200, 130, 100, 110, 100, 80, [quake, splash]),
    isw_champ("GhostA", "ゴースト", "", "", 200, 120, 100, 130, 100, 100, [ball, splash]),
    isw_champ("GhostB", "ゴースト", "どく", "", 200, 130, 100, 110, 100, 90, [diveg, splash]),
  ]
  let v = switching_game_winrate(mine, opp, 3)
  assert_true(isw_near(v, -0.08800084874647274))
}
