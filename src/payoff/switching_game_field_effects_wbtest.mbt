///|
/// Stage G (フィールド非 damage 効果) wbtest 群。Plan v3 G-1 / G-2 / G-3 を
/// 1 ファイルにまとめ、3 効果 × 3 grounded 否定条件 (ふゆう / ひこう /
/// ふうせん) + Field None 対照を網羅する。
///
/// 対象効果:
///   - G-1: Grassy heal     — EOT で grounded active が max/16 回復
///   - G-2: Misty status block — Misty + grounded defender で status 付与不可
///   - G-3: Psychic priority block — Psychic + grounded defender に対する
///          priority>0 攻撃を完全無効化 (damage=0 / status なし)
///
/// 既存 `is_grounded` ヘルパー (`src/damage/field.mbt`) を import 共有する。
/// 再実装はしない (Stage F-1 で確定済の単一 SSoT)。

///|
/// Stage G 用最小 Combatant ヘルパー。type1 / type2 / ability / item を直接
/// パラメータで受け取り、grounded 否定条件 (ふゆう / ひこう / ふうせん) を
/// テスト側で構築できるようにする。
fn mk_field_eff_combatant(
  type1? : String = "ノーマル",
  type2? : String = "",
  ability? : String = "",
  item? : String = "",
  moves? : Array[@model.Move] = [],
) -> Combatant {
  let p : @model.Pokemon = {
    global_no: "0001",
    name_ja: "テスト",
    name_en: "Test",
    type1,
    type2,
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  {
    pokemon: p,
    moves,
    ability,
    item,
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([100, 100, 100, 100, 100, 100]),
    ivs: None,
  }
}

///|
/// Stage G 用 baseline state。HP は両側 100/100 で満タンではなく 50/100 にして
/// Grassy heal の +max/16 が観測しやすいようにしておく。weather/field とも
/// None で初期化し、個別テストで上書きする。
fn mk_field_eff_state() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [50, 50],
    opp_hps: [50, 50],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

// =================================================================
// G-1: Grassy heal in apply_eot
//
// Step 2 (leftovers heal) と Step 3 (leech tick) の間に挿入される。
// 両 active について state.field == Grassy and is_grounded(active) なら
// HP += max(1, max_hp / 16)、上限クランプ。
// =================================================================

///|
/// Case G-1-A: Grassy field 中、grounded active (素ノーマル / 特性なし) は
/// EOT で HP += max/16 = 6 (50 → 56)。
test "apply_eot: Grassy field grounded active heals max/16 (50 → 56)" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Grassy, field_turns_left: 5 }
  let team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let new_state = apply_eot(state, team, team)
  // max_hp=100, max/16=6 → 50+6=56
  @debug.assert_eq(new_state.my_hps[0], 56)
  @debug.assert_eq(new_state.opp_hps[0], 56)
}

///|
/// Case G-1-B: Field == None なら Grassy heal は発火しない (50 のまま)。
/// negative pin: Grassy heal が Grassy field のときだけ発火することを担保。
test "apply_eot: Field=None disables Grassy heal" {
  let state = mk_field_eff_state()
  let team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let new_state = apply_eot(state, team, team)
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.opp_hps[0], 50)
}

///|
/// Case G-1-C: Grassy + ふゆう active は grounded=false なので heal なし。
test "apply_eot: Grassy field ふゆう active skips heal" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Grassy, field_turns_left: 5 }
  let my_team = [
    mk_field_eff_combatant(ability="ふゆう"),
    mk_field_eff_combatant(),
  ]
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  // my 側 ふゆう: heal なし、opp 側 通常: heal +6
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.opp_hps[0], 56)
}

///|
/// Case G-1-D: Grassy + ひこうタイプ active は grounded=false なので heal なし。
test "apply_eot: Grassy field ひこう active skips heal" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Grassy, field_turns_left: 5 }
  let my_team = [
    mk_field_eff_combatant(type1="ひこう"),
    mk_field_eff_combatant(),
  ]
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.opp_hps[0], 56)
}

