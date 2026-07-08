///|
/// ばけのかわ (Disguise, ミミッキュ専用) の SwitchingGame DP 実装 wbtest。
///
/// 本家仕様 (Bulbapedia 検証済み):
///   - 最初の**ダメージ技**の被弾を無効化、代わりに 最大HP/8 (床) の chip で剥がれる
///   - 1 戦闘 1 回のみ。交代しても回復しない (Switch でリセットしない)
///   - 連続技は初段のみブロック (2 段目以降通る)。変化技 / タイプ無効では剥がれない
///   - ブロックされた被弾でもダメージ 0 なので反動 (recoil) / ドレイン回復は発生しない
///
/// 検証は transition_with_cache (DP 統合) + compute/mean_damage helper (cache/
/// transform 単体) の両面で行う。

///|
/// ミミッキュ相当 defender: ゴースト / フェアリー, ばけのかわ。actual_stats で
/// HP を明示 (chip = HP/8 を可視化するため H=131 → chip=16)。ノーマル / かくとう
/// は immune、ドラゴンは (フェアリーで) immune。damage transform を見るには
/// みず / こおり 等の中立技を撃つ。
fn sgd_mimikyu(
  hp? : Int = 131,
  ability? : String = "ばけのかわ",
  spe? : Int = 50,
  mv? : @model.Move = sgd_move(
    "ゴースト0power",
    power=0,
    type_="ゴースト",
  ),
) -> Combatant {
  let pkm : @model.Pokemon = {
    global_no: "0778",
    name_ja: "ミミッキュ",
    name_en: "Mimikyu",
    type1: "ゴースト",
    type2: "フェアリー",
    hp,
    atk: 90,
    def_: 80,
    spa: 50,
    spd: 105,
    spe,
    bst: 476,
    ability1: ability,
    ability2: "",
    dream_ability: "",
    weight: 0.7,
    forms: [],
  }
  {
    pokemon: pkm,
    moves: [mv],
    ability,
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([hp, 90, 80, 50, 105, spe]),
    ivs: None,
  }
}

///|
fn sgd_move(
  name : String,
  power? : Int = 100,
  accuracy? : Int = 100,
  category? : @model.MoveCategory = @model.Physical,
  type_? : String = "みず",
  recoil_num? : Int = 0,
  recoil_den? : Int = 1,
  healing? : @model.HealingEffect? = None,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
    accuracy,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num,
    recoil_den,
    self_ko: false,
    recharge: false,
    healing,
    weather_set: None,
    field_set: None,
  }
}

///|
/// 攻撃側: 単発物理 みず技 (中立)。spe を高くして my_first を確定させる。
fn sgd_attacker(
  mv : @model.Move,
  spe? : Int = 200,
  hp? : Int = 300,
) -> Combatant {
  let pkm : @model.Pokemon = {
    global_no: "0000",
    name_ja: "attacker",
    name_en: "attacker",
    type1: "みず",
    type2: "",
    hp,
    atk: 120,
    def_: 80,
    spa: 120,
    spd: 80,
    spe,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
  {
    pokemon: pkm,
    moves: [mv],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([hp, 120, 80, 120, 80, spe]),
    ivs: None,
  }
}

///|
/// 1v1 初期 state。opp_disguise_busted を明示指定して intact / busted を切り替える。
fn sgd_state(
  my_hp : Int,
  opp_hp : Int,
  opp_busted? : Bool = false,
) -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [my_hp],
    opp_hps: [opp_hp],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false],
    opp_megaed: [false],
    my_status: [@model.None],
    opp_status: [@model.None],
    my_must_recharge: [false],
    opp_must_recharge: [false],
    my_item_consumed: [false],
    opp_item_consumed: [false],
    my_disguise_busted: [false],
    opp_disguise_busted: [opp_busted],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false],
    opp_leech_seeded: [false],
    my_protean_locked: [""],
    opp_protean_locked: [""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
/// (1) intact への単発物理: leaf の opp HP 減少 == chip (= effective_hp/8) のみ、
///     leaf state の opp_disguise_busted[0] == true。
test "disguise: intact single physical → chip only + busted flag set" {
  let mimikyu = sgd_mimikyu()
  let attacker = sgd_attacker(sgd_move("みずのは", power=100))
  let start_opp = 30000
  let state = sgd_state(30000, start_opp)
  let leaves = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    [attacker],
    [mimikyu],
    new_damage_cache(),
  )
  let chip = effective_hp(mimikyu) / 8
  assert_true(chip > 0)
  assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  // 単発技はブロックされ chip のみ削れる。
  assert_eq(start_opp - s.opp_hps[0], chip)
  // 剥がれフラグが立つ。
  assert_true(s.opp_disguise_busted[0])
}

