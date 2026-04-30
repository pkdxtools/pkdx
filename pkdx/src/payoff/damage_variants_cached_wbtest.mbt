///|
/// #91 Phase 2-A: white-box tests for `compute_damage_variants`.
///
/// Verifies that the payoff-layer probabilistic outcome list is built
/// from `r.variants[]` (NOT the legacy `r.damages` field), with one
/// `DamageOutcome` per chance-node leaf and `apply_burn_to_mean` already
/// folded in.
///
/// Phase 2-B regression coverage: `compute_mean_damage` is now a
/// probability-weighted aggregation of `compute_damage_variants` and
/// must agree with `expected_damage`-style math for multi-hit moves.

///|
fn dvc_pokemon(name : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1: "ノーマル",
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
fn dvc_move(
  name : String,
  power~ : Int = 25,
  accuracy~ : Int = 100,
) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
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
fn dvc_combatant(name : String, mv : @model.Move) -> Combatant {
  {
    pokemon: dvc_pokemon(name),
    moves: [mv],
    ability: "",
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
fn dvc_approx(a : Double, b : Double, tol : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < tol
}

///|
test "compute_damage_variants: single-hit move returns 1 outcome with probability 1.0" {
  let mv = dvc_move("たいあたり")
  let atk = dvc_combatant("attacker", mv)
  let dfn = dvc_combatant("defender", mv)
  let outcomes = compute_damage_variants(atk, dfn, mv, 0, 0)
  inspect(outcomes.length(), content="1")
  let o = outcomes[0]
  assert_true(dvc_approx(o.probability, 1.0, 1.0e-12))
  assert_true(o.hits_count == 1)
  assert_true(o.hit_steps.length() == 1)
}

///|
test "compute_damage_variants: Triple Axel returns 3 outcomes with hits_count {1,2,3} and probabilities {0.10,0.09,0.81}" {
  let mv = dvc_move("トリプルアクセル", power=20, accuracy=90)
  let atk = dvc_combatant("attacker", mv)
  let dfn = dvc_combatant("defender", mv)
  let outcomes = compute_damage_variants(atk, dfn, mv, 0, 0)
  inspect(outcomes.length(), content="3")
  assert_true(outcomes[0].hits_count == 1 && dvc_approx(outcomes[0].probability, 0.10, 1.0e-12))
  assert_true(outcomes[1].hits_count == 2 && dvc_approx(outcomes[1].probability, 0.09, 1.0e-12))
  assert_true(outcomes[2].hits_count == 3 && dvc_approx(outcomes[2].probability, 0.81, 1.0e-12))
}

///|
test "compute_damage_variants: Skill Link rocket blast returns 1 outcome with hits_count=5" {
  let mv = dvc_move("ロックブラスト", power=25, accuracy=90)
  let atk = {
    ..dvc_combatant("attacker", mv),
    ability: "スキルリンク",
  }
  let dfn = dvc_combatant("defender", mv)
  let outcomes = compute_damage_variants(atk, dfn, mv, 0, 0)
  inspect(outcomes.length(), content="1")
  assert_true(dvc_approx(outcomes[0].probability, 1.0, 1.0e-12))
  assert_true(outcomes[0].hits_count == 5)
}

///|
test "compute_damage_variants: PopulationBomb (ネズミざん) returns 10 outcomes with hits_count 1..10" {
  let mv = dvc_move("ネズミざん", power=20, accuracy=90)
  let atk = dvc_combatant("attacker", mv)
  let dfn = dvc_combatant("defender", mv)
  let outcomes = compute_damage_variants(atk, dfn, mv, 0, 0)
  inspect(outcomes.length(), content="10")
  let mut total = 0.0
  for i = 0; i < 10; i = i + 1 {
    assert_true(outcomes[i].hits_count == i + 1)
    total = total + outcomes[i].probability
  }
  assert_true(dvc_approx(total, 1.0, 1.0e-9))
}

///|
test "compute_damage_variants: outcomes Σ probability ≈ 1.0 ± 1e-9 across all multi-hit shapes" {
  let cases : Array[(@model.Move, Int)] = [
    (dvc_move("たいあたり"), 1),
    (dvc_move("にどげり"), 1),
    (dvc_move("トリプルアクセル", power=20, accuracy=90), 3),
    (dvc_move("みだれづき"), 4),
    (dvc_move("ネズミざん", power=20, accuracy=90), 10),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (mv, expected_n) = cases[i]
    let atk = dvc_combatant("attacker", mv)
    let dfn = dvc_combatant("defender", mv)
    let outcomes = compute_damage_variants(atk, dfn, mv, 0, 0)
    assert_true(outcomes.length() == expected_n)
    let mut total = 0.0
    for j = 0; j < outcomes.length(); j = j + 1 {
      total = total + outcomes[j].probability
    }
    assert_true(dvc_approx(total, 1.0, 1.0e-9))
  }
}

///|
test "compute_damage_variants: immune matchup returns one outcome with mean_damage=0" {
  // ノーマル damage move vs ゴースト defender → immune.
  let mv = dvc_move("たいあたり")
  let atk = dvc_combatant("attacker", mv)
  let dfn_pokemon : @model.Pokemon = {
    ..dvc_pokemon("ghost"),
    type1: "ゴースト",
  }
  let dfn : Combatant = {
    pokemon: dfn_pokemon,
    moves: [mv],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
  let outcomes = compute_damage_variants(atk, dfn, mv, 0, 0)
  inspect(outcomes.length(), content="1")
  assert_true(outcomes[0].mean_damage == 0)
  assert_true(dvc_approx(outcomes[0].probability, 1.0, 1.0e-12))
}

///|
test "compute_mean_damage agrees with Σ probability * mean_damage from variants (Phase 2-B contract)" {
  let mv = dvc_move("トリプルアクセル", power=20, accuracy=90)
  let atk = dvc_combatant("attacker", mv)
  let dfn = dvc_combatant("defender", mv)
  let outcomes = compute_damage_variants(atk, dfn, mv, 0, 0)
  let mut weighted = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    weighted = weighted + outcomes[i].probability * outcomes[i].mean_damage.to_double()
  }
  let scalar = compute_mean_damage(atk, dfn, mv, 0, 0)
  // compute_mean_damage truncates to Int, so allow +/- 1 of rounding slack.
  let diff = if weighted.to_int() > scalar {
    weighted.to_int() - scalar
  } else {
    scalar - weighted.to_int()
  }
  assert_true(diff <= 1)
}

///|
test "compute_damage_variants: burn halves Physical mean per variant" {
  let mv = dvc_move("たいあたり")
  let atk = dvc_combatant("attacker", mv)
  let dfn = dvc_combatant("defender", mv)
  let normal = compute_damage_variants(atk, dfn, mv, 0, 0)
  let burned = compute_damage_variants(atk, dfn, mv, 0, 0, atk_burn=true)
  // burn halves Physical → roughly 2x ratio (allow integer-division slack).
  inspect(normal.length(), content="1")
  inspect(burned.length(), content="1")
  let n = normal[0].mean_damage
  let b = burned[0].mean_damage
  assert_true(n > 0)
  assert_true(b > 0)
  assert_true(n >= b * 2 - 1)
  assert_true(n <= b * 2 + 1)
}