///|
/// Case G-1-D-extra: type2 のひこうも同様に heal をブロック。
test "apply_eot: Grassy field type2=ひこう active skips heal" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Grassy, field_turns_left: 5 }
  let my_team = [
    mk_field_eff_combatant(type1="ノーマル", type2="ひこう"),
    mk_field_eff_combatant(),
  ]
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.opp_hps[0], 56)
}

///|
/// Case G-1-E: Grassy + ふうせん持ち active は grounded=false なので heal なし。
test "apply_eot: Grassy field ふうせん active skips heal" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Grassy, field_turns_left: 5 }
  let my_team = [
    mk_field_eff_combatant(item="ふうせん"),
    mk_field_eff_combatant(),
  ]
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  @debug.assert_eq(new_state.my_hps[0], 50)
  @debug.assert_eq(new_state.opp_hps[0], 56)
}

///|
/// Case G-1-F: Grassy heal は HP=max で上限クランプ (no-op)。
test "apply_eot: Grassy field heal caps at max_hp" {
  let state0 = mk_field_eff_state()
  let state = {
    ..state0,
    field: @model.Field::Grassy,
    field_turns_left: 5,
    my_hps: [100, 100],
    opp_hps: [100, 100],
  }
  let team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let new_state = apply_eot(state, team, team)
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[0], 100)
}

///|
/// Case G-1-G: Grassy heal は HP=0 (ひんし) では発火しない (蘇生しない)。
/// `add_hp_capped` ヘルパーが「current_hp <= 0」ではなく「cur >= max_hp」だけ
/// しか弾かないため、ひんし保護は apply_eot 側で行う必要がある。
test "apply_eot: Grassy field heal skips fainted slot" {
  let state0 = mk_field_eff_state()
  let state = {
    ..state0,
    field: @model.Field::Grassy,
    field_turns_left: 5,
    my_hps: [0, 50],
    opp_hps: [50, 50],
  }
  let team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let new_state = apply_eot(state, team, team)
  // my 側はひんし: 蘇生しない
  @debug.assert_eq(new_state.my_hps[0], 0)
  // opp 側は通常 heal
  @debug.assert_eq(new_state.opp_hps[0], 56)
}

///|
/// Case G-1-H: Grassy heal は leftovers の **後** に走る。
/// たべのこし持ちの grounded active は leftovers (+max/16=6) → Grassy heal
/// (+max/16=6) で合計 +12 回復する (50 → 62)。
test "apply_eot: Grassy heal runs after leftovers (stacked +12)" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Grassy, field_turns_left: 5 }
  let my_team = [
    mk_field_eff_combatant(item="たべのこし"),
    mk_field_eff_combatant(),
  ]
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let new_state = apply_eot(state, my_team, opp_team)
  // たべのこし (+6) + Grassy heal (+6) = +12 → 50 → 62
  @debug.assert_eq(new_state.my_hps[0], 62)
  // opp 側はアイテムなし: Grassy heal のみ (+6)
  @debug.assert_eq(new_state.opp_hps[0], 56)
}

// =================================================================
// G-2: Misty status block in maybe_apply_status_fanout
//
// state.field == Misty AND is_grounded(defender) なら status 付与を skip
// (major status + confusion すべて)。Field != Misty / 非 grounded では
// 通常通り fanout する。
// =================================================================

///|
/// Stage G-2 用 でんじは 風の status 技ヘルパー。`mk_heal_move` ベース。
fn mk_status_move(
  name : String,
  type_ : String,
  kind : @model.StatusKind,
  chance : Int,
) -> @model.Move {
  {
    ..mk_heal_move(name, type_, @model.Status, 0),
    status_effect: Some((kind, chance)),
  }
}

