///|
/// Whitebox tests for reflect-move evaluation inside `compute_damage_variants`.
/// These exercise the nash-side aggregation logic (per-candidate Step1 reverse
/// recursion, p_slow × p_hit weighting, average × multiplier) without relying
/// on payoff-matrix orchestration above it.

///|
fn rfn_pokemon(
  name : String,
  type1 : String,
  type2 : String,
  hp : Int,
  atk : Int,
  def_ : Int,
  spa : Int,
  spd : Int,
  spe : Int,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2,
    hp,
    atk,
    def_,
    spa,
    spd,
    spe,
    bst: hp + atk + def_ + spa + spd + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 0.0,
    forms: [],
  }
}

///|
fn rfn_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
  accuracy? : Int = 100,
  priority? : Int = 0,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
    accuracy,
    pp: 10,
    learn_method: "",
    priority,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
  }
}

///|
fn rfn_combatant(
  pokemon : @model.Pokemon,
  moves : Array[@model.Move],
) -> Combatant {
  {
    pokemon,
    moves,
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
/// Physical attacker vs Counter holder → outcome non-zero, equals
/// (defender's lone physical move avg Step1) × 2.0.
test "reflect nash: Counter vs physical-only opponent yields positive outcome" {
  let counter_user = rfn_combatant(
    rfn_pokemon("user", "ノーマル", "", 200, 50, 100, 50, 100, 50),
    [rfn_move("カウンター", "かくとう", @model.Physical, 1)],
  )
  let physical_atk = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 200, 100, 50, 100, 100),
    [rfn_move("たいあたり", "ノーマル", @model.Physical, 40)],
  )
  let reflect_mv = counter_user.moves[0]
  let outcomes = compute_damage_variants(
    counter_user, physical_atk, reflect_mv, 0, 0,
  )
  @debug.debug_inspect(outcomes.length(), content="1")
  let o = outcomes[0]
  // Sanity: outcome is the reflect cell, single hit, probability 1.
  @debug.debug_inspect(o.hits_count, content="1")
  @debug.debug_inspect(o.probability, content="1")
  // Damage is positive (was 0 before this refactor since power=1 in DB).
  assert_true(o.mean_damage > 0)
}

///|
/// Mirror Coat picks up only the special move on a mixed-attack defender.
test "reflect nash: MirrorCoat ignores physical, sums only special" {
  let mc_user = rfn_combatant(
    rfn_pokemon("user", "エスパー", "", 200, 50, 100, 50, 100, 50),
    [rfn_move("ミラーコート", "エスパー", @model.Special, 1)],
  )
  let mixed = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 100, 100, 200, 100, 100),
    [
      // Physical: ignored by MirrorCoat.
      rfn_move("たいあたり", "ノーマル", @model.Physical, 40),
      // Special: the only candidate.
      rfn_move("ねっぷう", "ほのお", @model.Special, 95),
    ],
  )
  let reflect_mv = mc_user.moves[0]
  let outcomes_mixed = compute_damage_variants(mc_user, mixed, reflect_mv, 0, 0)
  // Now compare against a defender that has ONLY the special move. The
  // per-candidate average must be identical because the physical entry is
  // filtered out before averaging.
  let special_only = {
    ..mixed,
    moves: [rfn_move("ねっぷう", "ほのお", @model.Special, 95)],
  }
  let outcomes_solo = compute_damage_variants(
    mc_user, special_only, reflect_mv, 0, 0,
  )
  @debug.debug_inspect(
    outcomes_mixed[0].mean_damage == outcomes_solo[0].mean_damage,
    content="true",
  )
  assert_true(outcomes_mixed[0].mean_damage > 0)
}

///|
/// Status-only opponent → reflect outcome is 0 (no acceptable candidate).
test "reflect nash: status-only opponent yields zero outcome" {
  let counter_user = rfn_combatant(
    rfn_pokemon("user", "ノーマル", "", 200, 50, 100, 50, 100, 50),
    [rfn_move("カウンター", "かくとう", @model.Physical, 1)],
  )
  // Status moves have power > 0 in some DB rows, but here we synthesize one
  // with power=0 to match the engine's "no damage" treatment.
  let status_only = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 100, 100, 100, 100, 100),
    [rfn_move("どくどく", "どく", @model.Status, 0)],
  )
  let reflect_mv = counter_user.moves[0]
  let outcomes = compute_damage_variants(
    counter_user, status_only, reflect_mv, 0, 0,
  )
  @debug.debug_inspect(outcomes[0].mean_damage, content="0")
}

