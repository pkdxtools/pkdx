///|
/// Phase 3-B (#91): black-box e2e tests for the multi-hit variants[]
/// chance-node leaf expansion.
///
/// 公開 API (`switching_game_winrate` / `transition_with_cache`) のみで
/// per-hit Bernoulli compounding と value 安定性を観測する。各 multi-hit
/// 経路を実戦的シナリオで踏むことで、white-box wbtest がカバーしない
/// 「本物のゲーム木上での leaf 統計の正しさ」を保証する。
///
/// 5 ケース:
/// - 3-B-1: みだれづき + ほのおのからだ contact → hits=5 leaf 火傷率 ≈ 1-0.7^5 ≈ 0.832
///   (Triple Axel は contact_moves テーブル未登録のため、Random2to5 contact 技で代替)
/// - 3-B-2: Triple Axel + paralyze 30% secondary → hits=1 麻痺 0.30 / hits=3 麻痺 0.657
/// - 3-B-3: PopulationBomb 10-hit leaf vs 1-hit leaf で defender HP 差が compound (10x 近い)
/// - 3-B-4: Triple Axel mirror match → switching_game_winrate ≈ 0 (exploitability ≤ 1e-6)
/// - 3-B-5: PopulationBomb mirror match → switching_game_winrate ≈ 0 (exploitability ≤ 1e-6)

///|
fn sgvt_pokemon(
  name : String,
  type1~ : String = "ノーマル",
  spe~ : Int = 100,
  hp~ : Int = 200,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2: "",
    hp,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe,
    bst: 700,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
}