///|
/// (2) busted 状態 (フラグ true) への同技: フルダメージ、追加 chip なし。
test "disguise: busted → full damage, no extra chip" {
  let mimikyu = sgd_mimikyu()
  let attacker = sgd_attacker(sgd_move("みずのは", power=100))
  let start_opp = 30000
  let state = sgd_state(30000, start_opp, opp_busted=true)
  let leaves = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    [attacker],
    [mimikyu],
    new_damage_cache(),
  )
  let chip = effective_hp(mimikyu) / 8
  assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  let dealt = start_opp - s.opp_hps[0]
  // busted はフルダメージ。中立 power100 みず技なので chip (=16) より遥かに大きい。
  assert_true(dealt > chip)
  // 期待値 = 非 intact の mean_damage_cached と bit 一致。
  let expected = mean_damage_cached(
    new_damage_cache(),
    true,
    0,
    [0, 0, 0, 0, 0],
    0,
    [0, 0, 0, 0, 0],
    0,
    [attacker],
    [mimikyu],
    def_disguise_intact=false,
  )
  assert_eq(dealt, expected)
}

///|
/// (3) 連続技 (つららばり = Random2to5) intact: 各 variant mean ==
///     disguise_reduced_mean(engine variant, chip) と bit 一致。leaf 数も pin。
test "disguise: multi-hit intact → chip + later-hits mean per variant" {
  let mimikyu = sgd_mimikyu()
  let mv = sgd_move("つららばり", power=25, type_="こおり")
  let attacker = sgd_attacker(mv)
  // 直接 compute_damage_variants を intact / non-intact で叩き、engine 生 variant
  // から手計算した期待値と照合する (transform の white-box pin)。
  let atk_rank = 0
  let def_rank = 0
  let vt = compute_damage_variants(
    attacker,
    mimikyu,
    mv,
    atk_rank,
    def_rank,
    def_disguise_intact=true,
  )
  let vf = compute_damage_variants(
    attacker,
    mimikyu,
    mv,
    atk_rank,
    def_rank,
    def_disguise_intact=false,
  )
  let r = @damage.calc_damage(
    build_input_with_ranks(attacker, mimikyu, mv, atk_rank, def_rank),
  )
  let chip = r.defender_hp / 8
  // Random2to5 → 4 variants。intact / non-intact で variant 数は不変。
  assert_eq(vt.length(), r.variants.length())
  assert_eq(vf.length(), r.variants.length())
  assert_true(vt.length() >= 2)
  for k = 0; k < vt.length(); k = k + 1 {
    let expected = disguise_reduced_mean(
      r.variants[k],
      mv.category,
      false,
      chip,
    )
    // transform の white-box pin: intact variant mean == chip + (全ヒット16平均
    //  - 初段16平均)。これが本テストの核心。
    assert_eq(vt[k].mean_damage, expected)
    // chip は必ず含まれる (reduced/16 >= 0 なので mean >= chip)。
    assert_true(vt[k].mean_damage >= chip)
    // non-intact は chip も初段減算もない素の全ヒット mean。
    let raw_full = {
      let mut s = 0
      for j = 0; j < r.variants[k].total_damages.length(); j = j + 1 {
        s = s + r.variants[k].total_damages[j]
      }
      s / 16
    }
    assert_eq(vf[k].mean_damage, raw_full)
  }
}