///|
/// All-reflect-move defender (a degenerate set) → zero outcome. Verifies the
/// `allow_reflect=false` recursion barrier behaves observationally: candidates
/// are emptied by the inner skip, not by hanging.
test "reflect nash: all-reflect-move defender yields zero outcome (recursion guard)" {
  let counter_user = rfn_combatant(
    rfn_pokemon("user", "ノーマル", "", 200, 50, 100, 50, 100, 50),
    [rfn_move("カウンター", "かくとう", @model.Physical, 1)],
  )
  let all_reflect = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 100, 100, 100, 100, 100),
    [
      rfn_move("カウンター", "かくとう", @model.Physical, 1),
      rfn_move("ミラーコート", "エスパー", @model.Special, 1),
      rfn_move("メタルバースト", "はがね", @model.Physical, 1),
      rfn_move("ほうふく", "あく", @model.Physical, 1),
    ],
  )
  let reflect_mv = counter_user.moves[0]
  let outcomes = compute_damage_variants(
    counter_user, all_reflect, reflect_mv, 0, 0,
  )
  // Each reflect move is power=1 (DB legacy) but the candidate filter skips
  // reflect moves regardless, so candidate_count = 0 → 0 outcome.
  @debug.debug_inspect(outcomes[0].mean_damage, content="0")
}

///|
/// MetalBurst turn-order: when reflect user is FASTER, p_slow = 0 → outcome 0.
test "reflect nash: MetalBurst with faster reflect user → 0 (outspeeds)" {
  let mb_user = rfn_combatant(
    // High speed (200) → outspeeds opponent (50).
    rfn_pokemon("user", "はがね", "", 200, 100, 100, 50, 100, 200),
    [rfn_move("メタルバースト", "はがね", @model.Physical, 1)],
  )
  let slow_atk = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 150, 100, 50, 100, 50),
    [rfn_move("たいあたり", "ノーマル", @model.Physical, 40)],
  )
  let reflect_mv = mb_user.moves[0]
  let outcomes = compute_damage_variants(mb_user, slow_atk, reflect_mv, 0, 0)
  @debug.debug_inspect(outcomes[0].mean_damage, content="0")
}

///|
/// MetalBurst turn-order: when reflect user is SLOWER, p_slow = 1 → positive.
test "reflect nash: MetalBurst with slower reflect user → positive outcome" {
  let mb_user = rfn_combatant(
    // Low speed (50) → loses speed roll, MetalBurst lands.
    rfn_pokemon("user", "はがね", "", 200, 100, 100, 50, 100, 50),
    [rfn_move("メタルバースト", "はがね", @model.Physical, 1)],
  )
  let fast_atk = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 200, 100, 50, 100, 200),
    [rfn_move("たいあたり", "ノーマル", @model.Physical, 40)],
  )
  let reflect_mv = mb_user.moves[0]
  let outcomes = compute_damage_variants(mb_user, fast_atk, reflect_mv, 0, 0)
  assert_true(outcomes[0].mean_damage > 0)
}

///|
/// MetalBurst turn-order: same speed → p_slow = 0.5 → outcome ~half of slower
/// case. Compared inside one test so we don't have to byte-pin a number.
test "reflect nash: MetalBurst same-speed → roughly half of slower-side outcome" {
  let mv = rfn_move("メタルバースト", "はがね", @model.Physical, 1)
  let atk_mv = rfn_move("たいあたり", "ノーマル", @model.Physical, 40)
  let slow_user = rfn_combatant(
    rfn_pokemon("user_slow", "はがね", "", 200, 100, 100, 50, 100, 50),
    [mv],
  )
  let same_user = rfn_combatant(
    rfn_pokemon("user_same", "はがね", "", 200, 100, 100, 50, 100, 100),
    [mv],
  )
  let opponent = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 200, 100, 50, 100, 100),
    [atk_mv],
  )
  let slow_out = compute_damage_variants(slow_user, opponent, mv, 0, 0)
  let same_out = compute_damage_variants(same_user, opponent, mv, 0, 0)
  // p_slow=1 vs p_slow=0.5 → same-speed outcome must be roughly half of
  // slower-side outcome (allow ±1 for integer truncation).
  let slow_d = slow_out[0].mean_damage
  let same_d = same_out[0].mean_damage
  let half_slow = slow_d / 2
  assert_true(same_d >= half_slow - 1 && same_d <= half_slow + 1)
}

