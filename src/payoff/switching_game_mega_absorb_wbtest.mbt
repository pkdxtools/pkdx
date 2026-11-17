///|
/// Mega したターンの吸収 / 無効判定。`attempt_accuracy` はメガフラグを書く前に走るので、
/// このターンのメガは `effective_combatant` (メガ後の特性・タイプ、Protean はメガで解除)
/// で見ないと、そうしょく を得るターンに外れ枝が残り、失うターンは命中 100 のまま眠らされる。
/// MC はメガ未モデル。ダメージ技のタイプ / 特性無効を命中率 100 にする非メガ規則だけ合わせる。

///|
fn ma_form(ability : String, type1 : String, spe : Int) -> @model.MegaForm {
  {
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe,
    type1,
    type2: "",
    ability,
    name_ja: "メガテスト",
  }
}

///|
fn ma_mon(
  name : String,
  type1 : String,
  ability : String,
  moves : Array[@model.Move],
  spe : Int,
  mega_ability? : String = "",
  mega_type? : String = "",
  has_mega? : Bool = false,
) -> Combatant {
  let base = { ..im_pokemon(name, spe=spe), type1 }
  let mega_type1 = if mega_type == "" { type1 } else { mega_type }
  let form = if has_mega {
    Some(ma_form(mega_ability, mega_type1, spe))
  } else {
    None
  }
  im_combatant(base, moves, ability=ability, mega_form=form)
}

///|
fn ma_spore() -> @model.Move {
  mk_move(
    "ねむりごな",
    "くさ",
    @model.Status,
    0,
    accuracy=75,
    status_effect=Some((@model.SleepKind, 100)),
  )
}

///|
fn ma_splash() -> @model.Move {
  mk_move("はねる", "ノーマル", @model.Status, 0)
}

///|
fn ma_tackle() -> @model.Move {
  mk_move("たいあたり", "ノーマル", @model.Physical, 40, accuracy=50)
}

///|
fn ma_quake() -> @model.Move {
  mk_move("じしん", "じめん", @model.Physical, 100, accuracy=50)
}

///|
fn ma_turn(
  mine : Combatant,
  opp : Combatant,
  my_action : ActionKind,
  opp_action : ActionKind,
  state : SwitchingGameState,
) -> Array[(Double, SwitchingGameState)] {
  attempt_turn_with_cache(
    state,
    my_action,
    opp_action,
    [mine],
    [opp],
    new_damage_cache(),
  )
}

///|
/// 相手がこのターン そうしょく を得る。ねむりごな 75 は外れず、A +1 の単一 leaf。
test "mega absorb DP: そうしょくを得るメガターンは命中 100 で A +1" {
  let mine = ma_mon("Spore", "ノーマル", "", [ma_spore()], 120)
  let opp = ma_mon(
    "Holder",
    "ノーマル",
    "",
    [ma_splash()],
    80,
    mega_ability="そうしょく",
    has_mega=true,
  )
  let outs = ma_turn(mine, opp, UseMove(0), Mega(0), im_state())
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_ranks[0] == 1 }), 1.0)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_status[0] == @model.None }), 1.0)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_megaed[0] }), 1.0)
  @debug.assert_eq(outs[0].1.opp_hps[0], 100)
}

///|
/// 自分がこのターン そうしょく を得る (フラグの左右が逆でも同じ)。
test "mega absorb DP: 自分がそうしょくを得るメガターンは命中 100 で A +1" {
  let mine = ma_mon(
    "Holder",
    "ノーマル",
    "",
    [ma_splash()],
    80,
    mega_ability="そうしょく",
    has_mega=true,
  )
  let opp = ma_mon("Spore", "ノーマル", "", [ma_spore()], 120)
  let outs = ma_turn(mine, opp, Mega(0), UseMove(0), im_state())
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.my_ranks[0] == 1 }), 1.0)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.my_status[0] == @model.None }), 1.0)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.my_megaed[0] }), 1.0)
}

///|
/// 相手がこのターン そうしょく を失う。ねむりごな 75 は通常の命中で、A は上がらない。
test "mega absorb DP: そうしょくを失うメガターンはねむりごなの命中率のまま" {
  let mine = ma_mon("Spore", "ノーマル", "", [ma_spore()], 120)
  let opp = ma_mon(
    "Holder",
    "ノーマル",
    "そうしょく",
    [ma_splash()],
    80,
    mega_ability="",
    has_mega=true,
  )
  let outs = ma_turn(mine, opp, UseMove(0), Mega(0), im_state())
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_status[0] != @model.None }), 0.75)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_status[0] == @model.None }), 0.25)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_ranks[0] == 0 }), 1.0)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_megaed[0] }), 1.0)
}

///|
/// 既にメガ済みの そうしょく は UseMove でも吸収する (フラグはターン頭に立っている)。
test "mega absorb DP: メガ済みのそうしょくは UseMove でも吸収する" {
  let mine = ma_mon("Spore", "ノーマル", "", [ma_spore()], 120)
  let opp = ma_mon(
    "Holder",
    "ノーマル",
    "",
    [ma_splash()],
    80,
    mega_ability="そうしょく",
    has_mega=true,
  )
  let st = { ..im_state(), opp_megaed: [true, false, false] }
  let outs = ma_turn(mine, opp, UseMove(0), UseMove(0), st)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_ranks[0], 1)
  @debug.assert_eq(outs[0].1.opp_status[0], @model.None)
}