///|
fn sgvt_move(
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
fn sgvt_combatant(
  pokemon : @model.Pokemon,
  mv : @model.Move,
  ability~ : String = "",
) -> Combatant {
  {
    pokemon,
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
fn sgvt_state(
  my_hp : Int,
  opp_hp : Int,
) -> SwitchingGameState {
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
fn sgvt_approx(a : Double, b : Double, tol : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < tol
}

///|
test "Phase 3-B-1: みだれづき + ほのおのからだ contact → hits=5 leaf burn rate ≈ 0.832" {
  // 攻撃側 (my) が みだれづき (contact + Random2to5)、防御側 (opp) が
  // ほのおのからだ。各 contact hit ごとに 30% burn が attacker に proc。
  // hits=5 leaf では P(attacker burn) = 1 - 0.7^5 ≈ 0.832。
  // (Triple Axel は contact_moves テーブル未登録のため、検証原理が同じ
  //  Random2to5 contact 技に差し替え。)
  let mv_atk = sgvt_move("みだれづき", power=15, accuracy=85)
  let mv_dfn = sgvt_move("たいあたり", power=10)
  let attacker = sgvt_combatant(sgvt_pokemon("attacker", spe=200), mv_atk)
  let defender = sgvt_combatant(
    sgvt_pokemon("defender", type1="むし", spe=50),
    mv_dfn,
    ability="ほのおのからだ",
  )
  let state = sgvt_state(20000, 20000)
  let leaves = transition_with_cache(
    state, UseMove(0), UseMove(0), [attacker], [defender], new_damage_cache(),
  )
  // hits=5 leaf を「opp_hps が最小のグループ」として識別 (5-hit が最大 damage)。
  // attacker burn proc は my_status[0] に反映される。
  let mut min_opp_hp = 99999999
  for i = 0; i < leaves.length(); i = i + 1 {
    let (_, s) = leaves[i]
    if s.opp_hps[0] < min_opp_hp {
      min_opp_hp = s.opp_hps[0]
    }
  }
  let mut group_total = 0.0
  let mut group_burned = 0.0
  for i = 0; i < leaves.length(); i = i + 1 {
    let (p, s) = leaves[i]
    if s.opp_hps[0] == min_opp_hp {
      group_total = group_total + p
      let is_burned = match s.my_status[0] {
        @model.Burn => true
        _ => false
      }
      if is_burned {
        group_burned = group_burned + p
      }
    }
  }
  let burn_rate = group_burned / group_total
  // 期待値: 1 - 0.7^5 = 0.83193
  let expected = 1.0 - 0.7 * 0.7 * 0.7 * 0.7 * 0.7
  assert_true(sgvt_approx(burn_rate, expected, 1.0e-9))
}

///|
test "Phase 3-B-2: Triple Axel + paralyze secondary → hits=1 leaf 0.30, hits=3 leaf 0.657" {
  // 攻撃側 Triple Axel が paralyze 30% secondary を持つ。hits-count ごとに
  // 独立 Bernoulli 試行。hits=1 leaf 麻痺率 = 0.30、hits=3 leaf = 0.657。
  let mv_atk = sgvt_move(
    "トリプルアクセル",
    power=20,
    accuracy=90,
    status_effect=Some((@model.ParalyzeKind, 30)),
    type_="こおり",
  )
  let mv_dfn = sgvt_move("たいあたり", power=10)
  let attacker = sgvt_combatant(sgvt_pokemon("attacker", spe=200), mv_atk)
  let defender = sgvt_combatant(sgvt_pokemon("defender", spe=50), mv_dfn)
  let state = sgvt_state(20000, 20000)
  let leaves = transition_with_cache(
    state, UseMove(0), UseMove(0), [attacker], [defender], new_damage_cache(),
  )
  // opp_hps の groupwise (= hits-count ごと) 麻痺率を集計。
  // 最大 HP グループ = hits=1 (最小 dmg)、最小 HP グループ = hits=3 (最大 dmg)。
  let groups : Array[(Int, Double, Double)] = [] // (opp_hp, p_para, p_total)
  for i = 0; i < leaves.length(); i = i + 1 {
    let (p, s) = leaves[i]
    let hp = s.opp_hps[0]
    let is_para = match s.opp_status[0] {
      @model.Paralyze => true
      _ => false
    }
    let mut idx = -1
    for j = 0; j < groups.length(); j = j + 1 {
      if groups[j].0 == hp {
        idx = j
        break
      }
    }
    if idx == -1 {
      groups.push((hp, if is_para { p } else { 0.0 }, p))
    } else {
      let (h, pp, pt) = groups[idx]
      groups[idx] = (h, pp + (if is_para { p } else { 0.0 }), pt + p)
    }
  }
  let mut max_hp = -1
  let mut min_hp = 99999999
  let mut max_hp_para_rate = 0.0
  let mut min_hp_para_rate = 0.0
  for i = 0; i < groups.length(); i = i + 1 {
    let (h, pp, pt) = groups[i]
    if h > max_hp {
      max_hp = h
      max_hp_para_rate = pp / pt
    }
    if h < min_hp {
      min_hp = h
      min_hp_para_rate = pp / pt
    }
  }
  assert_true(sgvt_approx(max_hp_para_rate, 0.30, 1.0e-9))
  assert_true(sgvt_approx(min_hp_para_rate, 1.0 - 0.7 * 0.7 * 0.7, 1.0e-9))
}

///|
test "Phase 3-B-3: PopulationBomb HP compound across 10 vs 1 hit leaves" {
  // ネズミざん (PopulationBomb) は hits=1..10 の 10 variants。
  // hits=10 leaf の defender HP < hits=1 leaf の defender HP で、その差が
  // 9 hits 分に近いオーダー (per-hit damage ~一定)。
  let mv_atk = sgvt_move("ネズミざん", power=20, accuracy=90)
  let mv_dfn = sgvt_move("たいあたり", power=10)
  let attacker = sgvt_combatant(sgvt_pokemon("attacker", spe=200), mv_atk)
  let defender = sgvt_combatant(sgvt_pokemon("defender", spe=50), mv_dfn)
  let state = sgvt_state(50000, 50000) // 10-hit でも余裕で残る HP
  let leaves = transition_with_cache(
    state, UseMove(0), UseMove(0), [attacker], [defender], new_damage_cache(),
  )
  let mut max_hp = -1
  let mut min_hp = 99999999
  for i = 0; i < leaves.length(); i = i + 1 {
    let (_, s) = leaves[i]
    if s.opp_hps[0] > max_hp {
      max_hp = s.opp_hps[0]
    }
    if s.opp_hps[0] < min_hp {
      min_hp = s.opp_hps[0]
    }
  }
  // dmg_per_hit = (max_hp の reduction) ≈ start_hp - max_hp
  // 10-hit leaf の reduction ≈ 10 * dmg_per_hit
  let start_hp = 50000
  let dmg_1hit = start_hp - max_hp
  let dmg_10hit = start_hp - min_hp
  // 厳密に 10x ではない (per-hit damage の roll 平均 + 整数丸め) が、
  // 9hit 分の compound で「明確に大きく差が出る」ことを保証する。
  // 下限: 10-hit dmg ≥ 8 * 1-hit dmg (緩いガード)、上限: ≤ 12 * 1-hit dmg
  assert_true(dmg_1hit > 0)
  assert_true(dmg_10hit >= dmg_1hit * 8)
  assert_true(dmg_10hit <= dmg_1hit * 12)
}

///|
test "Phase 3-B-4: Triple Axel mirror match → exploitability ≤ 1e-6" {
  // 両陣営同一 Triple Axel/速度/ステ。anti-symmetry より switching_game_winrate
  // は厳密に 0。multi-hit variants 統合後も対称性が崩れていないことを確認。
  let mv = sgvt_move("トリプルアクセル", power=20, accuracy=90, type_="こおり")
  let cmb = sgvt_combatant(sgvt_pokemon("mirror", spe=100), mv)
  let v = switching_game_winrate([cmb], [cmb], 4)
  assert_true(v.abs() < 1.0e-6)
}

///|
test "Phase 3-B-5: PopulationBomb mirror match → exploitability ≤ 1e-6" {
  // 同上、PopulationBomb mirror。10 variants × 10 variants = 100 leaves
  // per turn の確率分岐でも anti-symmetry が保たれる。
  let mv = sgvt_move("ネズミざん", power=20, accuracy=90)
  // KO 防止のため HP 高め
  let cmb = sgvt_combatant(sgvt_pokemon("mirror", spe=100, hp=400), mv)
  let v = switching_game_winrate([cmb], [cmb], 3)
  assert_true(v.abs() < 1.0e-6)
}