///|
/// Case G-2-A: Misty field 中、grounded defender (素ノーマル) に
/// でんじは (100% paralyze) を撃っても status 付与なし (state は変化なし)。
test "maybe_apply_status_fanout: Misty field blocks status on grounded defender" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Misty, field_turns_left: 5 }
  // target_team[target_slot] は defender 本体。target_is_me=false なので
  // defender は opp 側、opp_active=0 → opp_team[0] が defender。
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let mv = mk_status_move("でんじは", "でんき", @model.ParalyzeKind, 100)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  // Misty + grounded → 1 leaf with original state (no status)。
  @debug.assert_eq(leaves.length(), 1)
  let (p, s) = leaves[0]
  @debug.assert_eq(p, 1.0)
  @debug.assert_eq(s.opp_status[0], @model.None)
}

///|
/// Case G-2-B: Field == None なら Misty block は発火せず、通常通り
/// でんじは 100% paralyze で 1 leaf (paralyze 付与) が返る。
test "maybe_apply_status_fanout: Field=None lets status fanout proceed" {
  let state = mk_field_eff_state()
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let mv = mk_status_move("でんじは", "でんき", @model.ParalyzeKind, 100)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  // 通常 fanout: 100% → 1 leaf (paralyze 付与)
  @debug.assert_eq(leaves.length(), 1)
  let (p, s) = leaves[0]
  @debug.assert_eq(p, 1.0)
  @debug.assert_eq(s.opp_status[0], @model.Paralyze)
}

///|
/// Case G-2-C: Misty + ふゆう defender は grounded=false なので Misty block を
/// 受けず、通常通り paralyze 付与。
test "maybe_apply_status_fanout: Misty field ふゆう defender takes status" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Misty, field_turns_left: 5 }
  let opp_team = [
    mk_field_eff_combatant(ability="ふゆう"),
    mk_field_eff_combatant(),
  ]
  let mv = mk_status_move("でんじは", "でんき", @model.ParalyzeKind, 100)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  @debug.assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  @debug.assert_eq(s.opp_status[0], @model.Paralyze)
}

///|
/// Case G-2-D: Misty + ひこう defender は grounded=false なので Misty block を
/// 受けず通常 fanout。でんじは の paralyze 自体は ひこう に効く (paralyze の
/// type 免疫は でんき のみ — `@model.immune_to_status` 参照)。よって Misty
/// block さえなければ paralyze が付与される。
test "maybe_apply_status_fanout: Misty field ひこう defender takes status" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Misty, field_turns_left: 5 }
  let opp_team = [
    mk_field_eff_combatant(type1="ノーマル", type2="ひこう"),
    mk_field_eff_combatant(),
  ]
  let mv = mk_status_move("でんじは", "でんき", @model.ParalyzeKind, 100)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  @debug.assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  @debug.assert_eq(s.opp_status[0], @model.Paralyze)
}

///|
/// Case G-2-E: Misty + ふうせん defender は grounded=false → 通常 fanout で
/// paralyze 付与。
test "maybe_apply_status_fanout: Misty field ふうせん defender takes status" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Misty, field_turns_left: 5 }
  let opp_team = [
    mk_field_eff_combatant(item="ふうせん"),
    mk_field_eff_combatant(),
  ]
  let mv = mk_status_move("でんじは", "でんき", @model.ParalyzeKind, 100)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  @debug.assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  @debug.assert_eq(s.opp_status[0], @model.Paralyze)
}

///|
/// Case G-2-F: Misty + grounded defender に対する 30% burn (おにび相当) でも
/// block される (1 leaf, no status)。確率分岐 (1-p, p) で 2 leaf 出さない。
test "maybe_apply_status_fanout: Misty field blocks 30% burn (no fanout branch)" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Misty, field_turns_left: 5 }
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let mv = mk_status_move("ひのこ", "ほのお", @model.BurnKind, 30)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  // Misty block: 1 leaf with original state, no probability split。
  @debug.assert_eq(leaves.length(), 1)
  let (p, s) = leaves[0]
  @debug.assert_eq(p, 1.0)
  @debug.assert_eq(s.opp_status[0], @model.None)
}

