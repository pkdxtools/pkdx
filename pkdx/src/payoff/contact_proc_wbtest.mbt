///|
/// Whitebox tests for apply_contact_proc_fanout (issue #93 / P4).

///|
fn cp_pokemon(name : String, type1 : String, type2 : String) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2,
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
fn cp_combatant(
  pokemon : @model.Pokemon,
  ability~ : String = "",
  item~ : String = "",
  mega_form~ : @model.MegaForm? = None,
) -> Combatant {
  {
    pokemon,
    moves: [],
    ability,
    item,
    tera_type: "",
    stat_system: @model.Standard,
    mega_form,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
}

///|
/// `cp_state()` の megaed 配列に攻撃側 slot 0 だけ true を立てた版。
/// mega-aware 経路 (#100) の regression test 用。
fn cp_state_attacker_megaed() -> SwitchingGameState {
  let s = cp_state()
  { ..s, my_megaed: [true, false, false] }
}

///|
fn cp_state() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100, 100],
    opp_hps: [100, 100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false, false],
    opp_megaed: [false, false, false],
    my_status: [@model.None, @model.None, @model.None],
    opp_status: [@model.None, @model.None, @model.None],
    my_must_recharge: [false, false, false],
    opp_must_recharge: [false, false, false],
    my_item_consumed: [false, false, false],
    opp_item_consumed: [false, false, false],
    turn: 0,
  }
}

///|
fn cp_move(name : String) -> @model.Move {
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
    power: 60,
    accuracy: 100,
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
test "contact_proc_fanout: ほのおのからだ vs contact move → 30% Burn" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり") // contact move
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // Expect 2 leaves: (0.7, no status) + (0.3, attacker burned)
  inspect(outcomes.length(), content="2")
  let mut p_sum = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    p_sum = p_sum + outcomes[i].0
  }
  let drift = if p_sum > 1.0 { p_sum - 1.0 } else { 1.0 - p_sum }
  inspect(drift < 1.0e-9, content="true")
}

///|
test "contact_proc_fanout: non-contact move → no fanout" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  // みずでっぽう is non-contact in the global table
  let mv = cp_move("みずでっぽう")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="1")
}

///|
test "contact_proc_fanout: defender has とびだすハバネロ → 100% Burn (single leaf)" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), item="とびだすハバネロ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="1")
  let drift = if outcomes[0].0 > 1.0 { outcomes[0].0 - 1.0 } else { 1.0 - outcomes[0].0 }
  inspect(drift < 1.0e-9, content="true")
}

///|
test "contact_proc_fanout: fire-type attacker is immune to burn proc" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ほのお", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // Fire types ignore Burn → no fanout, just (1.0, state)
  inspect(outcomes.length(), content="1")
}

///|
test "contact_proc_fanout: defender has no proc ability/item → no fanout" {
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(cp_pokemon("defender", "ノーマル", ""))
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="1")
}

///|
fn cp_multihit_move(name : String) -> @model.Move {
  // mhv_move と同じ shape だが、Skill Link 等で hit 数が確定する技に
  // なるよう name のみ差し替える。base power は contact-proc fanout の
  // 確率計算には影響しない。
  {
    name,
    type_: "ノーマル",
    category: @model.Physical,
    power: 25,
    accuracy: 100,
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
fn approx_eq_cp(a : Double, b : Double) -> Bool {
  let d = if a > b { a - b } else { b - a }
  d < 1.0e-9
}

///|
test "contact_proc_fanout: skill-link 5-hit contact move → P(burn)=1-0.7^5" {
  // #100: 多段技の各 contact 着弾で独立に proc 判定。スキルリンクで みだれづき
  // が確定 5 ヒットになる場合、ほのおのからだ の発火確率は 1 - 0.7^5 ≈ 0.832。
  let attacker = cp_combatant(
    cp_pokemon("attacker", "ノーマル", ""), ability="スキルリンク",
  )
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_multihit_move("みだれづき")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="2")
  // outcomes[0] は no-proc, outcomes[1] が burn 状態。
  let q5 = 0.7 * 0.7 * 0.7 * 0.7 * 0.7
  let expected_burn = 1.0 - q5
  let p_sum = outcomes[0].0 + outcomes[1].0
  assert_true(approx_eq_cp(p_sum, 1.0))
  assert_true(approx_eq_cp(outcomes[0].0, q5))
  assert_true(approx_eq_cp(outcomes[1].0, expected_burn))
}

///|
test "contact_proc_fanout: ほうし produces 4 leaves (no-status / poison / paralyze / sleep)" {
  // #100: ほうし は per-hit で 11% どく / 10% まひ / 9% ねむり (合計 30%) を
  // 独立試行扱いする。タイプ耐性のないノーマル攻撃側に対しては、3 種すべての
  // 状態異常 leaf が得られるはず。
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほうし",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // [no-status, poison, paralyze, sleep] = 4 leaves
  inspect(outcomes.length(), content="4")
  let mut p_sum = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    p_sum = p_sum + outcomes[i].0
  }
  assert_true(approx_eq_cp(p_sum, 1.0))
  // no-status mass = 0.7 (1 - p_total per hit)
  assert_true(approx_eq_cp(outcomes[0].0, 0.7))
}