///|
/// (4) 変化技 (power=0) intact: chip なし・busted 立たず。
test "disguise: status move (power 0) → no chip, no bust" {
  let mimikyu = sgd_mimikyu()
  let attacker = sgd_attacker(sgd_move("へんかわざ", power=0))
  let start_opp = 30000
  let state = sgd_state(30000, start_opp)
  let leaves = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    [attacker],
    [mimikyu],
    new_damage_cache(),
  )
  assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  assert_eq(s.opp_hps[0], start_opp)
  assert_true(!s.opp_disguise_busted[0])
}

///|
/// (5) タイプ無効 (ノーマル技 → ゴースト): ダメージ 0・chip なし・busted 立たず。
test "disguise: type-immune move → 0 damage, no chip, no bust" {
  let mimikyu = sgd_mimikyu()
  let attacker = sgd_attacker(
    sgd_move("たいあたり", power=100, type_="ノーマル"),
  )
  let start_opp = 30000
  let state = sgd_state(30000, start_opp)
  let leaves = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    [attacker],
    [mimikyu],
    new_damage_cache(),
  )
  assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  assert_eq(s.opp_hps[0], start_opp)
  assert_true(!s.opp_disguise_busted[0])
}

///|
/// (6) 交代往復後も busted 持続: busted=true の状態で Switch→別スロット→戻る で
///     busted が true のまま (Switch arm がリセットしないことの検証)。
test "disguise: busted flag persists across switch round-trip" {
  let mimikyu = sgd_mimikyu()
  let bench = sgd_mimikyu(ability="", spe=60)
  let attacker = sgd_attacker(sgd_move("へんかわざ", power=0))
  // opp_team = [ミミッキュ(busted), 控え]。opp_active=0, busted[0]=true。
  let state : SwitchingGameState = {
    ..sgd_state(30000, 30000, opp_busted=true),
    opp_hps: [30000, 30000],
    opp_megaed: [false, false],
    opp_status: [@model.None, @model.None],
    opp_must_recharge: [false, false],
    opp_item_consumed: [false, false],
    opp_disguise_busted: [true, false],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
  }
  // ターン1: opp が控えへ交代。
  let l1 = transition_with_cache(
    state,
    UseMove(0),
    Switch(1),
    [attacker],
    [mimikyu, bench],
    new_damage_cache(),
  )
  assert_eq(l1.length(), 1)
  let (_, s1) = l1[0]
  assert_eq(s1.opp_active, 1)
  // 交代しても slot0 の busted は保持される。
  assert_true(s1.opp_disguise_busted[0])
  // ターン2: opp が ミミッキュ (slot0) に戻る。
  let l2 = transition_with_cache(
    s1,
    UseMove(0),
    Switch(0),
    [attacker],
    [mimikyu, bench],
    new_damage_cache(),
  )
  assert_eq(l2.length(), 1)
  let (_, s2) = l2[0]
  assert_eq(s2.opp_active, 0)
  // 戻ってきても busted のまま (交代で回復しない本家仕様)。
  assert_true(s2.opp_disguise_busted[0])
}

///|
/// (7) 反動技 (recoil) を intact へ: attacker HP 減少なし (dmg_for_effects=0 →
///     recoil 0)、defender は chip 分のみ減。
test "disguise: recoil move blocked → no recoil, defender loses chip only" {
  let mimikyu = sgd_mimikyu()
  let mv = sgd_move(
    "すてみタックル",
    power=120,
    recoil_num=1,
    recoil_den=3,
  )
  let attacker = sgd_attacker(mv)
  let start_my = 300
  let start_opp = 30000
  let state = sgd_state(start_my, start_opp)
  let leaves = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    [attacker],
    [mimikyu],
    new_damage_cache(),
  )
  let chip = effective_hp(mimikyu) / 8
  assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  // 反動なし: attacker HP 不変。
  assert_eq(s.my_hps[0], start_my)
  // defender は chip のみ。
  assert_eq(start_opp - s.opp_hps[0], chip)
  assert_true(s.opp_disguise_busted[0])
}