///|
/// Case G-2-G: Misty + grounded defender に対する Sleep 系も block される。
/// (まひ/やけど/どく/ねむり 全部 block の SSoT pin)。
test "maybe_apply_status_fanout: Misty field blocks Sleep" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Misty, field_turns_left: 5 }
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let mv = mk_status_move("ねむりごな", "くさ", @model.SleepKind, 75)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  @debug.assert_eq(leaves.length(), 1)
  let (p, s) = leaves[0]
  @debug.assert_eq(p, 1.0)
  @debug.assert_eq(s.opp_status[0], @model.None)
}

// =================================================================
// G-2-H (#143 review): Electric Terrain sleep block in
// maybe_apply_status_fanout
//
// エレキフィールドは grounded を「眠らせない」効果のみを持つため、ねむり
// (SleepKind) と あくび予告 (DrowsyKind) だけを阻止し、まひ / やけど / どく
// 等は通常通り入る。Misty (全状態阻止) との差分を pin する。grounded gate は
// Misty と同一経路 (`field_blocks_status` + `is_grounded`)。
// =================================================================

///|
/// Case G-2-H-A: エレキフィールド + grounded defender への 75% sleep 技は
/// 阻止される (1 leaf, no status — 確率分岐も出ない)。
test "maybe_apply_status_fanout: Electric field blocks Sleep on grounded defender" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Electric, field_turns_left: 5 }
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let mv = mk_status_move("ねむりごな", "くさ", @model.SleepKind, 75)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  @debug.assert_eq(leaves.length(), 1)
  let (p, s) = leaves[0]
  @debug.assert_eq(p, 1.0)
  @debug.assert_eq(s.opp_status[0], @model.None)
}

///|
/// Case G-2-H-B: エレキフィールド + grounded defender への あくび (Drowsy 予告)
/// も阻止される (Yawn は grounded を眠らせる予告なので Electric 下で fizzle)。
test "maybe_apply_status_fanout: Electric field blocks Drowsy (Yawn) on grounded defender" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Electric, field_turns_left: 5 }
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let mv = mk_status_move("あくび", "ノーマル", @model.DrowsyKind, 100)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  @debug.assert_eq(leaves.length(), 1)
  let (p, s) = leaves[0]
  @debug.assert_eq(p, 1.0)
  @debug.assert_eq(s.opp_status[0], @model.None)
}

///|
/// Case G-2-H-C: エレキフィールド + grounded defender でも paralyze は阻止
/// されない (Electric は sleep 限定)。でんじは 100% で Paralyze が付与される。
/// Misty (全状態阻止) との決定的な差分。
test "maybe_apply_status_fanout: Electric field does NOT block Paralyze on grounded defender" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Electric, field_turns_left: 5 }
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let mv = mk_status_move("でんじは", "でんき", @model.ParalyzeKind, 100)
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  @debug.assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  @debug.assert_eq(s.opp_status[0], @model.Paralyze)
}

///|
/// Case G-2-H-D: エレキフィールド + 非 grounded (ひこう) defender への sleep は
/// 阻止されない (Electric の sleep block は grounded 限定)。100% sleep 技で
/// Sleep(2) が付与される。
test "maybe_apply_status_fanout: Electric field does NOT block Sleep on airborne defender" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Electric, field_turns_left: 5 }
  let opp_team = [
    mk_field_eff_combatant(type1="ノーマル", type2="ひこう"),
    mk_field_eff_combatant(),
  ]
  let mv = mk_status_move(
    "ねむらせる",
    "エスパー",
    @model.SleepKind,
    100,
  )
  let leaves = maybe_apply_status_fanout(state, false, 0, opp_team, mv)
  @debug.assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  @debug.assert_eq(s.opp_status[0], @model.Sleep(2))
}

// =================================================================
// G-3: Psychic priority block in resolve_attacker_leg
//
// state.field == Psychic AND is_grounded(defender) AND mv.priority > 0 なら
// 攻撃自体が無効化される (damage=0, status 付与なし)。priority=0 / Field !=
// Psychic / 非 grounded defender では通常通り処理。
//
// `resolve_attacker_leg` は private なので、payoff の attacker_leg レベルを
// 通すために公開 API `transition_with_cache` 経由で 1 ターン回す。
// switching_game_status_wbtest と同じ流儀で `transition_with_cache` を呼ぶ。
// =================================================================