///|
test "contact_proc_fanout: ほうし vs poison-immune attacker keeps paralyze and sleep" {
  // #100: どくタイプ攻撃側は どく proc に耐性があるが、まひ / ねむり は
  // そのまま残るべき。MVP の単一 proc 折り畳みでは丸ごと無効化される
  // 退行を防ぐ。
  let attacker = cp_combatant(cp_pokemon("attacker", "どく", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほうし",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // poison が immune fizzle するので [no-status, paralyze, sleep] の 3 leaves。
  inspect(outcomes.length(), content="3")
  let mut p_sum = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    p_sum = p_sum + outcomes[i].0
  }
  assert_true(approx_eq_cp(p_sum, 1.0))
  // viable_chance = 19 (10 まひ + 9 ねむり)、total_chance = 30
  // 単発技なので per-hit `1 - q_viable = 0.19` がそのまま p_viable。
  // no-status = 1 - 0.19 = 0.81
  assert_true(approx_eq_cp(outcomes[0].0, 0.81))
}

///|
test "contact_proc_fanout: ほうし × Skill-Link 5hit + poison-immune attacker → 1 - 0.81^5" {
  // #100: 旧実装は (1 - q_total^n) × viable/total を返していたため、5-hit
  // poison-immune 攻撃側で 0.526 になっていた (real: 1 - 0.81^5 = 0.6513…)。
  // viable_chance ベースで畳む新モデルでは正しい値が返るはず。
  let attacker = cp_combatant(
    cp_pokemon("attacker", "どく", ""), ability="スキルリンク",
  )
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほうし",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_multihit_move("みだれづき")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // poison fizzle で [no-status, paralyze, sleep] の 3 leaves。
  inspect(outcomes.length(), content="3")
  let mut p_sum = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    p_sum = p_sum + outcomes[i].0
  }
  assert_true(approx_eq_cp(p_sum, 1.0))
  // viable_chance = 19、q_viable = 0.81、5 hit → expected_no_status = 0.81^5
  let q5 = 0.81 * 0.81 * 0.81 * 0.81 * 0.81
  assert_true(approx_eq_cp(outcomes[0].0, q5))
  // p_viable = 1 - 0.81^5 ≈ 0.6513、まひ : ねむり = 10 : 9 で按分
  let p_viable = 1.0 - q5
  assert_true(approx_eq_cp(outcomes[1].0, p_viable * 10.0 / 19.0))
  assert_true(approx_eq_cp(outcomes[2].0, p_viable * 9.0 / 19.0))
}

