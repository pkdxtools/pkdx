///|
/// そうしょく (Sap Sipper) の DP 経路テスト。Showdown の `onTryHit` が null を返す
/// (技は当たらない) 挙動に合わせる:
///
///   - 相手のくさタイプ技 (攻撃・変化) は防御側に当たらない。HP / 状態異常 / 寄生 /
///     回復 / 相手へのランク変化 / 自分へのランク変化 / 接触 proc は一切起きない。
///   - 防御側の A が +1 される (+6 で頭打ち。吸収自体は起きる)。
///   - 命中判定より前に吸収するので、命中率が低い技でも外れ枝は出ない (単一 leaf)。
///   - ねをはる / こうごうせい / せいちょう / コットンガード / ニードルガード /
///     グラスフィールド / アロマセラピー / ジャングルヒール は相手を狙わないので吸収されない。
///   - 防御側が吸収しない技 (くさ以外 / 別特性) は従来どおり。
///   - Protean / Libero は技を使った時点でタイプが変わる (Showdown `PrepareHit` は
///     `TryHit` より前) ので、吸収された技でも固定を記録する。
///
/// helper: `mk_move` (switching_game_status_wbtest)、`im_pokemon` / `im_combatant` /
/// `im_state` / `im_tackle` (switching_game_intimidate_wbtest)。

///|
fn sap_leaf_blade() -> @model.Move {
  mk_move("リーフブレード", "くさ", @model.Physical, 90)
}