///|
/// Stage G-3 用 priority 技ヘルパー。しんそく相当 (priority=+2, ノーマル,
/// power=80, no status)。
fn mk_priority_move(
  name : String,
  type_ : String,
  priority : Int,
  power : Int,
) -> @model.Move {
  { ..mk_heal_move(name, type_, @model.Physical, power), priority, }
}

///|
/// 攻撃技と組ませる no-op 補助技 (じこさいせい相当)。HP=50 → 100 へ +50 回復
/// するため、priority block で attacker の damage が 0 のときに「opp_hps[0]≈100」
/// で確認できる。priority block が効かないと attacker の damage で opp_hps[0]
/// は < 100 になる (回復後でも damage が勝つよう power=80 にした)。
fn mk_recover_move() -> @model.Move {
  {
    ..mk_heal_move(
      "じこさいせい",
      "ノーマル",
      @model.Status,
      0,
      healing=Some(@model.FixedFraction(1, 2)),
    )
  }
}

///|
/// outcomes から (total_prob, expected opp_hps[0]) を集約。priority block の
/// 観測は「opp_hps[0] の期待値 ≥ 99.9」と「全 leaf で opp_status[0] == None」を
/// 同時に pin する形にする。
fn agg_outs(outs : Array[(Double, SwitchingGameState)]) -> (Double, Double) {
  let mut tp = 0.0
  let mut th = 0.0
  for b in outs {
    let (p, s) = b
    tp = tp + p
    th = th + p * s.opp_hps[0].to_double()
  }
  (tp, th)
}

///|
/// Case G-3-A: Psychic field 中、grounded defender に対する priority>0 攻撃
/// (しんそく) は無効化される: damage=0、defender HP は変化なし、defender
/// status も None のまま。
///
/// `transition_with_cache` を 1 ターン回し、最終 opp_hps[0] と
/// opp_status[0] を assert。priority block で my 側 しんそく が defender
/// (opp_active=0) に当たらない → opp 側 じこさいせい (priority=0) が後手で
/// +50 回復 → 期待値 opp_hps[0] ≈ 100。
///
/// 注意: transition_with_cache は末尾で apply_eot を呼ぶため Grassy heal が
/// 入りうるが、本 test は Psychic field なので Grassy heal は発火しない。
test "transition_with_cache: Psychic field blocks priority>0 attack (no damage / no status)" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Psychic, field_turns_left: 5 }
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let recover_mv = mk_recover_move()
  let my_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [
    mk_field_eff_combatant(moves=[recover_mv]),
    mk_field_eff_combatant(),
  ]
  let outs = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  // 全 leaf で opp_status[0] == None (priority block により status 付与なし)。
  for b in outs {
    let (_, s) = b
    @debug.assert_eq(s.opp_status[0], @model.None)
  }
  let (tp, th) = agg_outs(outs)
  assert_true(tp > 0.999 && tp < 1.001)
  // opp_hps[0] 期待値 ≈ 100 (damage 0 + recover +50)。
  assert_true(th > 99.9 && th < 100.1)
}

///|
/// Case G-3-B: Field == None なら priority block は発火せず、しんそく は
/// 通常通り damage を与える (defender HP < 100 へ)。
test "transition_with_cache: Field=None lets priority>0 attack proceed" {
  let state = mk_field_eff_state()
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let recover_mv = mk_recover_move()
  let my_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [
    mk_field_eff_combatant(moves=[recover_mv]),
    mk_field_eff_combatant(),
  ]
  let outs = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (tp, th) = agg_outs(outs)
  assert_true(tp > 0.999 && tp < 1.001)
  // priority block なし: しんそく の damage で opp_hps[0] 期待値 < 99.5。
  assert_true(th < 99.5)
}