///|
test "contact_proc_fanout: mega-form attacker uses post-mega ability (Skill Link)" {
  // #100: raw ability は "" でも mega_form の ability=スキルリンク が
  // mega 状態で適用され、みだれづき が 5-hit 化、ほのおのからだ proc は
  // 1 - 0.7^5 になるはず。effective_combatant 経由で ability を取れていない
  // と pre-mega の "" のまま 4-variant 分布で計算され、leaves 数も値もズレる。
  let mega_form : @model.MegaForm = {
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    type1: "ノーマル",
    type2: "",
    ability: "スキルリンク",
    name_ja: "メガ",
  }
  let attacker = cp_combatant(
    cp_pokemon("attacker", "ノーマル", ""), ability="", mega_form=Some(mega_form),
  )
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_multihit_move("みだれづき")
  let outcomes = apply_contact_proc_fanout(
    cp_state_attacker_megaed(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // Skill Link 5-hit → 単一 viable kind なので [no-status, burn] の 2 leaves。
  inspect(outcomes.length(), content="2")
  let q5 = 0.7 * 0.7 * 0.7 * 0.7 * 0.7
  assert_true(approx_eq_cp(outcomes[0].0, q5))
  assert_true(approx_eq_cp(outcomes[1].0, 1.0 - q5))
}

///|
test "contact_proc_fanout: non-mega attacker w/ pre-mega ability stays at base distribution" {
  // mega flag が false のときは pre-mega ability を見るので、Random2to5 が
  // FixedHits(3) ではなく分布展開されることを確認する (Skill Link 用 helper
  // のリグレッション)。攻撃側 ability="" → no Skill Link → 0.375 P(2hit) +
  // 0.375 P(3hit) + 0.125 P(4hit) + 0.125 P(5hit) で畳まれた no-proc が
  // 0.7 単発を上回るはず。
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_multihit_move("みだれづき")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="2")
  // Σ_n prob(n) × 0.7^n = 0.375×0.49 + 0.375×0.343 + 0.125×0.2401 + 0.125×0.16807
  //   ≈ 0.1838 + 0.1286 + 0.0300 + 0.0210 ≈ 0.3635
  let exp_no = 0.375 * 0.49 +
    0.375 * 0.343 +
    0.125 * 0.2401 +
    0.125 * 0.16807
  assert_true(approx_eq_cp(outcomes[0].0, exp_no))
}

///|
test "contact_proc_fanout: ability + item resolve sequentially per hit" {
  // #100 review: ability proc が先に解決し、status が乗らなかった場合だけ
  // item proc が後追いで解決する。せいでんき (paralyze 30%) +
  // とびだすハバネロ (burn 100%) では:
  //   q_a = 0.7、q_i = 0 → q_total = 0 (single contact 必発)
  //   per-hit set: paralyze = 0.30、burn = 0.7 × 1.0 = 0.70
  //   denom = 1 - q_total = 1 → P(paralyze) = 0.30、P(burn) = 0.70。
  // 旧実装は両 proc を 130% の categorical roll に畳み 30/130 vs 100/130 を
  // 出していたが、これは ability 先行 (30/70) でも item 先行 (0/100) でも
  // 再現不可能な合成分布。
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""),
    ability="せいでんき",
    item="とびだすハバネロ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // [no-status (mass 0), paralyze, burn] = 3 leaves.
  inspect(outcomes.length(), content="3")
  let mut p_sum = 0.0
  for i = 0; i < outcomes.length(); i = i + 1 {
    p_sum = p_sum + outcomes[i].0
  }
  assert_true(approx_eq_cp(p_sum, 1.0))
  // q_total = 0 → no-status mass collapses to 0.
  assert_true(approx_eq_cp(outcomes[0].0, 0.0))
  // 逐次解決の per-hit 確率がそのまま 1 hit の終端確率になる。
  assert_true(approx_eq_cp(outcomes[1].0, 0.30))
  assert_true(approx_eq_cp(outcomes[2].0, 0.70))
}

///|
test "contact_proc_fanout: ability + item with same kind collapse to one leaf" {
  // #100 review: せいでんき (paralyze 30) + とびだすなかみ (paralyze 100) は同 kind。
  //   q_a = 0.7、q_i = 0 → per-hit set(paralyze) = 0.30 + 0.7 × 1.0 = 1.0
  //   q_total = 0 で expected_no_status = 0 → 単一 kind 100% で 1 leaf に縮退。
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""),
    ability="せいでんき",
    item="とびだすなかみ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // Single-kind 100% proc → fanout collapses to one leaf.
  inspect(outcomes.length(), content="1")
  assert_true(approx_eq_cp(outcomes[0].0, 1.0))
}

