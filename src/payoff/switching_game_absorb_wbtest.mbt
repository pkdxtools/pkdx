///|
/// 吸収特性の DP 経路。そうしょく と同じ `with_absorb_effects` /
/// `attempt_accuracy` を、Champions 本文にある回復とランク上昇に広げる。
///
/// - ちくでん / ちょすい / かんそうはだ (みず): 最大 HP の 1/4 を回復 (上限で頭打ち)
/// - でんきエンジン: 素早さ +1 (上限 +6)
/// - ひらいしん: 特攻 +1。シングルなので引き寄せはしない
/// - もらいび: 無効にし、生存中の holder の slot をもらいび状態にする。威力 1.5 は別テスト
/// - 自分・味方・フィールド・相手側の技は吸収しない
/// - サンダーダイブ は吸収したうえで崩れる (onTryHit の null は MoveFail)
/// - 交代先で判定し、出ていく側の吸収では外れを消さない

///|
fn ab_bolt() -> @model.Move {
  mk_move("１０まんボルト", "でんき", @model.Special, 90)
}

///|
fn ab_surf() -> @model.Move {
  mk_move("なみのり", "みず", @model.Special, 90, accuracy=80)
}

///|
fn ab_wave() -> @model.Move {
  mk_move(
    "でんじは",
    "でんき",
    @model.Status,
    0,
    accuracy=90,
    status_effect=Some((@model.ParalyzeKind, 100)),
  )
}

///|
fn ab_dive() -> @model.Move {
  mk_move("サンダーダイブ", "でんき", @model.Physical, 100, accuracy=95)
}

///|
fn ab_splash() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
fn ab_holder(ability : String, max_hp : Int) -> Combatant {
  crash_mon("Holder", [im_tackle()], max_hp, ability=ability)
}

///|
fn ab_user(mv : @model.Move, max_hp : Int, ability? : String = "") -> Combatant {
  crash_mon("Attacker", [mv], max_hp, ability=ability)
}

///|
fn ab_leaf(
  ability : String,
  mv : @model.Move,
  holder_hp : Int,
  max_hp : Int,
  mean_damage : Int,
  opp_ranks? : Array[Int] = [0, 0, 0, 0, 0],
  atk_ability? : String = "",
) -> SwitchingGameState {
  let state = {
    ..im_state(my_hps=[max_hp], opp_hps=[holder_hp]),
    opp_ranks,
  }
  let outs = apply_damage_variants_fanout(
    state,
    [{ probability: 1.0, mean_damage, hits_count: 1, hit_steps: [] }],
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[ab_user(mv, max_hp, ability=atk_ability)],
    defender_team=[ab_holder(ability, max_hp)],
    pre_dmg_defender_hp=holder_hp,
  )
  if outs.length() != 1 {
    abort("ab_leaf: expected a single leaf")
  }
  outs[0].1
}

