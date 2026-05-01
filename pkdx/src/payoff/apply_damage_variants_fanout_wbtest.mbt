///|
/// Phase 2-D (#91): white-box tests for `apply_damage_variants_fanout`.
///
/// 5 つの独立した Red ステップで以下の dispatch を駆動:
/// - 2-D-1: Skill Link (Random2to5 + skill-link 縮退) → leaf 数 1
/// - 2-D-2: Triple Axel (TripleVariant) → leaf 数 3
/// - 2-D-3: PopulationBomb (ネズミざん) → leaf 数 10
/// - 2-D-4: variant ごとに defender HP が hits_count に応じて減る
/// - 2-D-5: variant 間の post-hit fanout 副作用が独立に評価される
///
/// 各 leaf の (Double, SwitchingGameState) は最終的に compose_fanouts の
/// 副作用を含むので、HP / 状態の確率分布を per-variant でフィルタして検証する。

///|
fn advf_pokemon(name : String, type1~ : String = "ノーマル") -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2: "",
    hp: 200,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 700,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
}

///|
fn advf_move(
  name : String,
  power~ : Int = 25,
  accuracy~ : Int = 100,
  status_effect~ : (@model.StatusKind, Int)? = None,
  type_~ : String = "ノーマル",
) -> @model.Move {
  {
    name,
    type_,
    category: @model.Physical,
    power,
    accuracy,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
  }
}

///|
fn advf_combatant(
  name : String,
  mv : @model.Move,
  ability~ : String = "",
) -> Combatant {
  {
    pokemon: advf_pokemon(name),
    moves: [mv],
    ability,
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
}

///|
fn advf_state(my_hp : Int, opp_hp : Int) -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [my_hp],
    opp_hps: [opp_hp],
    my_ranks: [0, 0, 0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0, 0, 0],
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
    turn: 0,
  }
}

///|
fn advf_approx(a : Double, b : Double, tol : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < tol
}

///|
/// Σ leaf probability を取り 1.0 ± tol に収まるか確認するヘルパ。
/// post-hit fanout で複数 sub-leaf に分岐する場合でも variant の Σprob は
/// 1.0 を保つので、attack site 全体の Σ も 1.0 になる。
fn advf_total_prob(leaves : Array[(Double, SwitchingGameState)]) -> Double {
  let mut acc = 0.0
  for i = 0; i < leaves.length(); i = i + 1 {
    let (p, _) = leaves[i]
    acc = acc + p
  }
  acc
}

///|
test "Phase 2-D-1: Skill Link rocket blast → leaf 数 1 (variants 縮退 dispatch)" {
  // Skill Link は Random2to5 を 5 hits 固定に縮退させる ability。
  // expand_variants は 1 outcome (hits=5, p=1.0) を返すので、
  // post-hit fanout が分岐しない (ability/item proc/secondary なし) 場合は
  // leaf 数 = 1 になる。
  let mv = advf_move("ロックブラスト", power=25, accuracy=90)
  let attacker = advf_combatant("attacker", mv, ability="スキルリンク")
  let defender = advf_combatant("defender", mv)
  let state = advf_state(200, 200)
  let outcomes = compute_damage_variants(attacker, defender, mv, 0, 0)
  let leaves = apply_damage_variants_fanout(
    state,
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[attacker],
    defender_team=[defender],
    pre_dmg_defender_hp=200,
  )
  assert_true(leaves.length() == 1)
  assert_true(advf_approx(advf_total_prob(leaves), 1.0, 1.0e-9))
}

///|
test "Phase 2-D-2: Triple Axel → leaf 数 3 (TripleVariant dispatch)" {
  // TripleVariant は (1,0.10) (2,0.09) (3,0.81) の 3 outcome を返す。
  // post-hit fanout なしで合計 3 leaf。
  let mv = advf_move("トリプルアクセル", power=20, accuracy=90)
  let attacker = advf_combatant("attacker", mv)
  let defender = advf_combatant("defender", mv)
  let state = advf_state(200, 200)
  let outcomes = compute_damage_variants(attacker, defender, mv, 0, 0)
  let leaves = apply_damage_variants_fanout(
    state,
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[attacker],
    defender_team=[defender],
    pre_dmg_defender_hp=200,
  )
  assert_true(leaves.length() == 3)
  assert_true(advf_approx(advf_total_prob(leaves), 1.0, 1.0e-9))
}

///|
test "Phase 2-D-3: PopulationBomb → leaf 数 10 (PopulationBomb dispatch)" {
  // PopulationBomb (ネズミざん) は 1..10 の 10 outcome を返す
  // (per-hit 90% 幾何分布、初撃命中後 Σ=1.0)。
  // post-hit fanout なしで合計 10 leaf。
  let mv = advf_move("ネズミざん", power=20, accuracy=90)
  let attacker = advf_combatant("attacker", mv)
  let defender = advf_combatant("defender", mv)
  let state = advf_state(2000, 2000) // KO 防止のため十分な HP
  let outcomes = compute_damage_variants(attacker, defender, mv, 0, 0)
  let leaves = apply_damage_variants_fanout(
    state,
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[attacker],
    defender_team=[defender],
    pre_dmg_defender_hp=2000,
  )
  assert_true(leaves.length() == 10)
  assert_true(advf_approx(advf_total_prob(leaves), 1.0, 1.0e-9))
}