///|
/// へんげんじざい の じしん 50 を、このターン ふゆう になる相手へ。外れ枝は無く、
/// 免疫 leg でも Protean は記録される。
test "mega absorb DP: ふゆうを得るメガターンはダメージ技を外さない" {
  let mine = ma_mon("Protean", "ノーマル", "へんげんじざい", [ma_quake()], 120)
  let opp = ma_mon(
    "Levi",
    "ノーマル",
    "",
    [ma_splash()],
    80,
    mega_ability="ふゆう",
    has_mega=true,
  )
  let outs = ma_turn(mine, opp, UseMove(0), Mega(0), im_state())
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.my_protean_locked[0] == "じめん" }), 1.0)
  @debug.assert_eq(outs[0].1.opp_hps[0], 100)
  @debug.assert_eq(outs[0].1.opp_megaed[0], true)
}

///|
/// このターン ゴースト になる相手へ、たいあたり 50。タイプ無効で外れ枝は無い。
/// 使用者は単ノーマルなので、同じタイプのたいあたりではロックを消費しない。
test "mega absorb DP: ゴーストになるメガターンはノーマル技を外さない" {
  let mine = ma_mon("Protean", "ノーマル", "へんげんじざい", [ma_tackle()], 120)
  let opp = ma_mon(
    "Ghost",
    "ノーマル",
    "",
    [ma_splash()],
    80,
    mega_type="ゴースト",
    has_mega=true,
  )
  let outs = ma_turn(mine, opp, UseMove(0), Mega(0), im_state())
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.my_protean_locked[0] == "" }), 1.0)
  @debug.assert_eq(outs[0].1.opp_hps[0], 100)
}

///|
/// 攻撃側が エレキスキン を得る。たいあたりはでんきになり、ひらいしん は外さない。
test "mega absorb DP: エレキスキンを得るメガターンはひらいしんで外れない" {
  let mine = ma_mon(
    "Skin",
    "ノーマル",
    "",
    [ma_tackle()],
    120,
    mega_ability="エレキスキン",
    has_mega=true,
  )
  let opp = ma_mon("Rod", "ノーマル", "ひらいしん", [ma_splash()], 80)
  let outs = ma_turn(mine, opp, Mega(0), UseMove(0), im_state())
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.opp_hps[0], 100)
  @debug.assert_eq(outs[0].1.my_megaed[0], true)
}

///|
/// ゴーストにロックされた相手がメガするとロックは外れ、たいあたり 50 は当たる。
test "mega absorb DP: メガでプロテアンロックが外れるとタイプ無効にならない" {
  let mine = ma_mon("Atk", "ノーマル", "", [ma_tackle()], 120)
  let opp = ma_mon(
    "Locked",
    "ノーマル",
    "",
    [ma_splash()],
    80,
    mega_ability="",
    mega_type="ノーマル",
    has_mega=true,
  )
  let st = { ..im_state(), opp_protean_locked: ["ゴースト", "", ""] }
  let outs = ma_turn(mine, opp, UseMove(0), Mega(0), st)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_hps[0] < 100 }), 0.5)
  @debug.assert_eq(mm_mass(outs, fn(s) { s.opp_megaed[0] }), 1.0)
}

///|
/// メガしていない相手が Protean でゴーストなら、たいあたり 50 は外れない。
/// 使用者自身も単ノーマルのへんげんじざいだが、たいあたりではロックしない。
test "mega absorb DP: プロテアンでゴーストの相手はたいあたりを外さない" {
  let tackle = ma_tackle()
  let mine = ma_mon("Atk", "ノーマル", "へんげんじざい", [tackle], 120)
  let opp = ma_mon("Locked", "ノーマル", "", [ma_splash()], 80)
  let st = { ..im_state(), opp_protean_locked: ["ゴースト", "", ""] }
  @debug.assert_eq(attempt_accuracy(st, UseMove(0), true, [mine], [opp]), 100)
  let outs = ma_turn(mine, opp, UseMove(0), UseMove(0), st)
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.my_protean_locked[0], "")
  @debug.assert_eq(outs[0].1.opp_hps[0], 100)
}

///|
test "MC: ダメージ技の無効と無効な変化技は命中 100、当たる変化技は技の命中率" {
  let tackle = ma_tackle()
  let water = mk_move("みずでっぽう", "みず", @model.Special, 40, accuracy=50)
  let wave = mk_move("でんじは", "でんき", @model.Status, 0, accuracy=90)
  let atk = ma_mon("Atk", "ノーマル", "", [tackle], 100)
  let ghost = ma_mon("Ghost", "ゴースト", "", [tackle], 80)
  let normal = ma_mon("Normal", "ノーマル", "", [tackle], 80)
  let absorb = ma_mon("Absorb", "ノーマル", "ちょすい", [water], 80)
  let ground = ma_mon("Ground", "じめん", "", [wave], 80)
  let none = @model.Weather::None
  @debug.assert_eq(mc_attempt_accuracy(atk, tackle, ghost, none), 100)
  @debug.assert_eq(mc_attempt_accuracy(atk, tackle, normal, none), 50)
  @debug.assert_eq(
    mc_attempt_accuracy(atk, tackle, normal, none, defender_protean="ゴースト"),
    100,
  )
  @debug.assert_eq(mc_attempt_accuracy(atk, water, absorb, none), 100)
  // でんじははじめんに効かない。ノーマルには技の命中率 90 のまま。
  @debug.assert_eq(mc_attempt_accuracy(atk, wave, ground, none), 100)
  @debug.assert_eq(mc_attempt_accuracy(atk, wave, normal, none), 90)
}
