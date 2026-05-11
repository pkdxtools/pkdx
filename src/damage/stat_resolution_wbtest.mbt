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

///|
/// Body Press and the Psyshock family live on opposite axes: Body Press
/// rewrites the attacker stat, Psyshock rewrites the defender stat. The
/// struct must allow them to compose in any pairing without cross-talk.
/// (The move name gate keeps only one branch firing per call; these tests
/// verify the *other* axis stays on its default.)
test "stat_resolution: Body Press keeps defender stat on default Def" {
  // Body Press is physical → default defender is Def already, so the
  // Psyshock branch must not fire. Verify by swapping in an SpD-heavy
  // defender and confirming Def is still chosen.
  let mv = sr_move("ボディプレス", @model.Physical, 80)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=60, atk_spa=60, def_def=70, def_spd=200,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="Def")
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.effective_physical, content="true")
}

///|
test "stat_resolution: Psyshock keeps attacker stat on default SpA" {
  // Psyshock is special → attacker is SpA. Body-Press-style atk_stat_kind
  // override must not leak in even when the attacker's Defense is larger.
  let mv = sr_move("サイコショック", @model.Special, 80)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=200, atk_spa=100, def_def=80, def_spd=200,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="SpA")
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.effective_physical, content="false")
}

///|
test "stat_resolution: Psyshock × Unaware fully masks attacker stages" {
  // Unaware on the defender should still flip atk_rank_mask even when the
  // defender stat kind is overridden to Def.
  let mv = sr_move("サイコブレイク", @model.Special, 100)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=140, def_def=80, def_spd=140,
    atk_ability="", def_ability="てんねん", critical=false,
  )
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.atk_rank_mask, content="true")
  inspect(sr.def_rank_mask, content="false")
}

///|
test "stat_resolution: Body Press × critical keeps Def-as-attack and sets masks" {
  // Body Press under critical: attacker reads own Def as attack stat, and
  // critical still fires both directional masks. Neither branch should
  // cancel the other.
  let mv = sr_move("ボディプレス", @model.Physical, 80)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=80, atk_spa=60, def_def=150, def_spd=100,
    atk_ability="", def_ability="", critical=true,
  )
  inspect(sr.atk_stat_kind, content="Def")
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.atk_rank_negative_mask, content="true")
  inspect(sr.def_rank_positive_mask, content="true")
}

///|
test "stat_resolution: Body Press × Unaware on attacker masks defender ranks" {
  // Attacker holding Unaware: defender's ranks fully masked; atk_stat_kind
  // stays on Def (Body Press).
  let mv = sr_move("ボディプレス", @model.Physical, 80)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=80, atk_spa=60, def_def=150, def_spd=100,
    atk_ability="てんねん", def_ability="", critical=false,
  )
  inspect(sr.atk_stat_kind, content="Def")
  inspect(sr.def_rank_mask, content="true")
  inspect(sr.atk_rank_mask, content="false")
}

///|
test "stat_resolution: Psyshock × critical composes def_positive_mask" {
  // Crit gives the defender's +stages a mask; the Psyshock Def override
  // must keep that mask active (same stage index applies to Def and SpD
  // in the ladder, so correctness comes from *which* mask is set).
  let mv = sr_move("しんぴのつるぎ", @model.Special, 85)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=130, def_def=80, def_spd=130,
    atk_ability="", def_ability="", critical=true,
  )
  inspect(sr.def_stat_kind, content="Def")
  inspect(sr.def_rank_positive_mask, content="true")
  inspect(sr.atk_rank_negative_mask, content="true")
}

///|
test "stat_resolution: Shell Side Arm physical mode forces contact=true" {
  // Physical route must mark the move as contact so downstream contact-based
  // bonuses (rough skin, iron fist family, etc.) fire correctly.
  let mv = sr_move("シェルアームズ", @model.Special, 90)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=120, atk_spa=100, def_def=100, def_spd=120,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.force_contact, content="Some(true)")
}

///|
test "stat_resolution: Shell Side Arm special mode forces contact=false" {
  // Special route must mark the move as non-contact regardless of any name
  // table entry (Shell Side Arm's table entry targets the physical form).
  let mv = sr_move("シェルアームズ", @model.Special, 90)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=120, def_def=120, def_spd=120,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.force_contact, content="Some(false)")
}

///|
test "stat_resolution: non-Shell-Side-Arm keeps force_contact None" {
  // Every other move leaves force_contact unset; downstream defers to the
  // static is_contact_move table.
  let mv = sr_move("ボディプレス", @model.Physical, 80)
  let sr = resolve_stat_resolution(
    mv,
    atk_atk=100, atk_spa=100, def_def=150, def_spd=100,
    atk_ability="", def_ability="", critical=false,
  )
  inspect(sr.force_contact, content="None")
}

///|
test "stat_resolution: Secret Sword × Body Press does not apply (mutually exclusive by name)" {
  // Secret Sword (せいなるつるぎ) is a named physical move distinct from
  // Body Press (ボディプレス). Only one name branch fires per call; this
  // regression-guards the name gates so a future refactor to a shared
  // "move attribute" table doesn't accidentally merge them.
  let body_press = sr_move("ボディプレス", @model.Physical, 80)
  let sr_bp = resolve_stat_resolution(
    body_press,
    atk_atk=100, atk_spa=100, def_def=150, def_spd=100,
    atk_ability="", def_ability="", critical=false,
  )
  // Body Press does NOT set def_rank_positive_mask.
  inspect(sr_bp.def_rank_positive_mask, content="false")
  let secret_sword = sr_move("せいなるつるぎ", @model.Physical, 85)
  let sr_ss = resolve_stat_resolution(
    secret_sword,
    atk_atk=120, atk_spa=100, def_def=100, def_spd=100,
    atk_ability="", def_ability="", critical=false,
  )
  // Secret Sword does NOT remap atk_stat_kind.
  inspect(sr_ss.atk_stat_kind, content="Atk")
  inspect(sr_ss.def_rank_positive_mask, content="true")
}
