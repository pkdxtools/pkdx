///|
/// Phase 3-A (#91): parameterized matrix wbtest for the variants[] →
/// chance-node leaf expansion pipeline.
///
/// transition_with_cache(UseMove, UseMove) を 8 ケース table 駆動で回し、
/// 各ケースの leaf 数 (= multi-hit variants 数) と Σprob = 1.0 ± 1e-9 を
/// まとめて assert する。compute_damage_variants の単体テスト
/// (damage_variants_cached_wbtest.mbt) と attack-site 統合テスト
/// (attack_site_variants_wbtest.mbt) の中間で「transition 出口の leaves
/// が move 種別ごとに正しい変動数になっている」ことを横断検証する。
///
/// 検証マトリックス:
/// | Move          | Spec                      | Expected leaves |
/// |---------------|---------------------------|-----------------|
/// | じしん         | Single                    | 1               |
/// | ハイドロポンプ  | Single (special)          | 1               |
/// | ロックブラスト  | Random2to5 + Skill Link → FixedHits(5) | 1 |
/// | トリプルアクセル| TripleVariant             | 3               |
/// | ネズミざん     | PopulationBomb            | 10              |
/// | みだれづき     | Random2to5                | 4               |
/// | つららばり     | Random2to5                | 4               |
/// | じしん+おやこあい | ParentalBond           | 1               |

///|
fn sgvw_pokemon(
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
fn sgvw_move(
  name : String,
  power~ : Int = 25,
  accuracy~ : Int = 100,
  category~ : @model.MoveCategory = @model.Physical,
  type_~ : String = "ノーマル",
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
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
  }
}

///|
fn sgvw_combatant(
  name : String,
  mv : @model.Move,
  spe~ : Int = 100,
  ability~ : String = "",
) -> Combatant {
  {
    pokemon: sgvw_pokemon(name, spe~),
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
fn sgvw_state(my_hp : Int, opp_hp : Int) -> SwitchingGameState {
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
fn sgvw_approx(a : Double, b : Double, tol : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < tol
}

///|
fn sgvw_total_prob(leaves : Array[(Double, SwitchingGameState)]) -> Double {
  let mut acc = 0.0
  for i = 0; i < leaves.length(); i = i + 1 {
    let (p, _) = leaves[i]
    acc = acc + p
  }
  acc
}

///|
/// distinct opp_hps[0] 値の個数を返す。各 multi-hit variant が異なる残 HP
/// を生むので、leaves 数 (or attacker 側の variant 数) と一致するはず。
fn sgvw_distinct_opp_hps(leaves : Array[(Double, SwitchingGameState)]) -> Int {
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
test "Phase 3-A: parameterized matrix — leaves count + Σprob across 8 cases" {
  // Each case: (label, attacker move, attacker ability, expected variants)
  // 防御側は固定 (たいあたり / 単発 / 非ランダム / 状態異常なし) で、
  // 攻撃側 multi-hit variants 数のみが leaves 数を駆動する。
  // attacker spe=200, defender spe=50 で my_first 確定。
  let mv_dfn = sgvw_move("たいあたり", power=10)
  // (label, attacker_move, attacker_ability, expected_distinct_variants)
  let cases : Array[(String, @model.Move, String, Int)] = [
    ("じしん", sgvw_move("じしん", power=100, type_="じめん"), "", 1),
    (
      "ハイドロポンプ",
      sgvw_move("ハイドロポンプ", power=110, accuracy=80, category=@model.Special, type_="みず"),
      "",
      1,
    ),
    (
      "Skill Link ロックブラスト",
      sgvw_move("ロックブラスト", power=25, accuracy=90, type_="いわ"),
      "スキルリンク",
      1,
    ),
    (
      "トリプルアクセル",
      sgvw_move("トリプルアクセル", power=20, accuracy=90, type_="こおり"),
      "",
      3,
    ),
    (
      "ネズミざん",
      sgvw_move("ネズミざん", power=20, accuracy=90, type_="ノーマル"),
      "",
      10,
    ),
    (
      "みだれづき",
      sgvw_move("みだれづき", power=15, accuracy=85, type_="ノーマル"),
      "",
      4,
    ),
    (
      "つららばり",
      sgvw_move("つららばり", power=25, accuracy=100, type_="こおり"),
      "",
      4,
    ),
    (
      "ParentalBond じしん",
      sgvw_move("じしん", power=100, type_="じめん"),
      "おやこあい",
      1,
    ),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (_label, mv_atk, ability, expected) = cases[i]
    let attacker = {
      ..sgvw_combatant("attacker", mv_atk, spe=200),
      ability,
    }
    let defender = sgvw_combatant("defender", mv_dfn, spe=50)
    // KO 防止のため十分大きな HP (PopulationBomb 10-hit でも残るレベル)。
    let state = sgvw_state(30000, 30000)
    let leaves = transition_with_cache(
      state,
      UseMove(0),
      UseMove(0),
      [attacker],
      [defender],
      new_damage_cache(),
    )
    // distinct opp_hps の数 = 攻撃側 variants 数 (防御側は単発で post-hit
    // 非分岐、status_effect=None なので追加 fanout なし)。
    let distinct = sgvw_distinct_opp_hps(leaves)
    assert_true(distinct == expected)
    // Σprob = 1.0 ± 1e-9
    assert_true(sgvw_approx(sgvw_total_prob(leaves), 1.0, 1.0e-9))
  }
}