///|
/// Opponent priority move (e.g. しんそく priority +2) → p_slow forced to 1
/// regardless of speed. The reflect user always goes after the priority move.
test "reflect nash: opponent priority move forces p_slow=1 even when faster" {
  let mb_user = rfn_combatant(
    // Even with high speed, MetalBurst still lands against a priority move.
    rfn_pokemon("user", "はがね", "", 200, 100, 100, 50, 100, 200),
    [rfn_move("メタルバースト", "はがね", @model.Physical, 1)],
  )
  let prio_atk = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 200, 100, 50, 100, 50),
    [rfn_move("しんそく", "ノーマル", @model.Physical, 80, priority=2)],
  )
  let reflect_mv = mb_user.moves[0]
  let outcomes = compute_damage_variants(mb_user, prio_atk, reflect_mv, 0, 0)
  // Without the priority-forces-p_slow=1 rule this would be 0 (faster user).
  assert_true(outcomes[0].mean_damage > 0)
}

///|
/// Accuracy multiplier: 70% accuracy move yields ~70% of the 100% case.
test "reflect nash: 70% accuracy halves outcome relative to 100% (roughly 0.7x)" {
  let counter_user = rfn_combatant(
    rfn_pokemon("user", "ノーマル", "", 200, 50, 100, 50, 100, 50),
    [rfn_move("カウンター", "かくとう", @model.Physical, 1)],
  )
  // Same move type / category / power; only accuracy differs so the
  // reflect outcome ratio isolates the p_hit_i multiplier.
  let acc100 = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 200, 100, 50, 100, 100),
    [
      rfn_move(
        "たいあたり",
        "ノーマル",
        @model.Physical,
        80,
        accuracy=100,
      ),
    ],
  )
  let acc70 = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 200, 100, 50, 100, 100),
    [
      rfn_move(
        "たいあたり",
        "ノーマル",
        @model.Physical,
        80,
        accuracy=70,
      ),
    ],
  )
  let reflect_mv = counter_user.moves[0]
  let o100 = compute_damage_variants(counter_user, acc100, reflect_mv, 0, 0)
  let o70 = compute_damage_variants(counter_user, acc70, reflect_mv, 0, 0)
  // damage_70 ≈ damage_100 × (0.7) (allow generous tolerance due to integer
  // truncation in mean_damage and Step1's own 16-roll quantization).
  let d100 = o100[0].mean_damage
  let d70 = o70[0].mean_damage
  assert_true(d70 > 0)
  assert_true(d100 > 0)
  // d70 should be ~70% of d100; tolerate ±15% absolute relative to d100.
  let upper = d100 * 85 / 100
  let lower = d100 * 55 / 100
  assert_true(d70 >= lower && d70 <= upper)
}

///|
/// Counter against Ghost-type opponent (type immune) → outcome 0.
test "reflect nash: Counter against Ghost-type opponent → 0 (type immune)" {
  let counter_user = rfn_combatant(
    rfn_pokemon("user", "ノーマル", "", 200, 50, 100, 50, 100, 50),
    [rfn_move("カウンター", "かくとう", @model.Physical, 1)],
  )
  let ghost = rfn_combatant(
    rfn_pokemon("atk", "ゴースト", "", 200, 200, 100, 50, 100, 100),
    [rfn_move("シャドーパンチ", "ゴースト", @model.Physical, 60)],
  )
  let reflect_mv = counter_user.moves[0]
  let outcomes = compute_damage_variants(counter_user, ghost, reflect_mv, 0, 0)
  @debug.debug_inspect(outcomes[0].mean_damage, content="0")
}