///|
test "contact_proc_fanout: ability + item with attacker immune to one branch" {
  // #100 review: でんきタイプ攻撃側はせいでんきに免疫だが、
  // とびだすハバネロ (burn 100%) は通常通り発火する。
  //   viable_ability = 0 → q_a = 1、viable_item = 100 → q_i = 0
  //   per-hit set(burn) = 0 + 1.0 × 1.0 = 1.0、q_total = 0 で 1 leaf burn。
  let attacker = cp_combatant(cp_pokemon("attacker", "でんき", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""),
    ability="せいでんき",
    item="とびだすハバネロ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // Single viable kind (burn @100%) → 1 leaf via the deterministic fast path.
  inspect(outcomes.length(), content="1")
  assert_true(approx_eq_cp(outcomes[0].0, 1.0))
}

///|
test "contact_proc_fanout: type-immune contact move suppresses fanout" {
  // #100 review iter2: たいあたり (ノーマル) は ゴースト 防御側に対して
  // type immunity で 0 ダメージ。Showdown / Gen9 では「damage が解決された
  // hit」のみが contact proc trigger になるため、ほのおのからだ 持ちゴースト
  // でも やけど branch を生んではならない。
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ゴースト", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // 完全に immune なので fanout が起きず (1.0, state) の 1 leaf のみ。
  inspect(outcomes.length(), content="1")
  assert_true(approx_eq_cp(outcomes[0].0, 1.0))
}

///|
test "contact_proc_fanout: ability-immune contact move suppresses fanout" {
  // #100 review iter2: ふゆう defender (じめん 無効) に じしん などの じめん
  // contact 技 (実際の DB に じめん contact 技は存在しないが、ダミーで
  // 「じめんタイプ + makes_contact」move を組み立てる) が当たっても
  // ability immunity で 0 ダメージ。contact proc は起きてはならない。
  // ここでは「でんき contact 技」を使って ひらいしん defender に
  // 当てるテストにする (でんき 無効 ability の代表例)。
  let attacker = cp_combatant(cp_pokemon("attacker", "ノーマル", ""))
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""),
    ability="ひらいしん",
    item="とびだすハバネロ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  // でんき + contact 技は通常 DB では存在しないが、本テストは
  // apply_contact_proc_fanout の immunity 判定をピンポイントで確認するため
  // type_ のみを差し替えた move を組む (resolve_move_contact は move name
  // で contact 判定するので たいあたり の name を流用)。
  let mv = { ..cp_move("たいあたり"), type_: "でんき" }
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="1")
  assert_true(approx_eq_cp(outcomes[0].0, 1.0))
}

///|
test "contact_proc_fanout: フェアリースキン Normal contact vs Ghost still fans out" {
  // #100 review iter3: フェアリースキン + たいあたり (raw Normal, effective
  // Fairy) を ゴースト 防御 (ほのおのからだ) に当てると、engine は Fairy ×
  // Ghost = 2× で damage を解決するので contact proc も発火する。raw mv.type_
  // (ノーマル) で immunity を判定すると Normal × Ghost = 0 で fanout が抑制
  // され、burn branch が落ちてしまう regression を防ぐ。
  let attacker = cp_combatant(
    cp_pokemon("attacker", "ノーマル", ""), ability="フェアリースキン",
  )
  let defender = cp_combatant(
    cp_pokemon("defender", "ゴースト", ""), ability="ほのおのからだ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  // 30% burn × 1 hit → (0.7, no status) + (0.3, burn) の 2 leaves。
  inspect(outcomes.length(), content="2")
  assert_true(approx_eq_cp(outcomes[0].0, 0.7))
  assert_true(approx_eq_cp(outcomes[1].0, 0.3))
}

///|
test "contact_proc_fanout: エレキスキン Normal contact vs ひらいしん is suppressed" {
  // #100 review iter3: エレキスキン + たいあたり (raw Normal, effective Electric)
  // を ひらいしん 防御に当てると、engine は ability immunity で 0 ダメージを
  // 返す。raw mv.type_ (ノーマル) で immunity を判定すると check_def_immunity が
  // false を返し、虚偽の burn branch が出てしまう。resolved type を使って engine
  // と一致させる regression test。
  let attacker = cp_combatant(
    cp_pokemon("attacker", "ノーマル", ""), ability="エレキスキン",
  )
  let defender = cp_combatant(
    cp_pokemon("defender", "ノーマル", ""),
    ability="ひらいしん",
    item="とびだすハバネロ",
  )
  let attacker_team = [attacker, attacker, attacker]
  let defender_team = [defender, defender, defender]
  let mv = cp_move("たいあたり")
  let outcomes = apply_contact_proc_fanout(
    cp_state(), true, 0, 0, attacker_team, defender_team, mv,
  )
  inspect(outcomes.length(), content="1")
  assert_true(approx_eq_cp(outcomes[0].0, 1.0))
}