///|
/// (8) ドレイン技 (Drain) を intact へ: attacker 回復 0。
test "disguise: drain move blocked → attacker heals 0" {
  let mimikyu = sgd_mimikyu()
  let mv = sgd_move(
    "きゅうけつ",
    power=80,
    healing=Some(@model.Drain(1, 2)),
  )
  let attacker = sgd_attacker(mv)
  // attacker を最大 HP 未満に置き、回復余地を作る。
  let start_my = 100
  let start_opp = 30000
  let state = sgd_state(start_my, start_opp)
  let leaves = transition_with_cache(
    state,
    UseMove(0),
    UseMove(0),
    [attacker],
    [mimikyu],
    new_damage_cache(),
  )
  assert_eq(leaves.length(), 1)
  let (_, s) = leaves[0]
  // ブロックされたので実ダメージ 0 → ドレイン回復 0。
  assert_eq(s.my_hps[0], start_my)
  assert_true(s.opp_disguise_busted[0])
}

///|
/// (9) L1 cache alias 防止: 同一 (attacker,defender,move,ranks) で
///     def_disguise_intact=true / false が異なる mean を返す。
test "disguise: L1 cache key separates intact vs busted" {
  let mimikyu = sgd_mimikyu()
  let attacker = sgd_attacker(sgd_move("みずのは", power=100))
  let cache = new_damage_cache()
  let mean_intact = mean_damage_cached(
    cache,
    true,
    0,
    [0, 0, 0, 0, 0],
    0,
    [0, 0, 0, 0, 0],
    0,
    [attacker],
    [mimikyu],
    def_disguise_intact=true,
  )
  let mean_busted = mean_damage_cached(
    cache,
    true,
    0,
    [0, 0, 0, 0, 0],
    0,
    [0, 0, 0, 0, 0],
    0,
    [attacker],
    [mimikyu],
    def_disguise_intact=false,
  )
  // intact はブロック + chip、busted はフルダメージ。別 key なので shadow しない。
  assert_true(mean_intact != mean_busted)
  let chip = effective_hp(mimikyu) / 8
  assert_eq(mean_intact, chip)
  assert_true(mean_busted > chip)
  // variants cache 側でも同様に分離される。
  let vt = damage_variants_cached(
    cache,
    true,
    0,
    [0, 0, 0, 0, 0],
    0,
    [0, 0, 0, 0, 0],
    0,
    [attacker],
    [mimikyu],
    def_disguise_intact=true,
  )
  let vf = damage_variants_cached(
    cache,
    true,
    0,
    [0, 0, 0, 0, 0],
    0,
    [0, 0, 0, 0, 0],
    0,
    [attacker],
    [mimikyu],
    def_disguise_intact=false,
  )
  assert_eq(vt[0].mean_damage, chip)
  assert_true(vf[0].mean_damage > chip)
}

///|
/// (10) value-level: ばけのかわ 持ち defender の winrate value は ability="" 版より
///      my (攻撃) 側にとって不利方向 (= disguise が defender を助ける)。
test "disguise: winrate value favors the disguise holder" {
  // 攻撃側は 1 発で確殺 (power 300 みず、mimikyu Def 80)。turn_limit=1 で:
  //   - ばけのかわ なし → 初撃で確殺 → opp 全滅 → terminal_value = +1.0
  //   - ばけのかわ あり → 初撃はブロック (chip のみ) → mimikyu 生存 → turn 到達で
  //     HP マージン評価 (< 1.0)。よって disguise 側の方が my (攻撃) 側に不利。
  let attacker = sgd_attacker(
    sgd_move("だいふんげき", power=300),
    spe=200,
    hp=200,
  )
  let counter = sgd_move(
    "エナジーボール",
    power=90,
    category=@model.Special,
    type_="くさ",
  )
  let mimikyu = sgd_mimikyu(hp=120, spe=100, mv=counter)
  let no_disguise = sgd_mimikyu(hp=120, ability="", spe=100, mv=counter)
  let v_disguise = switching_game_winrate([attacker], [mimikyu], 1)
  let v_plain = switching_game_winrate([attacker], [no_disguise], 1)
  // ばけのかわ が defender を 1 発分守るので、my 側 value は下がる。
  // 実測: v_plain=+1.0 (確殺で opp 全滅)、v_disguise≈-0.055 (mimikyu 生存 →
  // HP マージンが defender 有利)。
  assert_true(v_disguise < v_plain)
  // 具体値: plain は確殺で +1.0。
  assert_eq(v_plain, 1.0)
}

