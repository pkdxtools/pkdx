///|
/// Phase 2-E (#91): white-box tests for attack-site variants integration.
///
/// 5 つの独立した Red ステップで attack-resolution の chance-node leaf 展開を
/// transition_with_cache 経由で観測する:
/// - 2-E-1: Triple Axel transition → 3 hit-count leaves
/// - 2-E-2: Triple Axel + 麻痺 secondary → hits 別の麻痺確率 (per-hit 独立)
/// - 2-E-3: PopulationBomb transition → 10 leaves
/// - 2-E-4: Σprob across all leaves at one transition step within 1e-9
/// - 2-E-5: SwitchingGameState の cache key shape 不変
///
/// transition_with_cache(UseMove, UseMove) では速度差で attacker が確定する
/// シナリオを使い、resolve_moves → resolve_attacker_leg の variants 経路を
/// 駆動する。

///|
fn asv_pokemon(
  name : String,
  type1~ : String = "ノーマル",
  spe~ : Int = 100,
) -> @model.Pokemon {
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
fn asv_move(
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
fn asv_combatant(
  name : String,
  mv : @model.Move,
  spe~ : Int = 100,
  ability~ : String = "",
) -> Combatant {
  {
    pokemon: asv_pokemon(name, spe~),
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
fn asv_state(my_hp : Int, opp_hp : Int) -> SwitchingGameState {
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
fn asv_approx(a : Double, b : Double, tol : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < tol
}

///|
fn asv_total_prob(leaves : Array[(Double, SwitchingGameState)]) -> Double {
  let mut acc = 0.0
  for i = 0; i < leaves.length(); i = i + 1 {
    let (p, _) = leaves[i]
    acc = acc + p
  }
  acc
}

///|
/// Distinct opp_hps[0] 値の個数。Triple Axel なら 3 (hits=1/2/3 で異なる),
/// PopulationBomb なら 10 (hits=1..10 で異なる) に等しい。
fn asv_distinct_opp_hps(leaves : Array[(Double, SwitchingGameState)]) -> Int {
  let seen : Array[Int] = []
  for i = 0; i < leaves.length(); i = i + 1 {
    let (_, s) = leaves[i]
    let hp = s.opp_hps[0]
    let mut found = false
    for j = 0; j < seen.length(); j = j + 1 {
      if seen[j] == hp {
        found = true
        break
      }
    }
    if not(found) {
      seen.push(hp)
    }
  }
  seen.length()
}

///|
test "Phase 2-E-1: Triple Axel transition → 3 distinct hit-count leaves" {
  // attacker (my_team[0]) speed >> defender's speed (opp_team[0]) so
  // resolve_moves dispatches my_first=true and the attacker leg uses
  // Triple Axel's variants pipeline.
  let mv_atk = asv_move("トリプルアクセル", power=20, accuracy=90)
  let mv_dfn = asv_move("たいあたり", power=10) // 防御側はダメージ低め
  let attacker = asv_combatant("attacker", mv_atk, spe=200)
  let defender = asv_combatant("defender", mv_dfn, spe=50)
  let state = asv_state(2000, 2000)
  let leaves = transition_with_cache(
    state, UseMove(0), UseMove(0), [attacker], [defender], new_damage_cache(),
  )
  // 3 hits-count variants on attacker side. 防御側は単発 (たいあたり) で
  // post-hit fanout も非分岐 (status_effect=None, contact_proc 該当なし) なので
  // 攻撃側 variants 数 = distinct な opp_hps の数。
  assert_true(asv_distinct_opp_hps(leaves) == 3)
}

///|
test "Phase 2-E-2: Triple Axel + paralyze 30% → hits 別の麻痺確率" {
  // attacker の Triple Axel が 30% paralyze secondary を持つ。
  // defender 側の per_side_attempt は paralyze 未付与 (初回 hit でしか付与
  // されないが、実装上は hits_count で per-hit Bernoulli 独立試行)。
  // hits=1 leaf 麻痺率 0.30 / hits=3 leaf 麻痺率 1-(1-0.3)^3 ≈ 0.657。
  let mv_atk = asv_move(
    "トリプルアクセル",
    power=20,
    accuracy=90,
    status_effect=Some((@model.ParalyzeKind, 30)),
  )
  let mv_dfn = asv_move("たいあたり", power=10)
  let attacker = asv_combatant("attacker", mv_atk, spe=200)
  let defender = asv_combatant("defender", mv_dfn, spe=50)
  let state = asv_state(2000, 2000)
  let leaves = transition_with_cache(
    state, UseMove(0), UseMove(0), [attacker], [defender], new_damage_cache(),
  )
  // Triple Axel 3 variants × paralyze 2 (Yes/No) → 6 leaves on the attacker
  // side. 防御側 たいあたり は単発で post-hit 非分岐 → 各 leaf で 1 sub leaf。
  // attacker 側で variants ごとに HP が異なるので distinct opp_hps = 3。
  // 各 hits-count グループ内で麻痺確率を集計する。
  let distinct_hps = asv_distinct_opp_hps(leaves)
  assert_true(distinct_hps == 3)
  // 各 hits-count グループの paralyze 確率を計算 (defender 麻痺、防御側を判定)
  // attacker の Triple Axel は my → opp に攻撃するので opp_status[0] が paralyze。
  let groups : Array[(Int, Double, Double)] = [] // (hp, p_para, p_total)
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
  // 3 groups: hits=1, hits=2, hits=3 (HP 降順=damage 昇順なので、
  //   HP 大きい = hits 少ない)。最大 HP グループの paralyze 率 = 0.30、
  //   最小 HP グループ = 1-0.7^3 = 0.657。
  let mut max_hp = -1
  let mut min_hp = 99999
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
  assert_true(asv_approx(max_hp_para_rate, 0.30, 1.0e-9))
  assert_true(asv_approx(min_hp_para_rate, 1.0 - 0.7 * 0.7 * 0.7, 1.0e-9))
}

///|
test "Phase 2-E-3: PopulationBomb transition → 10 distinct hit-count leaves" {
  let mv_atk = asv_move("ネズミざん", power=20, accuracy=90)
  let mv_dfn = asv_move("たいあたり", power=10)
  let attacker = asv_combatant("attacker", mv_atk, spe=200)
  let defender = asv_combatant("defender", mv_dfn, spe=50)
  let state = asv_state(20000, 20000) // KO 防止のため十分大
  let leaves = transition_with_cache(
    state, UseMove(0), UseMove(0), [attacker], [defender], new_damage_cache(),
  )
  // PopulationBomb 10 variants (hits=1..10) → 10 distinct opp_hps。
  assert_true(asv_distinct_opp_hps(leaves) == 10)
}

///|
test "Phase 2-E-4: Σprob across all leaves within 1e-9" {
  // 各 attack site で出力 leaves の確率合計が 1.0 ± 1e-9 を保つ。
  // Triple Axel + paralyze + 通常防御技で 6 leaves、ネズミざんで 10 leaves。
  let cases : Array[(@model.Move, @model.Move, Int, Int)] = [
    (asv_move("じしん", power=100), asv_move("たいあたり", power=10), 2000, 2000),
    (asv_move("トリプルアクセル", power=20, accuracy=90), asv_move("たいあたり", power=10), 2000, 2000),
    (asv_move("ネズミざん", power=20, accuracy=90), asv_move("たいあたり", power=10), 20000, 20000),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (mv_atk, mv_dfn, my_hp, opp_hp) = cases[i]
    let attacker = asv_combatant("attacker", mv_atk, spe=200)
    let defender = asv_combatant("defender", mv_dfn, spe=50)
    let state = asv_state(my_hp, opp_hp)
    let leaves = transition_with_cache(
      state, UseMove(0), UseMove(0), [attacker], [defender], new_damage_cache(),
    )
    assert_true(asv_approx(asv_total_prob(leaves), 1.0, 1.0e-9))
  }
}

///|
test "Phase 2-E-5: SwitchingGameState cache key shape unchanged" {
  // SwitchingGameState には hits_count や landed フィールドが追加されない
  // (= memoize cache key と互換)。Triple Axel 経由で transition すると
  // 3 leaves 返るが、各 leaf state は元の SwitchingGameState 型そのものであり、
  // Hash / Eq が機能する (= struct shape 不変)。
  let mv_atk = asv_move("トリプルアクセル", power=20, accuracy=90)
  let mv_dfn = asv_move("たいあたり", power=10)
  let attacker = asv_combatant("attacker", mv_atk, spe=200)
  let defender = asv_combatant("defender", mv_dfn, spe=50)
  let state = asv_state(2000, 2000)
  let leaves = transition_with_cache(
    state, UseMove(0), UseMove(0), [attacker], [defender], new_damage_cache(),
  )
  // 各 leaf を HashMap に入れて Hash collision 無く 3 distinct entries あること
  let map : @hashmap.HashMap[SwitchingGameState, Double] = @hashmap.HashMap::new()
  for i = 0; i < leaves.length(); i = i + 1 {
    let (p, s) = leaves[i]
    match map.get(s) {
      Some(existing) => map[s] = existing + p
      None => map[s] = p
    }
  }
  // distinct opp_hps が 3 通り (hits=1/2/3) で、他フィールドは同じなので
  // distinct state も 3 通り。defender (たいあたり) の damage が my_hps を
  // 単一値で減らすのでこの観点でも distinct ではない。
  assert_true(map.length() == 3)
}