///|
test "Phase 2-D-4: variant ごとに defender HP が hits_count に応じて減る" {
  // Triple Axel hits=1 leaf vs hits=3 leaf で defender HP 差を assert。
  // 単発(hits=1): 1 hit 分の damage、3 連続(hits=3): 3 hit 分の damage。
  // post-hit fanout は副作用なし (status_effect None / contact 非考慮) なので
  // 各 leaf は variant 確率と HP のみで識別できる。
  let mv = advf_move("トリプルアクセル", power=20, accuracy=90)
  let attacker = advf_combatant("attacker", mv)
  let defender = advf_combatant("defender", mv)
  let state = advf_state(2000, 2000)
  let outcomes = compute_damage_variants(attacker, defender, mv, 0, 0)
  let leaves = apply_damage_variants_fanout(
    state,
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[attacker],
    defender_team=[defender],
    pre_dmg_defender_hp=2000,
  )
  // 3 leaf 全部に opp_hp を集める。Σ p = 1.0 / それぞれ HP は 2000 - dmg。
  // variant 確率順 (1,2,3) で sort なら hits=1 leaf が最大 HP。
  assert_true(leaves.length() == 3)
  let hp_hits1 = leaves[0].1.opp_hps[0]
  let hp_hits3 = leaves[2].1.opp_hps[0]
  // hits=1 の damage < hits=3 の damage なので残 HP は hits=1 > hits=3。
  assert_true(hp_hits1 > hp_hits3)
  // hits=1 の damage が 0 でない (= damage 適用されている) ことを確認。
  assert_true(hp_hits1 < 2000)
}

///|
test "Phase 2-D-5: post-hit fanout 副作用が variant 間で独立 (per-hit secondary)" {
  // Triple Axel に secondary status effect (麻痺 30%) を付け、
  // hits=1 leaf vs hits=3 leaf で麻痺確率が異なる (per-hit 独立試行) ことを
  // assert。Phase 2-C で maybe_apply_status_fanout が hits_count を
  // 受け取り 1-(1-p)^n を計算する形に修正済。
  //
  // hits=1: 麻痺率 0.30 / hits=3: 麻痺率 1-(1-0.30)^3 = 1 - 0.343 = 0.657
  let mv = advf_move(
    "トリプルアクセル",
    power=20,
    accuracy=90,
    status_effect=Some((@model.ParalyzeKind, 30)),
  )
  let attacker = advf_combatant("attacker", mv)
  // でんき タイプ defender は麻痺 immune なので避ける。ノーマル defender。
  let defender = advf_combatant("defender", mv)
  let state = advf_state(2000, 2000)
  let outcomes = compute_damage_variants(attacker, defender, mv, 0, 0)
  let leaves = apply_damage_variants_fanout(
    state,
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[attacker],
    defender_team=[defender],
    pre_dmg_defender_hp=2000,
  )
  // 各 variant ごとに 2 leaf (no-status, paralyzed) に分岐するので
  // 計 6 leaf。
  assert_true(leaves.length() == 6)
  assert_true(advf_approx(advf_total_prob(leaves), 1.0, 1.0e-9))
  // hits_count 別に麻痺確率を計算する: opp_status[0] が Paralyze の leaf の
  // 確率を、HP が一致する variant ごとに集計。
  // hits=1 の HP / hits=3 の HP は全 variant 中で異なる識別子になる。
  // ここでは status による分岐確率の合計を、各 variant probability で割って
  // 正規化された麻痺率を得る。
  //
  // hits=1 のグループ: 全 leaf の HP が hits=1 のもの
  // hits=3 のグループ: 全 leaf の HP が hits=3 のもの
  let hp_hits1 = {
    // dummy: probe 用、test 内で hits=1 leaf の HP を取得
    let probe = leaves[0].1.opp_hps[0]
    let probe2 = leaves[1].1.opp_hps[0]
    if probe > probe2 { probe } else { probe2 }
  }
  let hp_hits3 = {
    let probe = leaves[4].1.opp_hps[0]
    let probe2 = leaves[5].1.opp_hps[0]
    if probe < probe2 { probe } else { probe2 }
  }
  let mut p_para_hits1_total = 0.0
  let mut p_var_hits1_total = 0.0
  let mut p_para_hits3_total = 0.0
  let mut p_var_hits3_total = 0.0
  for i = 0; i < leaves.length(); i = i + 1 {
    let (p, s) = leaves[i]
    let is_paralyzed = match s.opp_status[0] {
      @model.Paralyze => true
      _ => false
    }
    if s.opp_hps[0] == hp_hits1 {
      p_var_hits1_total = p_var_hits1_total + p
      if is_paralyzed {
        p_para_hits1_total = p_para_hits1_total + p
      }
    } else if s.opp_hps[0] == hp_hits3 {
      p_var_hits3_total = p_var_hits3_total + p
      if is_paralyzed {
        p_para_hits3_total = p_para_hits3_total + p
      }
    }
  }
  let p_para_hits1 = p_para_hits1_total / p_var_hits1_total
  let p_para_hits3 = p_para_hits3_total / p_var_hits3_total
  // hits=1: 0.30 ± 1e-9
  assert_true(advf_approx(p_para_hits1, 0.30, 1.0e-9))
  // hits=3: 1 - 0.7^3 = 0.657
  assert_true(advf_approx(p_para_hits3, 1.0 - 0.7 * 0.7 * 0.7, 1.0e-9))
}
