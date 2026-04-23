///|
/// Whitebox tests for `resolve_stat_resolution`. Each mechanic (Body Press,
/// Psyshock family, Secret Sword, Shell Side Arm, Unaware, critical hit) is
/// exercised independently, then two mechanics are composed (critical ×
/// Unaware) to prove the orthogonal design survives mixed cases.
///
/// These tests are Red-first: they fail until `stat_resolution.mbt`
/// implements `resolve_stat_resolution` with the StatResolution struct.

///|
/// Minimal Move constructor. Only the fields `resolve_stat_resolution`
/// reads (name / category / power) vary across tests; the rest are fixed.
fn sr_move(
  name : String,
  category : @model.MoveCategory,
  power : Int,
) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category,
    power,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
  }
}

///|
test "stat_resolution: default physical picks Atk vs Def" {
  let mv = sr_move("たいあたり", @model.Physical, 40)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=120, atk_spa=100, def_def=100, def_spd=100,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="Atk")
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.effective_physical, content="true")
  inspect(sr.atk_rank_mask, content="false")
  inspect(sr.def_rank_mask, content="false")
}

///|
test "stat_resolution: default special picks SpA vs SpD" {
  let mv = sr_move("ねんりき", @model.Special, 50)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=120, def_def=100, def_spd=100,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="SpA")
  inspect(sr.def_stat_kind, content="SpD")
  inspect(sr.effective_physical, content="false")
}

///|
test "stat_resolution: Body Press uses Def as attack stat" {
  let mv = sr_move("ボディプレス", @model.Physical, 80)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=100, def_def=150, def_spd=100,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="Def")
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.effective_physical, content="true")
}

///|
test "stat_resolution: Psyshock is special but hits physical Def" {
  let mv = sr_move("サイコショック", @model.Special, 80)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=120, def_def=80, def_spd=120,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="SpA")
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.effective_physical, content="false")
}

///|
test "stat_resolution: Psystrike same family as Psyshock" {
  let mv = sr_move("サイコブレイク", @model.Special, 100)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=140, def_def=80, def_spd=140,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="SpA")
  inspect(sr.def_stat_kind, content="Def")
}

///|
test "stat_resolution: Mystical Sword same family as Psyshock" {
  let mv = sr_move("しんぴのつるぎ", @model.Special, 85)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=130, def_def=80, def_spd=130,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.def_stat_kind, content="Def")
}

///|
test "stat_resolution: Secret Sword ignores defender +rank only" {
  let mv = sr_move("せいなるつるぎ", @model.Physical, 85)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=120, atk_spa=100, def_def=100, def_spd=100,
    atk_ability="", def_ability="", critical=false,
  )
  // Physical category preserved.
  inspect(sr.atk_stat_kind, content="Atk")
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.effective_physical, content="true")
  // Defender positive rank mask set; negative rank still applies.
  inspect(sr.def_rank_positive_mask, content="true")
  inspect(sr.def_rank_negative_mask, content="false")
  inspect(sr.def_rank_mask, content="false")
}

///|
test "stat_resolution: Shell Side Arm strict > chooses physical" {
  // atk_atk * def_spd = 120 * 120 = 14400
  // atk_spa * def_def = 100 * 100 = 10000
  // 14400 > 10000 → physical
  let mv = sr_move("シェルアームズ", @model.Special, 90)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=120, atk_spa=100, def_def=100, def_spd=120,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="Atk")
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.effective_physical, content="true")
}

///|
test "stat_resolution: Shell Side Arm tie falls to special" {
  // atk_atk * def_spd = 100 * 100 = 10000
  // atk_spa * def_def = 100 * 100 = 10000
  // Tie → special (Showdown spec)
  let mv = sr_move("シェルアームズ", @model.Special, 90)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=100, def_def=100, def_spd=100,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="SpA")
  inspect(sr.def_stat_kind, content="SpD")
  inspect(sr.effective_physical, content="false")
}

///|
test "stat_resolution: Shell Side Arm < chooses special" {
  // atk_atk * def_spd = 100 * 120 = 12000
  // atk_spa * def_def = 120 * 120 = 14400
  // 12000 < 14400 → special
  let mv = sr_move("シェルアームズ", @model.Special, 90)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=120, def_def=120, def_spd=120,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="SpA")
  inspect(sr.def_stat_kind, content="SpD")
  inspect(sr.effective_physical, content="false")
}

///|
test "stat_resolution: Unaware on defender masks attacker's stages fully" {
  let mv = sr_move("たいあたり", @model.Physical, 40)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=100, def_def=100, def_spd=100,
    atk_ability="", def_ability="てんねん", critical=false,
  )
  inspect(sr.atk_rank_mask, content="true")
  // Defender's own ranks still apply (Unaware is one-sided).
  inspect(sr.def_rank_mask, content="false")
}

///|
test "stat_resolution: Unaware on attacker masks defender's stages fully" {
  let mv = sr_move("たいあたり", @model.Physical, 40)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=100, def_def=100, def_spd=100,
    atk_ability="てんねん", def_ability="", critical=false,
  )
  inspect(sr.def_rank_mask, content="true")
  inspect(sr.atk_rank_mask, content="false")
}

///|
test "stat_resolution: critical hit masks only harmful stages" {
  let mv = sr_move("たいあたり", @model.Physical, 40)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=100, def_def=100, def_spd=100,
    atk_ability="", def_ability="", critical=true,
  )
  // Critical: attacker's negative stages ignored, defender's positive stages
  // ignored. The other direction still applies.
  inspect(sr.atk_rank_negative_mask, content="true")
  inspect(sr.atk_rank_positive_mask, content="false")
  inspect(sr.def_rank_positive_mask, content="true")
  inspect(sr.def_rank_negative_mask, content="false")
}

///|
test "stat_resolution: critical × Unaware composes orthogonally" {
  let mv = sr_move("たいあたり", @model.Physical, 40)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=100, def_def=100, def_spd=100,
    atk_ability="", def_ability="てんねん", critical=true,
  )
  // Unaware pulls atk_rank_mask all the way up.
  inspect(sr.atk_rank_mask, content="true")
  // Critical's def_rank_positive_mask still fires independently of Unaware.
  inspect(sr.def_rank_positive_mask, content="true")
}

///|
test "stat_resolution: Shell Side Arm × Unaware composes" {
  // Physical by ratio, but Unaware masks defender's ranks too.
  let mv = sr_move("シェルアームズ", @model.Special, 90)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=150, atk_spa=100, def_def=80, def_spd=120,
    atk_ability="てんねん", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="Atk")
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.def_rank_mask, content="true")
}