///|
/// MirrorCoat (Special) Step1 must read the opponent's SpA stage and the
/// reflect user's SpD stage. Before the rank-routing fix, the outer
/// dispatch picked the opponent's SpD for the outer `def_rank` and reused
/// it as Step1's atk_rank, so an opponent SpA boost was invisible to
/// Step1. With the fix, Step1 picks `def_ranks_full[2]` (opponent SpA)
/// and `atk_ranks_full[3]` (reflect user SpD).
test "reflect nash: MirrorCoat Step1 reads opponent SpA from def_ranks_full" {
  let mc_user = rfn_combatant(
    rfn_pokemon("user", "エスパー", "", 200, 50, 100, 50, 100, 50),
    [rfn_move("ミラーコート", "エスパー", @model.Special, 1)],
  )
  let special_atk = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 100, 100, 100, 100, 100),
    [rfn_move("ねっぷう", "ほのお", @model.Special, 95)],
  )
  let reflect_mv = mc_user.moves[0]
  // Baseline: all ranks 0. compute_damage_variants applies the rank-routing
  // fix when full arrays are present.
  let baseline = compute_damage_variants(
    mc_user,
    special_atk,
    reflect_mv,
    0,
    0,
    atk_ranks_full=Some([0, 0, 0, 0, 0]),
    def_ranks_full=Some([0, 0, 0, 0, 0]),
  )
  // Opponent SpA at +2 (def_ranks_full index 2 = SpA stage). Step1
  // attacker is the opponent, so its SpA rank scales the inbound damage,
  // which then scales the reflected output.
  let spa_boost = compute_damage_variants(
    mc_user,
    special_atk,
    reflect_mv,
    0,
    0,
    atk_ranks_full=Some([0, 0, 0, 0, 0]),
    def_ranks_full=Some([0, 0, 2, 0, 0]),
  )
  // Reflect user SpD at -2 (atk_ranks_full index 3 = SpD stage). Step1
  // defender is the reflect user, so a lower SpD increases the inbound
  // damage and therefore the reflected output.
  let spd_drop = compute_damage_variants(
    mc_user,
    special_atk,
    reflect_mv,
    0,
    0,
    atk_ranks_full=Some([0, 0, 0, -2, 0]),
    def_ranks_full=Some([0, 0, 0, 0, 0]),
  )
  // Both perturbations must increase the reflected damage above baseline.
  // Before the fix, they would not — the outer (Special-dispatched) atk/
  // def ranks were already opp-SpD / user-SpA, masking these stages.
  assert_true(spa_boost[0].mean_damage > baseline[0].mean_damage)
  assert_true(spd_drop[0].mean_damage > baseline[0].mean_damage)
  // Boosting the opponent's Atk or our Def must NOT affect a MirrorCoat
  // reflecting a Special candidate — the rank-routing pick is per-category.
  let irrelevant = compute_damage_variants(
    mc_user,
    special_atk,
    reflect_mv,
    0,
    0,
    atk_ranks_full=Some([0, -2, 0, 0, 0]),
    def_ranks_full=Some([2, 0, 0, 0, 0]),
  )
  @debug.assert_eq(irrelevant[0].mean_damage, baseline[0].mean_damage)
}

///|
/// MetalBurst accepts BOTH physical and special candidates, so a single
/// fixed (atk_rank, def_rank) pair from the outer dispatch cannot serve
/// both. Verify per-candidate routing: an opponent Atk boost only affects
/// the physical candidate's Step1, and an opponent SpA boost only the
/// special candidate's Step1.
test "reflect nash: MetalBurst routes Atk vs SpA per candidate category" {
  let mb_user = rfn_combatant(
    // Slow user so MetalBurst always lands (p_slow=1).
    rfn_pokemon("user", "はがね", "", 200, 100, 100, 100, 100, 50),
    [rfn_move("メタルバースト", "はがね", @model.Physical, 1)],
  )
  // Opponent has tied physical + special offences with equal base stats so
  // both candidates contribute equally at baseline. Choose move powers and
  // types that don't favour one over the other relative to user typing.
  let mixed_atk = rfn_combatant(
    rfn_pokemon("atk", "ノーマル", "", 200, 120, 100, 120, 100, 120),
    [
      rfn_move("たいあたり", "ノーマル", @model.Physical, 60),
      rfn_move("はかいこうせん", "ノーマル", @model.Special, 60),
    ],
  )
  let reflect_mv = mb_user.moves[0]
  let baseline = compute_damage_variants(
    mb_user,
    mixed_atk,
    reflect_mv,
    0,
    0,
    atk_ranks_full=Some([0, 0, 0, 0, 0]),
    def_ranks_full=Some([0, 0, 0, 0, 0]),
  )
  // Boost opponent's Atk only.
  let atk_boost = compute_damage_variants(
    mb_user,
    mixed_atk,
    reflect_mv,
    0,
    0,
    atk_ranks_full=Some([0, 0, 0, 0, 0]),
    def_ranks_full=Some([2, 0, 0, 0, 0]),
  )
  // Boost opponent's SpA only.
  let spa_boost = compute_damage_variants(
    mb_user,
    mixed_atk,
    reflect_mv,
    0,
    0,
    atk_ranks_full=Some([0, 0, 0, 0, 0]),
    def_ranks_full=Some([0, 0, 2, 0, 0]),
  )
  // Both single-stage boosts must lift the reflected damage above
  // baseline, because each is the dominant rank for exactly one
  // candidate. With the pre-fix code, the outer (Physical-dispatched)
  // pair was (user-Atk, opp-Def) for both candidates, so SpA boosts
  // would be invisible and the physical Atk boost would land on the
  // wrong slot.
  assert_true(atk_boost[0].mean_damage > baseline[0].mean_damage)
  assert_true(spa_boost[0].mean_damage > baseline[0].mean_damage)
}