///|
fn sap_spore() -> @model.Move {
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
fn sap_holder_team() -> Array[Combatant] {
  [im_combatant(im_pokemon("Holder"), [im_tackle()], ability="そうしょく")]
}

///|
fn sap_plain_team() -> Array[Combatant] {
  [im_combatant(im_pokemon("Plain"), [im_tackle()])]
}

///|
fn sap_team(mv : @model.Move, ability? : String = "") -> Array[Combatant] {
  [im_combatant(im_pokemon("Attacker"), [mv], ability=ability)]
}

///|
/// Run one outcome (`mean_damage`, probability 1.0, one hit) through the
/// post-hit fanout and return the single resulting state. The fanout is
/// `apply_damage_variants_fanout`, the function the DP attack site calls.
fn sap_one_leaf(
  state : SwitchingGameState,
  attacker_is_me : Bool,
  attacker_team : Array[Combatant],
  defender_team : Array[Combatant],
  mv : @model.Move,
  mean_damage : Int,
) -> SwitchingGameState {
  let outs = apply_damage_variants_fanout(
    state,
    [{ probability: 1.0, mean_damage, hits_count: 1, hit_steps: [] }],
    attacker_is_me=attacker_is_me,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=attacker_team,
    defender_team=defender_team,
    pre_dmg_defender_hp=100,
  )
  if outs.length() != 1 {
    abort("sap_one_leaf: expected a single leaf")
  }
  outs[0].1
}

///|
/// **Case 1 (くさ攻撃技の吸収)**: 相手 (そうしょく) への リーフブレード は当たらず、
/// 防御側 HP は不変、防御側 A が +1。自分の HP も変わらない。
test "そうしょく: くさ技は当たらず防御側の A が +1 (HP 不変)" {
  let s = sap_one_leaf(
    im_state(),
    true,
    sap_team(sap_leaf_blade()),
    sap_holder_team(),
    sap_leaf_blade(),
    60,
  )
  @debug.assert_eq(s.opp_hps[0], 100)
  @debug.assert_eq(s.my_hps[0], 100)
  @debug.assert_eq(s.opp_ranks[0], 1)
  @debug.assert_eq(s.my_ranks[0], 0)
}

///|
/// **Case 2 (くさ状態技の吸収)**: ねむりごな (命中 75・眠り 100%) は眠らせず、A +1。
test "そうしょく: ねむりごなは眠らせず防御側の A が +1" {
  let s = sap_one_leaf(
    im_state(),
    true,
    sap_team(sap_spore()),
    sap_holder_team(),
    sap_spore(),
    0,
  )
  @debug.assert_eq(s.opp_status[0], @model.None)
  @debug.assert_eq(s.opp_ranks[0], 1)
}

///|
/// **Case 3 (やどりぎのタネ)**: 吸収されるので植え付けられず、A +1。
test "そうしょく: やどりぎのタネは植え付けられず防御側の A が +1" {
  let seed = {
    ..mk_move("やどりぎのタネ", "くさ", @model.Status, 0, accuracy=90),
    healing: Some(@model.LeechSeed),
  }
  let s = sap_one_leaf(im_state(), true, sap_team(seed), sap_holder_team(), seed, 0)
  @debug.assert_eq(s.opp_leech_seeded[0], false)
  @debug.assert_eq(s.opp_ranks[0], 1)
}

///|
/// **Case 4 (わたほうし)**: 相手の素早さ -2 (相手ダウン) は吸収で発生しない。
/// 防御側の A のみ +1。
test "そうしょく: わたほうしの相手素早さダウンは発生せず A が +1" {
  let cotton = mk_move(
    "わたほうし",
    "くさ",
    @model.Status,
    0,
    stat_effects=[@model.StatEffect::{ stat: 4, delta: -2, target: 1 }],
  )
  let s = sap_one_leaf(im_state(), true, sap_team(cotton), sap_holder_team(), cotton, 0)
  @debug.assert_eq(s.opp_ranks[4], 0)
  @debug.assert_eq(s.opp_ranks[0], 1)
}

///|
/// **Case 5 (リーフストームの自己ダウン)**: 吸収された技は当たらないので、使用者の
/// とくこう -2 は起きない。使用者が あまのじゃく でも同じ (反転すべき効果がない)。
test "そうしょく: リーフストームの自己ダウンは発生しない (あまのじゃく使用者も同じ)" {
  let storm = mk_move(
    "リーフストーム",
    "くさ",
    @model.Special,
    130,
    stat_effects=[@model.StatEffect::{ stat: 2, delta: -2, target: 0 }],
  )
  for ability in ["", "あまのじゃく"] {
    let s = sap_one_leaf(
      im_state(),
      true,
      sap_team(storm, ability=ability),
      sap_holder_team(),
      storm,
      60,
    )
    @debug.assert_eq(s.my_ranks[2], 0)
    @debug.assert_eq(s.opp_ranks[0], 1)
    @debug.assert_eq(s.opp_hps[0], 100)
  }
}

///|
/// **Case 6 (自分を狙うくさ技は吸収されない)**: コットンガード (自分の防御 +3) は
/// 相手に当たらないので従来どおり自分の防御が上がり、相手の A は変わらない。
test "そうしょく: 自分を狙うくさ技 (コットンガード) は吸収されず自己効果が出る" {
  let cotton_guard = mk_move(
    "コットンガード",
    "くさ",
    @model.Status,
    0,
    stat_effects=[@model.StatEffect::{ stat: 1, delta: 3, target: 0 }],
  )
  let s = sap_one_leaf(
    im_state(),
    true,
    sap_team(cotton_guard),
    sap_holder_team(),
    cotton_guard,
    0,
  )
  @debug.assert_eq(s.my_ranks[1], 2)
  @debug.assert_eq(s.opp_ranks[0], 0)
}

///|
/// **Case 7 (グラスフィールド)**: フィールドを張る技は相手に当たらない。吸収されず
/// フィールドが張られ、相手の A は変わらない。
test "そうしょく: グラスフィールドは吸収されずフィールドを張る" {
  let terrain = {
    ..mk_move("グラスフィールド", "くさ", @model.Status, 0),
    field_set: Some(@model.Grassy),
  }
  let s = sap_one_leaf(
    im_state(),
    true,
    sap_team(terrain),
    sap_holder_team(),
    terrain,
    0,
  )
  @debug.assert_eq(s.field, @model.Grassy)
  @debug.assert_eq(s.opp_ranks[0], 0)
}

///|
/// **Case 8 (くさ以外の技)**: たいあたり (ノーマル) は吸収されず、通常どおり当たる。
test "そうしょく: くさ以外の技は吸収されず通常どおり当たる" {
  let s = sap_one_leaf(
    im_state(),
    true,
    sap_team(im_tackle()),
    sap_holder_team(),
    im_tackle(),
    60,
  )
  @debug.assert_eq(s.opp_hps[0], 40)
  @debug.assert_eq(s.opp_ranks[0], 0)
}

///|
/// **Case 9 (なきごえは吸収されない)**: 相手の なきごえ (A -1) はくさ技ではないので
/// 吸収されず、そうしょく の A が -1 される (full-range 追跡でも 0 から -1)。
test "そうしょく: なきごえ (ノーマル変化) は吸収されず A が -1 される" {
  let growl = mk_move(
    "なきごえ",
    "ノーマル",
    @model.Status,
    0,
    stat_effects=[@model.StatEffect::{ stat: 0, delta: -1, target: 1 }],
  )
  let s = sap_one_leaf(im_state(), true, sap_team(growl), sap_holder_team(), growl, 0)
  @debug.assert_eq(s.opp_ranks[0], -1)
}

///|
/// **Case 10 (+6 で頭打ち)**: A が既に +6 でも吸収自体は起き、HP は変わらない。
/// ランクは +6 のまま。
test "そうしょく: A が +6 でも吸収は起きるがランクは +6 のまま" {
  let s = sap_one_leaf(
    { ..im_state(), opp_ranks: [6, 0, 0, 0, 0] },
    true,
    sap_team(sap_leaf_blade()),
    sap_holder_team(),
    sap_leaf_blade(),
    60,
  )
  @debug.assert_eq(s.opp_ranks[0], 6)
  @debug.assert_eq(s.opp_hps[0], 100)
}

///|
/// **Case 11 (±6 追跡)**: 通常特性は ±2 で頭打ちだが、そうしょく は +6 まで積み上がる。
/// 3 回吸収すると A は +3 (±2 に丸められていれば +2 になる)。
test "そうしょく: 吸収の +1 は ±2 ではなく +6 まで積み上がる" {
  let mut s = im_state()
  for _i in 0..<3 {
    s = sap_one_leaf(s, true, sap_team(sap_leaf_blade()), sap_holder_team(), sap_leaf_blade(), 60)
  }
  @debug.assert_eq(s.opp_ranks[0], 3)
}

///|
/// **Case 12 (Protean / Libero の固定)**: 吸収された くさ技 でも、へんげんじざい は
/// 技を使った時点で くさ に固定される (PrepareHit は TryHit より前)。
test "そうしょく: 吸収された技でも へんげんじざい の固定は記録される" {
  let s = sap_one_leaf(
    im_state(),
    true,
    sap_team(sap_leaf_blade(), ability="へんげんじざい"),
    sap_holder_team(),
    sap_leaf_blade(),
    60,
  )
  @debug.assert_eq(s.my_protean_locked[0], "くさ")
  @debug.assert_eq(s.opp_ranks[0], 1)
}

///|
/// **Case 13 (防御側が くさ技を使う)**: 吸収特性の持ち主自身の くさ技は、相手側の
/// 防御側に対して通常どおり当たる (持ち主の技は吸収されない)。
test "そうしょく: 持ち主自身のくさ技は吸収されず相手に当たる" {
  let s = sap_one_leaf(
    im_state(),
    false,
    sap_team(sap_leaf_blade(), ability="そうしょく"),
    sap_plain_team(),
    sap_leaf_blade(),
    60,
  )
  @debug.assert_eq(s.my_hps[0], 40)
  @debug.assert_eq(s.opp_ranks[0], 0)
}

///|
/// **Case 14 (命中の固定)**: 命中率 75 の ねむりごな は、そうしょく に対しては
/// 命中率 100 として扱われる (外れ枝なし)。通常の防御側では 75 のまま。
test "そうしょく: 吸収対象の技は命中率 100 として扱う (外れ枝なし)" {
  let mine = sap_team(sap_spore())
  let st = im_state()
  @debug.assert_eq(
    attempt_accuracy(st, ActionKind::UseMove(0), true, mine, sap_holder_team()),
    100,
  )
  @debug.assert_eq(
    attempt_accuracy(st, ActionKind::UseMove(0), true, mine, sap_plain_team()),
    75,
  )
}

///|
/// (相手の素早さは 60 にして、同速による 50/50 の行動順の分岐を避ける。)
/// **Case 15 (ターン解決の統合)**: 両者が行動する 1 ターンを `attempt_turn_with_cache`
/// で解決する。リーフブレード は吸収され、相手のはねるは効果なし。結果は単一 leaf で
/// 確率 1.0、防御側 A +1、HP 不変。
test "そうしょく: 1 ターン解決 (attempt_turn_with_cache) で単一 leaf・A +1" {
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let opp = [im_combatant(im_pokemon("Holder", spe=60), [splash], ability="そうしょく")]
  let outs = attempt_turn_with_cache(
    im_state(),
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    sap_team(sap_leaf_blade()),
    opp,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (p, s) = outs[0]
  @debug.assert_eq(p, 1.0)
  @debug.assert_eq(s.opp_ranks[0], 1)
  @debug.assert_eq(s.opp_hps[0], 100)
  @debug.assert_eq(s.my_hps[0], 100)
}

///|
/// **Case 16 (命中率が低い状態技を 1 ターン解決)**: 命中 75 の ねむりごな でも
/// 外れ枝は出ず、単一 leaf (確率 1.0)。眠らず、A +1。対照として、そうしょく で
/// ない相手には 命中 75 の 2 枝 (当たり / 外れ) が出る。
test "そうしょく: 命中 75 の状態技も 1 ターンで単一 leaf (外れ枝なし)" {
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let opp = [im_combatant(im_pokemon("Holder", spe=60), [splash], ability="そうしょく")]
  let outs = attempt_turn_with_cache(
    im_state(),
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    sap_team(sap_spore()),
    opp,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (p, s) = outs[0]
  @debug.assert_eq(p, 1.0)
  @debug.assert_eq(s.opp_status[0], @model.None)
  @debug.assert_eq(s.opp_ranks[0], 1)
  let plain_opp = [im_combatant(im_pokemon("Plain", spe=60), [splash])]
  let plain_outs = attempt_turn_with_cache(
    im_state(),
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    sap_team(sap_spore()),
    plain_opp,
    new_damage_cache(),
  )
  @debug.assert_eq(plain_outs.length(), 2)
}