///|
/// (回帰: codex review 指摘) 反射技が 0 ダメージ (相手のタイプ無効) のとき、
/// intact な ばけのかわ は剥がれず chip も受けない。反射経路は
/// outcomes_from_calc_result を通らず単一 outcome を直接返すため、0 ダメージ
/// 反射を chip 化して剥がしてしまう退行を防ぐ。
///
/// シナリオ: カウンター使用者 (attacker) が、反射ダメージを受ける defender =
/// ミミッキュ (ゴースト/フェアリー) に対し反射する。カウンターの反射タイプは
/// かくとう で、ゴーストには無効 → 反射ダメージ 0。本家では 0 ダメージ被弾で
/// Disguise は発動しないので、intact のとき mean_damage=0 かつ hits_count=0
/// (immune sentinel = fanout の bust ゲート power>0 && hits_count>0 を通さない)。
test "disguise: zero-damage (type-immune) reflect does NOT bust intact Disguise" {
  let counter_user = sgd_attacker(
    sgd_move(
      "カウンター",
      power=1,
      category=@model.Physical,
      type_="かくとう",
    ),
  )
  // defender = ミミッキュ (ゴースト/フェアリー、ばけのかわ)。かくとう 反射は
  // ゴーストに無効。
  let mimikyu = sgd_mimikyu()
  let reflect_mv = counter_user.moves[0]
  let intact = compute_damage_variants(
    counter_user,
    mimikyu,
    reflect_mv,
    0,
    0,
    def_disguise_intact=true,
  )
  // 0 ダメージ反射: chip 化されず、hits_count=0 (剥がれない sentinel)。
  @debug.debug_inspect(intact.length(), content="1")
  assert_eq(intact[0].mean_damage, 0)
  @debug.debug_inspect(intact[0].hits_count, content="0")
  // 対照: def_disguise_intact=false でも 0 ダメージ (reflect 生値、hits_count=1)。
  let plain = compute_damage_variants(counter_user, mimikyu, reflect_mv, 0, 0)
  assert_eq(plain[0].mean_damage, 0)
}

///|
/// (回帰: codex review 指摘) 反射技が実ダメージを返すケースは intact な
/// ばけのかわ を chip で剥がす (= 通常のダメージ技と同じ扱い、hits_count=1)。
/// 上のゼロ反射テストと対で「0 のときだけ剥がれない」ことを固める。
///
/// ミミッキュは常にゴースト/フェアリーなので、かくとう 反射のカウンターは必ず
/// 無効化される。正の反射を得るにはエスパー反射のミラーコート (ゴースト/フェアリー
/// に等倍) + ミミッキュ側の特殊技候補を使う (ミラーコートは特殊技のみ候補に取る)。
test "disguise: nonzero reflect chips intact Disguise (hits_count stays 1)" {
  let mc_user = sgd_attacker(
    sgd_move(
      "ミラーコート",
      power=1,
      category=@model.Special,
      type_="エスパー",
    ),
  )
  // defender = 特殊技 (シャドーボール) 持ちミミッキュ。ばけのかわ で intact。
  // ミラーコート反射 (エスパー) は ゴースト/フェアリー に等倍 → 反射 > 0。
  let sp_mimikyu = sgd_mimikyu(
    mv=sgd_move(
      "シャドーボール",
      power=80,
      category=@model.Special,
      type_="ゴースト",
    ),
  )
  let reflect_mv = mc_user.moves[0]
  let intact = compute_damage_variants(
    mc_user,
    sp_mimikyu,
    reflect_mv,
    0,
    0,
    def_disguise_intact=true,
  )
  @debug.debug_inspect(intact.length(), content="1")
  // まず反射が非ゼロであることを対照 (def_disguise_intact=false) で確認。
  let plain = compute_damage_variants(mc_user, sp_mimikyu, reflect_mv, 0, 0)
  assert_true(plain[0].mean_damage > 0)
  // intact では chip に置換され hits_count は 1 のまま (剥がれる)。
  let chip = effective_hp(sp_mimikyu) / 8
  assert_eq(intact[0].mean_damage, chip)
  @debug.debug_inspect(intact[0].hits_count, content="1")
}
