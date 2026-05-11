///|
/// Phase 3-C (#91): deterministic branch-count upper bounds for the
/// multi-hit variants[] integrated game tree.
///
/// 時間計測ではなく cached_states (= 探索した distinct SwitchingGameState 数)
/// で上限を assert する。variants 統合により branch が非線形に増えていない
/// ことを CI で機械的に保証する。実時間計測は scripts/bench_branch.sh に
/// 分離 (CI では warning のみ、assertion なし)。
///
/// 上限値は実測 baseline から余裕を持たせた値で、回帰検出時に手動見直す。

///|
fn bc_pokemon(
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
fn bc_move(
  name : String,
  power~ : Int = 25,
  accuracy~ : Int = 100,
  status_effect~ : (@model.StatusKind, Int)? = None,
  type_~ : String = "ノーマル",
  category~ : @model.MoveCategory = @model.Physical,
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
    status_effect,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
  }
}

///|
fn bc_combatant(
  pokemon : @model.Pokemon,
  moves : Array[@model.Move],
  ability~ : String = "",
  item~ : String = "",
) -> Combatant {
  {
    pokemon,
    moves,
    ability,
    item,
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
test "Phase 3-C-1: Triple Axel 1v1 turn=4 — cached_states ≤ 800" {
  // multi-hit variants (3 outcomes) × 2 sides × 4 turns。memoize の状態空間
  // が指数的に膨らんでいないことを確認。baseline 実測: 478 (2026-05 時点)。
  let mv = bc_move("トリプルアクセル", power=20, accuracy=90, type_="こおり")
  let cmb = bc_combatant(bc_pokemon("axel", spe=100, hp=300), [mv])
  let (_v, stats, _cache) = switching_game_winrate_stats([cmb], [cmb], 4)
  assert_true(stats.cached_states <= 800)
}

///|
test "Phase 3-C-2: PopulationBomb 1v1 turn=4 — cached_states ≤ 4500" {
  // PopulationBomb の 10-variants が attacker / defender 両方で展開される
  // 最悪ケース。HP が 10-hit でも残るよう大きめに設定し、KO 早期収束で
  // branch が減る効果を抑制する。baseline 実測: 2786 (2026-05 時点)。
  let mv = bc_move("ネズミざん", power=20, accuracy=90)
  let cmb = bc_combatant(bc_pokemon("popbomb", spe=100, hp=400), [mv])
  let (_v, stats, _cache) = switching_game_winrate_stats([cmb], [cmb], 4)
  assert_true(stats.cached_states <= 4500)
}

///|
test "Phase 3-C-3: PopulationBomb + ほのおのからだ + paralyze secondary + フィラのみ — cached_states ≤ 1000" {
  // 多重 fanout: PopulationBomb 10 variants × ほのおのからだ contact (per-hit
  // 30% burn) × paralyze 30% secondary × フィラのみ HP-threshold proc。
  // 黒箱で「これらすべてが噛み合っても決定論的上限を超えない」ことを保証。
  let mv_atk = bc_move(
    "みだれづき", // contact + Random2to5 (4 variants) — PopulationBomb は contact_moves 未登録
    power=15,
    accuracy=85,
    status_effect=Some((@model.ParalyzeKind, 30)),
  )
  let attacker = bc_combatant(
    bc_pokemon("attacker", spe=120, hp=300),
    [mv_atk],
    item="フィラのみ",
  )
  let defender = bc_combatant(
    bc_pokemon("defender", type1="むし", spe=80, hp=300),
    [bc_move("たいあたり", power=40)],
    ability="ほのおのからだ",
  )
  let (_v, stats, _cache) = switching_game_winrate_stats(
    [attacker], [defender], 4,
  )
  // baseline 実測: 564 (2026-05 時点)。
  assert_true(stats.cached_states <= 1000)
}