///|
fn ab_near(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
test "ちくでん: でんき技は当たらず最大HPの1/4を回復する" {
  let s = ab_leaf("ちくでん", ab_bolt(), 100, 200, 80)
  @debug.assert_eq(s.opp_hps[0], 150)
  @debug.assert_eq(s.my_hps[0], 200)
  @debug.assert_eq(s.opp_ranks[2], 0)
  @debug.assert_eq(s.opp_status[0], @model.None)
}

///|
test "ちょすい: みず技は当たらず最大HPの1/4を回復する" {
  let s = ab_leaf("ちょすい", ab_surf(), 100, 200, 80)
  @debug.assert_eq(s.opp_hps[0], 150)
  @debug.assert_eq(s.my_hps[0], 200)
}

///|
test "かんそうはだ: みずは1/4回復し、ほのおは吸収せずダメージを受ける" {
  let water = ab_leaf("かんそうはだ", ab_surf(), 100, 200, 80)
  @debug.assert_eq(water.opp_hps[0], 150)
  let fire = mk_move("かえんほうしゃ", "ほのお", @model.Special, 90)
  let burned = ab_leaf("かんそうはだ", fire, 100, 200, 40)
  @debug.assert_eq(burned.opp_hps[0], 60)
}

///|
test "吸収の回復は最大HPで頭打ちになり、満タンでも技は当たらない" {
  let s = ab_leaf("ちょすい", ab_surf(), 180, 200, 80)
  @debug.assert_eq(s.opp_hps[0], 200)
  let full = ab_leaf("ちくでん", ab_bolt(), 200, 200, 80)
  @debug.assert_eq(full.opp_hps[0], 200)
}

///|
test "でんきエンジン: でんき技で素早さ+1、HPは変わらない" {
  let s = ab_leaf("でんきエンジン", ab_bolt(), 100, 200, 80)
  @debug.assert_eq(s.opp_ranks[4], 1)
  @debug.assert_eq(s.opp_ranks[2], 0)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
test "ひらいしん: でんき技で特攻+1、引き寄せ先はなくHPは変わらない" {
  let s = ab_leaf("ひらいしん", ab_bolt(), 100, 200, 80)
  @debug.assert_eq(s.opp_ranks[2], 1)
  @debug.assert_eq(s.opp_ranks[4], 0)
  @debug.assert_eq(s.my_ranks[2], 0)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
test "もらいび: ほのおを無効にするだけでランクもHPも変わらない" {
  let fire = mk_move(
    "おにび",
    "ほのお",
    @model.Status,
    0,
    accuracy=85,
    status_effect=Some((@model.BurnKind, 100)),
  )
  let s = ab_leaf("もらいび", fire, 100, 200, 0)
  @debug.assert_eq(s.opp_status[0], @model.None)
  @debug.assert_eq(s.opp_hps[0], 100)
  @debug.assert_eq(s.opp_ranks[2], 0)
  let overheat = mk_move(
    "オーバーヒート",
    "ほのお",
    @model.Special,
    130,
    stat_effects=[@model.StatEffect::{ stat: 2, delta: -2, target: 0 }],
  )
  let dropped = ab_leaf("もらいび", overheat, 100, 200, 90)
  @debug.assert_eq(dropped.my_ranks[2], 0)
  @debug.assert_eq(dropped.opp_hps[0], 100)
  @debug.assert_eq(flash_fire_lit(s.opp_flash_fire, 0), true)
  @debug.assert_eq(flash_fire_lit(dropped.opp_flash_fire, 0), true)
}

///|
test "ちくでん: でんじはは麻痺させず1/4回復する" {
  let s = ab_leaf("ちくでん", ab_wave(), 100, 200, 0)
  @debug.assert_eq(s.opp_status[0], @model.None)
  @debug.assert_eq(s.opp_hps[0], 150)
}

///|
test "ひらいしん: 特攻+6でも吸収は起きるがランクは+6のまま" {
  let s = ab_leaf(
    "ひらいしん",
    ab_bolt(),
    100,
    200,
    80,
    opp_ranks=[0, 0, 6, 0, 0],
  )
  @debug.assert_eq(s.opp_ranks[2], 6)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
test "でんきエンジン: 吸収の素早さ+1は+2ではなく+6まで積み上がる" {
  let bolt = ab_bolt()
  let mut s = im_state(my_hps=[200], opp_hps=[100])
  let user = [ab_user(bolt, 200)]
  let holder = [ab_holder("でんきエンジン", 200)]
  for _i in 0..<3 {
    let outs = apply_damage_variants_fanout(
      s,
      [{ probability: 1.0, mean_damage: 40, hits_count: 1, hit_steps: [] }],
      attacker_is_me=true,
      attacker_active=0,
      defender_active=0,
      attacker_move=bolt,
      attacker_team=user,
      defender_team=holder,
      pre_dmg_defender_hp=100,
    )
    s = outs[0].1
  }
  @debug.assert_eq(s.opp_ranks[4], 3)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
test "吸収: 瀕死の防御側は回復もランク上昇もしない" {
  let healed = ab_leaf("ちくでん", ab_bolt(), 0, 200, 80)
  @debug.assert_eq(healed.opp_hps[0], 0)
  let boosted = ab_leaf("ひらいしん", ab_bolt(), 0, 200, 80)
  @debug.assert_eq(boosted.opp_ranks[2], 0)
  @debug.assert_eq(boosted.opp_hps[0], 0)
}

///|
test "吸収: タイプが違う技は通常どおり当たる" {
  let s = ab_leaf("ちくでん", im_tackle(), 100, 200, 40)
  @debug.assert_eq(s.opp_hps[0], 60)
  @debug.assert_eq(s.opp_ranks[4], 0)
}

///|
test "ちょすい: あまごいは吸収されず天候を張る" {
  let rain = {
    ..mk_move("あまごい", "みず", @model.Status, 0),
    weather_set: Some(@model.Rain),
  }
  let s = ab_leaf("ちょすい", rain, 100, 200, 0)
  @debug.assert_eq(s.weather, @model.Rain)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
test "ちくでん: じゅうでんは吸収されず自分の特防が上がる" {
  let charge = mk_move(
    "じゅうでん",
    "でんき",
    @model.Status,
    0,
    stat_effects=[@model.StatEffect::{ stat: 3, delta: 1, target: 0 }],
  )
  let s = ab_leaf("ちくでん", charge, 100, 200, 0)
  @debug.assert_eq(s.my_ranks[3], 1)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
test "もらいび: にほんばれは吸収されず天候を張る" {
  let sun = {
    ..mk_move("にほんばれ", "ほのお", @model.Status, 0),
    weather_set: Some(@model.Sun),
  }
  let s = ab_leaf("もらいび", sun, 100, 200, 0)
  @debug.assert_eq(s.weather, @model.Sun)
  @debug.assert_eq(s.opp_hps[0], 100)
  @debug.assert_eq(flash_fire_lit(s.opp_flash_fire, 0), false)
}

///|
test "ひらいしん: 吸収された技でもへんげんじざいの固定は記録される" {
  let s = ab_leaf("ひらいしん", ab_bolt(), 100, 200, 80, atk_ability="へんげんじざい")
  @debug.assert_eq(s.my_protean_locked[0], "でんき")
  @debug.assert_eq(s.opp_ranks[2], 1)
}

///|
test "サンダーダイブ: ちくでんは回復し、使用者は最大HPの1/2を失う" {
  let s = ab_leaf("ちくでん", ab_dive(), 100, 200, 90)
  @debug.assert_eq(s.opp_hps[0], 150)
  @debug.assert_eq(s.my_hps[0], 100)
}

///|
test "サンダーダイブ: ひらいしんは特攻+1し、使用者は最大HPの1/2を失う" {
  let s = ab_leaf("ひらいしん", ab_dive(), 100, 200, 90)
  @debug.assert_eq(s.opp_ranks[2], 1)
  @debug.assert_eq(s.opp_hps[0], 100)
  @debug.assert_eq(s.my_hps[0], 100)
}

///|
test "吸収対象の変化技は命中率100、非吸収は技の命中率" {
  let wave = ab_wave()
  let st = im_state()
  let mine = [ab_user(wave, 200)]
  @debug.assert_eq(
    attempt_accuracy(st, UseMove(0), true, mine, [ab_holder("ちくでん", 200)]),
    100,
  )
  @debug.assert_eq(
    attempt_accuracy(st, UseMove(0), true, mine, [ab_holder("", 200)]),
    90,
  )
  let surf = ab_surf()
  @debug.assert_eq(
    attempt_accuracy(
      st, UseMove(0), true, [ab_user(surf, 200)], [ab_holder("ちょすい", 200)],
    ),
    100,
  )
}

///|
fn ab_turn(
  mine : Array[Combatant],
  opp : Array[Combatant],
  opp_action : ActionKind,
  opp_hps : Array[Int],
) -> Array[(Double, SwitchingGameState)] {
  let st = im_state(my_hps=[200], opp_hps=opp_hps)
  attempt_turn_with_cache(
    st, UseMove(0), opp_action, mine, opp, new_damage_cache(),
  )
}

///|
test "交代先のちょすいはなみのりを外れ前に吸収して1/4回復する" {
  let surf = ab_surf()
  let mine = [crash_mon("Surf", [surf], 200, spe=120)]
  let leaving = crash_mon("Out", [ab_splash()], 200, spe=100)
  let incoming = crash_mon("In", [ab_splash()], 200, spe=70, ability="ちょすい")
  let outs = ab_turn(mine, [leaving, incoming], Switch(1), [80, 80])
  @debug.assert_eq(outs.length(), 1)
  assert_true(ab_near(outs[0].0, 1.0))
  @debug.assert_eq(outs[0].1.opp_active, 1)
  @debug.assert_eq(outs[0].1.opp_hps[0], 80)
  @debug.assert_eq(outs[0].1.opp_hps[1], 130)
}

///|
test "出ていくちょすいは交代先へのなみのりの外れを消さない" {
  let surf = ab_surf()
  let mine = [crash_mon("Surf", [surf], 200, spe=120)]
  let leaving = crash_mon("Out", [ab_splash()], 200, spe=100, ability="ちょすい")
  let incoming = crash_mon("In", [ab_splash()], 200, spe=70)
  let outs = ab_turn(mine, [leaving, incoming], Switch(1), [80, 80])
  let mut saw_hit = false
  let mut saw_miss = false
  for o in outs {
    let (p, s) = o
    @debug.assert_eq(s.opp_active, 1)
    @debug.assert_eq(s.opp_hps[0], 80)
    if ab_near(p, 0.8) {
      saw_hit = true
      assert_true(s.opp_hps[1] < 80)
    } else if ab_near(p, 0.2) {
      saw_miss = true
      @debug.assert_eq(s.opp_hps[1], 80)
    }
  }
  assert_true(saw_hit)
  assert_true(saw_miss)
}

///|
test "交代先のちくでんはでんじはを外れ前に吸収して回復し、麻痺しない" {
  let wave = ab_wave()
  let mine = [crash_mon("Wave", [wave], 200, spe=120)]
  let leaving = crash_mon("Out", [ab_splash()], 200, spe=100)
  let incoming = crash_mon("In", [ab_splash()], 200, spe=70, ability="ちくでん")
  let outs = ab_turn(mine, [leaving, incoming], Switch(1), [80, 80])
  @debug.assert_eq(outs.length(), 1)
  assert_true(ab_near(outs[0].0, 1.0))
  @debug.assert_eq(outs[0].1.opp_active, 1)
  @debug.assert_eq(outs[0].1.opp_status[1], @model.None)
  @debug.assert_eq(outs[0].1.opp_hps[1], 130)
}

///|
test "出ていくちくでんは交代先へのでんじはの外れを消さない" {
  let wave = ab_wave()
  let mine = [crash_mon("Wave", [wave], 200, spe=120)]
  let leaving = crash_mon("Out", [ab_splash()], 200, spe=100, ability="ちくでん")
  let incoming = crash_mon("In", [ab_splash()], 200, spe=70)
  let outs = ab_turn(mine, [leaving, incoming], Switch(1), [80, 80])
  let mut saw_para = false
  let mut saw_miss = false
  for o in outs {
    let (p, s) = o
    @debug.assert_eq(s.opp_active, 1)
    @debug.assert_eq(s.opp_hps[1], 80)
    if ab_near(p, 0.9) {
      saw_para = true
      @debug.assert_eq(s.opp_status[1], @model.Paralyze)
    } else if ab_near(p, 0.1) {
      saw_miss = true
      @debug.assert_eq(s.opp_status[1], @model.None)
    }
  }
  assert_true(saw_para)
  assert_true(saw_miss)
}

///|
test "交代先のひらいしんはかみなりを外れ前に吸収して特攻+1する" {
  let bolt = mk_move("かみなり", "でんき", @model.Special, 110, accuracy=70)
  let mine = [crash_mon("Bolt", [bolt], 200, spe=120)]
  let leaving = crash_mon("Out", [ab_splash()], 200, spe=100)
  let incoming = crash_mon("In", [ab_splash()], 200, spe=70, ability="ひらいしん")
  let outs = ab_turn(mine, [leaving, incoming], Switch(1), [80, 80])
  @debug.assert_eq(outs.length(), 1)
  assert_true(ab_near(outs[0].0, 1.0))
  @debug.assert_eq(outs[0].1.opp_active, 1)
  @debug.assert_eq(outs[0].1.opp_ranks[2], 1)
  @debug.assert_eq(outs[0].1.opp_hps[1], 80)
}

///|
test "出ていくひらいしんは交代先へのかみなりの外れを消さない" {
  let bolt = mk_move("かみなり", "でんき", @model.Special, 110, accuracy=70)
  let mine = [crash_mon("Bolt", [bolt], 200, spe=120)]
  let leaving = crash_mon("Out", [ab_splash()], 200, spe=100, ability="ひらいしん")
  let incoming = crash_mon("In", [ab_splash()], 200, spe=70)
  let outs = ab_turn(mine, [leaving, incoming], Switch(1), [80, 80])
  let mut saw_hit = false
  let mut saw_miss = false
  for o in outs {
    let (p, s) = o
    @debug.assert_eq(s.opp_active, 1)
    @debug.assert_eq(s.opp_ranks[2], 0)
    if ab_near(p, 0.7) {
      saw_hit = true
      assert_true(s.opp_hps[1] < 80)
    } else if ab_near(p, 0.3) {
      saw_miss = true
      @debug.assert_eq(s.opp_hps[1], 80)
    }
  }
  assert_true(saw_hit)
  assert_true(saw_miss)
}