///|
/// Case G-3-C: Psychic + ふゆう defender (grounded=false) → priority block
/// 不発、しんそく は通常 damage を与える。
test "transition_with_cache: Psychic field ふゆう defender takes priority>0 attack" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Psychic, field_turns_left: 5 }
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let recover_mv = mk_recover_move()
  let my_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [
    mk_field_eff_combatant(ability="ふゆう", moves=[recover_mv]),
    mk_field_eff_combatant(),
  ]
  let outs = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (tp, th) = agg_outs(outs)
  assert_true(tp > 0.999 && tp < 1.001)
  assert_true(th < 99.5)
}

///|
/// Case G-3-D: Psychic + grounded defender だが priority=0 の通常技 (たいあたり)
/// は block されず通常 damage。
test "transition_with_cache: Psychic field priority=0 move proceeds normally" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Psychic, field_turns_left: 5 }
  let normal_mv = mk_priority_move("たいあたり", "ノーマル", 0, 40)
  let recover_mv = mk_recover_move()
  let my_team = [
    mk_field_eff_combatant(moves=[normal_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [
    mk_field_eff_combatant(moves=[recover_mv]),
    mk_field_eff_combatant(),
  ]
  let outs = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (tp, th) = agg_outs(outs)
  assert_true(tp > 0.999 && tp < 1.001)
  // priority=0 → Psychic block 対象外、damage 入る。
  assert_true(th < 99.5)
}

///|
/// Case G-3-E: Psychic + ひこう defender → grounded=false で priority block
/// 不発。ノーマル → ひこう は immune ではないので damage 入る。
test "transition_with_cache: Psychic field ひこう defender takes priority>0 attack" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Psychic, field_turns_left: 5 }
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let recover_mv = mk_recover_move()
  let my_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [
    mk_field_eff_combatant(type1="ノーマル", type2="ひこう", moves=[
      recover_mv,
    ]),
    mk_field_eff_combatant(),
  ]
  let outs = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (tp, th) = agg_outs(outs)
  assert_true(tp > 0.999 && tp < 1.001)
  assert_true(th < 99.5)
}

///|
/// Case G-3-F: Psychic + ふうせん defender → grounded=false で priority block
/// 不発、damage 入る。
test "transition_with_cache: Psychic field ふうせん defender takes priority>0 attack" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Psychic, field_turns_left: 5 }
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let recover_mv = mk_recover_move()
  let my_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [
    mk_field_eff_combatant(item="ふうせん", moves=[recover_mv]),
    mk_field_eff_combatant(),
  ]
  let outs = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let (tp, th) = agg_outs(outs)
  assert_true(tp > 0.999 && tp < 1.001)
  assert_true(th < 99.5)
}

///|
/// Case G-3-G (#143 review): Switch-vs-UseMove DP path も Psychic-priority
/// guard を funnel する。my が slot 1 (grounded) へ交代、opp が priority>0
/// (しんそく) で switch-in を狙う → Psychic 下では無効化され my_hps[1] は不変。
/// guard が switch path を bypass していた回帰を pin する。
test "transition_with_cache: Psychic blocks opp priority>0 vs my grounded switch-in" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Psychic, field_turns_left: 5 }
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let my_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let opp_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let outs = transition_with_cache(
    state,
    Switch(1),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let mut tp = 0.0
  for b in outs {
    let (p, s) = b
    tp = tp + p
    // priority block: switch-in (my_active=1) は damage を受けない。
    @debug.assert_eq(s.my_hps[1], 50)
  }
  assert_true(tp > 0.999 && tp < 1.001)
}

///|
/// Case G-3-H: Switch-vs-UseMove で Field==None なら guard 不発、opp の
/// priority 技は switch-in に通る (my_hps[1] < 50)。G-3-G の対照。
test "transition_with_cache: Field=None lets opp priority>0 hit my switch-in" {
  let state = mk_field_eff_state()
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let my_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let opp_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let outs = transition_with_cache(
    state,
    Switch(1),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let mut tp = 0.0
  let mut th = 0.0
  for b in outs {
    let (p, s) = b
    tp = tp + p
    th = th + p * s.my_hps[1].to_double()
  }
  assert_true(tp > 0.999 && tp < 1.001)
  assert_true(th < 49.5)
}

///|
/// Case G-3-I (#143 review): 逆方向 — my が priority>0 で opp の grounded
/// switch-in (slot 1) を狙う。UseMove-vs-Switch path も guard を funnel し、
/// Psychic 下では opp_hps[1] が不変。
test "transition_with_cache: Psychic blocks my priority>0 vs opp grounded switch-in" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, field: @model.Field::Psychic, field_turns_left: 5 }
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let my_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let outs = transition_with_cache(
    state,
    UseMove(0),
    Switch(1),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let mut tp = 0.0
  for b in outs {
    let (p, s) = b
    tp = tp + p
    @debug.assert_eq(s.opp_hps[1], 50)
  }
  assert_true(tp > 0.999 && tp < 1.001)
}

///|
/// Case G-3-J: UseMove-vs-Switch で Field==None なら guard 不発、my の
/// priority 技は opp switch-in に通る (opp_hps[1] < 50)。G-3-I の対照。
test "transition_with_cache: Field=None lets my priority>0 hit opp switch-in" {
  let state = mk_field_eff_state()
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let my_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [mk_field_eff_combatant(), mk_field_eff_combatant()]
  let outs = transition_with_cache(
    state,
    UseMove(0),
    Switch(1),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let mut tp = 0.0
  let mut th = 0.0
  for b in outs {
    let (p, s) = b
    tp = tp + p
    th = th + p * s.opp_hps[1].to_double()
  }
  assert_true(tp > 0.999 && tp < 1.001)
  assert_true(th < 49.5)
}

///|
/// Case G-3-K (#143 review): partial-act path (相手が眠りで skip) も guard を
/// funnel する。opp が Sleep(2) で行動不能、my が priority>0 (しんそく) で opp の
/// grounded active を狙う → Psychic 下では opp_hps[0] 不変。Sleep(n>0) は
/// prob 1.0 / acts=false なので partial_act_outcomes が決定的に走る。
test "attempt_turn_with_cache: Psychic blocks my priority>0 vs sleeping grounded opp (partial act)" {
  let state0 = mk_field_eff_state()
  let state = {
    ..state0,
    field: @model.Field::Psychic,
    field_turns_left: 5,
    opp_status: [@model.Sleep(2), @model.None],
  }
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let my_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [
    mk_field_eff_combatant(moves=[mk_recover_move()]),
    mk_field_eff_combatant(),
  ]
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let mut tp = 0.0
  for b in outs {
    let (p, s) = b
    tp = tp + p
    @debug.assert_eq(s.opp_hps[0], 50)
  }
  assert_true(tp > 0.999 && tp < 1.001)
}

///|
/// Case G-3-L: partial-act で Field==None なら guard 不発、my の priority 技は
/// 眠っている opp active に通る (opp_hps[0] < 50)。G-3-K の対照。
test "attempt_turn_with_cache: Field=None lets my priority>0 hit sleeping opp (partial act)" {
  let state0 = mk_field_eff_state()
  let state = { ..state0, opp_status: [@model.Sleep(2), @model.None] }
  let priority_mv = mk_priority_move("しんそく", "ノーマル", 2, 80)
  let my_team = [
    mk_field_eff_combatant(moves=[priority_mv]),
    mk_field_eff_combatant(),
  ]
  let opp_team = [
    mk_field_eff_combatant(moves=[mk_recover_move()]),
    mk_field_eff_combatant(),
  ]
  let outs = attempt_turn_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let mut tp = 0.0
  let mut th = 0.0
  for b in outs {
    let (p, s) = b
    tp = tp + p
    th = th + p * s.opp_hps[0].to_double()
  }
  assert_true(tp > 0.999 && tp < 1.001)
  assert_true(th < 49.5)
}
