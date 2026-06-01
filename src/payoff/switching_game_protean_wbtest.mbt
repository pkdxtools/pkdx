///|
/// Stage 2 (Protean / Libero): white-box tests for the Protean type-lock
/// recording inside `with_post_hit_effects`.
///
/// へんげんじざい / リベロ は技を撃った瞬間に使用者をその技のタイプ 1 つに
/// 変える。本ステージは `with_post_hit_effects` が attacker 側スロットの
/// `*_protean_locked[active]` に `mv.type_` を記録するロジックのみを pin する。
/// ダメージ数値は engine 側で担保済みなので一切 assert しない。記録された
/// ロック文字列のみを検証する。

///|
fn pl_pokemon(name : String, type1 : String, type2 : String) -> @model.Pokemon {
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
fn pl_combatant(
  pokemon : @model.Pokemon,
  ability? : String = "",
  tera_type? : String = "",
) -> Combatant {
  {
    pokemon,
    moves: [],
    ability,
    item: "",
    tera_type,
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
}

///|
fn pl_state() -> SwitchingGameState {
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
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false, false],
    my_protean_locked: ["", "", ""],
    opp_leech_seeded: [false, false, false],
    opp_protean_locked: ["", "", ""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
fn pl_move(
  name : String,
  type_? : String = "ほのお",
  category? : @model.MoveCategory = @model.Physical,
  power? : Int = 60,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
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
    healing: None,
    weather_set: None,
    field_set: None,
  }
}

///|
test "protean: 初手ダメージ技で攻撃側スロットがロックされる" {
  let attacker = pl_combatant(
    pl_pokemon("attacker", "ノーマル", ""),
    ability="へんげんじざい",
  )
  let defender = pl_combatant(pl_pokemon("defender", "ノーマル", ""))
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let mv = pl_move(
    "かえんほうしゃ",
    type_="ほのお",
    category=@model.Special,
  )
  let new_state = with_post_hit_effects(
    pl_state(),
    true,
    0,
    0,
    team,
    def_team,
    mv,
    10,
  )
  @debug.assert_eq(new_state.my_protean_locked[0], "ほのお")
  // 控えスロット / 相手側は無関係。
  @debug.assert_eq(new_state.my_protean_locked[1], "")
  @debug.assert_eq(new_state.opp_protean_locked[0], "")
}

///|
test "protean: Status 技でもロックする" {
  // category=Status / power=0 の補助技でも Protean は発動する (カテゴリゲートなし)。
  let attacker = pl_combatant(
    pl_pokemon("attacker", "ノーマル", ""),
    ability="リベロ",
  )
  let defender = pl_combatant(pl_pokemon("defender", "ノーマル", ""))
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let mv = pl_move(
    "でんこうそうげき",
    type_="でんき",
    category=@model.Status,
    power=0,
  )
  let new_state = with_post_hit_effects(
    pl_state(),
    true,
    0,
    0,
    team,
    def_team,
    mv,
    0,
  )
  @debug.assert_eq(new_state.my_protean_locked[0], "でんき")
}

///|
test "protean: テラス中は非発動" {
  // tera_type != "" のとき Protean は発動しない (テラスタル中は型固定)。
  let attacker = pl_combatant(
    pl_pokemon("attacker", "ノーマル", ""),
    ability="へんげんじざい",
    tera_type="みず",
  )
  let defender = pl_combatant(pl_pokemon("defender", "ノーマル", ""))
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let mv = pl_move(
    "かえんほうしゃ",
    type_="ほのお",
    category=@model.Special,
  )
  let new_state = with_post_hit_effects(
    pl_state(),
    true,
    0,
    0,
    team,
    def_team,
    mv,
    10,
  )
  @debug.assert_eq(new_state.my_protean_locked[0], "")
}

///|
test "protean: 2手目は再ロックしない" {
  // 既に "ほのお" でロック済みのスロットが みず技を撃っても "ほのお" のまま
  // (once per switch-in)。
  let attacker = pl_combatant(
    pl_pokemon("attacker", "ノーマル", ""),
    ability="へんげんじざい",
  )
  let defender = pl_combatant(pl_pokemon("defender", "ノーマル", ""))
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let state = { ..pl_state(), my_protean_locked: ["ほのお", "", ""] }
  let mv = pl_move(
    "ハイドロポンプ",
    type_="みず",
    category=@model.Special,
  )
  let new_state = with_post_hit_effects(
    state, true, 0, 0, team, def_team, mv, 10,
  )
  @debug.assert_eq(new_state.my_protean_locked[0], "ほのお")
}

///|
test "非Protean はロックしない" {
  // ability が へんげんじざい / リベロ 以外なら locked は "" のまま。
  let attacker = pl_combatant(
    pl_pokemon("attacker", "みず", ""),
    ability="げきりゅう",
  )
  let defender = pl_combatant(pl_pokemon("defender", "ノーマル", ""))
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let mv = pl_move(
    "ハイドロポンプ",
    type_="みず",
    category=@model.Special,
  )
  let new_state = with_post_hit_effects(
    pl_state(),
    true,
    0,
    0,
    team,
    def_team,
    mv,
    10,
  )
  @debug.assert_eq(new_state.my_protean_locked[0], "")
}

///|
test "protean: 攻撃側が opp 側 (attacker_is_me=false) のとき opp 配列に記録" {
  // attacker_is_me=false なら opp_protean_locked 側へ記録され、my 側は不変。
  let attacker = pl_combatant(
    pl_pokemon("attacker", "ノーマル", ""),
    ability="へんげんじざい",
  )
  let defender = pl_combatant(pl_pokemon("defender", "ノーマル", ""))
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let mv = pl_move(
    "かえんほうしゃ",
    type_="ほのお",
    category=@model.Special,
  )
  let new_state = with_post_hit_effects(
    pl_state(),
    false,
    0,
    0,
    team,
    def_team,
    mv,
    10,
  )
  @debug.assert_eq(new_state.opp_protean_locked[0], "ほのお")
  @debug.assert_eq(new_state.my_protean_locked[0], "")
}

// ============================================================================
// fanout integration: apply_damage_variants_fanout を通る経路で全 leaf が
// 同一ロック値になること (variant 非依存) を pin する。
// ============================================================================

///|
fn pl_fanout_pokemon(name : String) -> @model.Pokemon {
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
fn pl_fanout_combatant(
  name : String,
  mv : @model.Move,
  ability~ : String,
) -> Combatant {
  {
    pokemon: pl_fanout_pokemon(name),
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
fn pl_fanout_state() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [2000],
    opp_hps: [2000],
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
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false],
    my_protean_locked: [""],
    opp_leech_seeded: [false],
    opp_protean_locked: [""],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
test "protean: fanout 全 leaf が同一ロック値" {
  // Triple Axel (3 variant に分岐) を Protean 攻撃側が撃つと、各 variant leaf の
  // my_protean_locked[0] が全て mv.type_ (= こおり) で一致するはず。記録値は
  // variant 非依存なので fanout の全 leaf でブレてはならない。
  let mv = pl_move(
    "トリプルアクセル",
    type_="こおり",
    category=@model.Physical,
    power=20,
  )
  let mv = { ..mv, accuracy: 90 }
  let attacker = pl_fanout_combatant(
    "attacker",
    mv,
    ability="へんげんじざい",
  )
  let defender = pl_fanout_combatant("defender", mv, ability="")
  let outcomes = compute_damage_variants(attacker, defender, mv, 0, 0)
  let leaves = apply_damage_variants_fanout(
    pl_fanout_state(),
    outcomes,
    attacker_is_me=true,
    attacker_active=0,
    defender_active=0,
    attacker_move=mv,
    attacker_team=[attacker],
    defender_team=[defender],
    pre_dmg_defender_hp=2000,
  )
  assert_true(leaves.length() >= 1)
  for i = 0; i < leaves.length(); i = i + 1 {
    let (_, s) = leaves[i]
    @debug.assert_eq(s.my_protean_locked[0], "こおり")
  }
}

// ============================================================================
// Stage 3: effective_combatant の Protean type override が damage の
// 攻撃 STAB / 防御タイプ相性へ効いていること。engine の数値は
// src/damage/protean_libero_test.mbt で担保済みなので、ここでは「STAB / 相性が
// 変わること」を相対比較で pin する (重複回避)。
// ============================================================================

///|
/// 単一 hit move の variants 配列から mean ダメージ (= outcomes[0].mean_damage)
/// を取り出す小ヘルパー。テスト内の比較を読みやすくする。
fn pl_single_mean(outcomes : Array[@model.DamageOutcome]) -> Int {
  outcomes[0].mean_damage
}

///|
test "protean offense: 発動技にのみ STAB (ロック後に別タイプ技は STAB なし)" {
  // 攻撃側 へんげんじざい。ベースタイプは ノーマル。
  // (a) ロック="ほのお" で ほのお技 → override で type1=ほのお, protean_consumed=true
  //     → 通常 STAB 経路で技タイプ一致 → STAB あり
  // (b) ロック="みず" で ほのお技 → override で type1=みず, protean_consumed=true
  //     → 技タイプ (ほのお) と使用者タイプ (みず) 不一致 → STAB なし
  // STAB 有無のみが差なので (a) > (b) になるはず。
  let mv = pl_move(
    "かえんほうしゃ",
    type_="ほのお",
    category=@model.Special,
    power=90,
  )
  let attacker = pl_fanout_combatant(
    "attacker",
    mv,
    ability="へんげんじざい",
  )
  let defender = pl_fanout_combatant("defender", mv, ability="")
  let team = [attacker]
  let def_team = [defender]
  let ranks = [0, 0, 0, 0, 0, 0, 0]
  let cache_stab = new_damage_cache()
  let stab = pl_single_mean(
    damage_variants_cached(
      cache_stab,
      true,
      0,
      ranks,
      0,
      ranks,
      0,
      team,
      def_team,
      atk_protean_locked="ほのお",
    ),
  )
  let cache_nostab = new_damage_cache()
  let nostab = pl_single_mean(
    damage_variants_cached(
      cache_nostab,
      true,
      0,
      ranks,
      0,
      ranks,
      0,
      team,
      def_team,
      atk_protean_locked="みず",
    ),
  )
  // STAB (1.5x) が乗る分 (a) のほうが大きい。
  assert_true(stab > nostab)
}

///|
test "protean offense: 未ロック発動技には engine が STAB を push (ロック後別タイプとの差)" {
  // 未ロック ("") で ほのお技 → engine の Protean gate が move_type=ほのお を STAB
  // へ push → STAB あり。これを「ロック="みず" で ほのお技 (STAB なし)」と比較し、
  // 初手 (発動技) には STAB が乗ることを pin する。
  let mv = pl_move(
    "かえんほうしゃ",
    type_="ほのお",
    category=@model.Special,
    power=90,
  )
  let attacker = pl_fanout_combatant(
    "attacker",
    mv,
    ability="へんげんじざい",
  )
  let defender = pl_fanout_combatant("defender", mv, ability="")
  let team = [attacker]
  let def_team = [defender]
  let ranks = [0, 0, 0, 0, 0, 0, 0]
  let cache_initial = new_damage_cache()
  let initial = pl_single_mean(
    damage_variants_cached(
      cache_initial,
      true,
      0,
      ranks,
      0,
      ranks,
      0,
      team,
      def_team,
      atk_protean_locked="",
    ),
  )
  let cache_locked_other = new_damage_cache()
  let locked_other = pl_single_mean(
    damage_variants_cached(
      cache_locked_other,
      true,
      0,
      ranks,
      0,
      ranks,
      0,
      team,
      def_team,
      atk_protean_locked="みず",
    ),
  )
  // 未ロック (= 発動技) は STAB あり、ロック後の別タイプ技は STAB なし。
  assert_true(initial > locked_other)
}

///|
test "protean defense: ロック後は変化後タイプで被弾 (相性が変わる)" {
  // defender base タイプ みず (みず技を 0.5x で半減)。攻撃側はノーマルの みず技。
  // (a) def ロックなし → みず ⇐ みず は 0.5x
  // (b) def ロック="ほのお" → override で defender type1=ほのお → みず ⇐ ほのお は 2x
  // ロック後のほうが大きく食らうはず。
  let mv = pl_move(
    "ハイドロポンプ",
    type_="みず",
    category=@model.Special,
    power=90,
  )
  let attacker = pl_fanout_combatant("attacker", mv, ability="")
  // defender base を みず 単タイプにする。pl_fanout_pokemon は ノーマル 固定なので
  // ここで type1 を上書きした combatant を作る。
  let def_base = pl_fanout_pokemon("defender")
  let def_water : @model.Pokemon = { ..def_base, type1: "みず", type2: "" }
  let defender : Combatant = {
    pokemon: def_water,
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
  let team = [attacker]
  let def_team = [defender]
  let ranks = [0, 0, 0, 0, 0, 0, 0]
  let cache_base = new_damage_cache()
  let base_dmg = pl_single_mean(
    damage_variants_cached(
      cache_base,
      true,
      0,
      ranks,
      0,
      ranks,
      0,
      team,
      def_team,
      def_protean_locked="",
    ),
  )
  let cache_locked = new_damage_cache()
  let locked_dmg = pl_single_mean(
    damage_variants_cached(
      cache_locked,
      true,
      0,
      ranks,
      0,
      ranks,
      0,
      team,
      def_team,
      def_protean_locked="ほのお",
    ),
  )
  // 0.5x → 2x の相性反転で 4 倍前後。少なくとも大きくなる。
  assert_true(locked_dmg > base_dmg)
}

///|
test "protean: テラス優先 (locked != \"\" でも tera が支配し override されない)" {
  // tera_type="みず" の Protean 使用者。locked="ほのお" を渡しても、
  // effective_combatant は tera 中は override しないので type1 はベースの ノーマル
  // のまま (tera 処理は engine の tera_type 経路に委ねる)。
  let base = pl_combatant(
    pl_pokemon("attacker", "ノーマル", "ひこう"),
    ability="へんげんじざい",
    tera_type="みず",
  )
  let eff = effective_combatant(base, false, protean_locked="ほのお")
  // override されないので元の 2 タイプがそのまま残る (単タイプ化していない)。
  @debug.assert_eq(eff.pokemon.type1, "ノーマル")
  @debug.assert_eq(eff.pokemon.type2, "ひこう")
  @debug.assert_eq(eff.tera_type, "みず")
}

///|
test "protean: tera 無しなら locked で単タイプへ override" {
  // 対照: tera_type="" のとき locked="ほのお" は type1=ほのお, type2="" へ override。
  let base = pl_combatant(
    pl_pokemon("attacker", "ノーマル", "ひこう"),
    ability="へんげんじざい",
  )
  let eff = effective_combatant(base, false, protean_locked="ほのお")
  @debug.assert_eq(eff.pokemon.type1, "ほのお")
  @debug.assert_eq(eff.pokemon.type2, "")
}

///|
test "protean: locked=\"\" は override 無し (従来挙動を維持)" {
  // 既定 "" のとき override されず元の combatant をそのまま返す。
  let base = pl_combatant(
    pl_pokemon("attacker", "ノーマル", "ひこう"),
    ability="へんげんじざい",
  )
  let eff = effective_combatant(base, false)
  @debug.assert_eq(eff.pokemon.type1, "ノーマル")
  @debug.assert_eq(eff.pokemon.type2, "ひこう")
}

// ============================================================================
// Stage 4: switch-out で Protean ロックがリセットされる。出ていくスロットは
// 再登場時に "" へ戻り、Protean を再発動できる。leech_seeded の switch 剥がし
// (transition_with_cache の Switch arm / partial_act_outcomes の Switch arm)
// を完全ミラーする。
// ============================================================================

///|
/// Stage 4 用: moves を 1 本持たせた Protean Combatant。transition_with_cache
/// の UseMove arm が `my_team[active].moves[mi]` を読むため、再発動テストでは
/// 技付きの combatant が必要。
fn pl_move_combatant(
  name : String,
  type1 : String,
  mv : @model.Move,
  ability? : String = "へんげんじざい",
) -> Combatant {
  {
    pokemon: pl_pokemon(name, type1, ""),
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
test "protean: 交代で出ていくスロットのロックが解除される (transition_with_cache)" {
  // my[0] が "ほのお" でロック済み。my[0]→my[1] へ Switch すると、出ていった
  // my[0] の protean_locked が "" に戻る。opp 側は Switch (テスト都合) でも、
  // opp は未ロックなので不変。
  let attacker = pl_combatant(
    pl_pokemon("attacker", "ノーマル", ""),
    ability="へんげんじざい",
  )
  let defender = pl_combatant(pl_pokemon("defender", "ノーマル", ""))
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let state = { ..pl_state(), my_protean_locked: ["ほのお", "", ""] }
  let cache = new_damage_cache()
  let outs = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::Switch(0),
    team,
    def_team,
    cache,
  )
  // Switch+Switch は確率 1.0 の単一決定的遷移。
  @debug.assert_eq(outs.length(), 1)
  let (_, new_state) = outs[0]
  @debug.assert_eq(new_state.my_protean_locked[0], "")
  // 控えに下がった先 (my[1]) はもともと "" なので不変。
  @debug.assert_eq(new_state.my_protean_locked[1], "")
  @debug.assert_eq(new_state.my_active, 1)
}

///|
test "protean: 交代で出ていくスロットのロックが解除される (partial_act_outcomes)" {
  // 片側のみ行動する partial path でも Switch-out でロックが剥がれる。
  // opp[0] が "みず" でロック済み、opp のみ Switch (me_is_actor=false)。
  let attacker = pl_combatant(
    pl_pokemon("attacker", "ノーマル", ""),
    ability="へんげんじざい",
  )
  let defender = pl_combatant(pl_pokemon("defender", "ノーマル", ""))
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let state = { ..pl_state(), opp_protean_locked: ["みず", "", ""] }
  let cache = new_damage_cache()
  let outs = partial_act_outcomes(
    state,
    ActionKind::Switch(1),
    false,
    team,
    def_team,
    cache,
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, new_state) = outs[0]
  @debug.assert_eq(new_state.opp_protean_locked[0], "")
  @debug.assert_eq(new_state.opp_active, 1)
  // my 側は何もしていないので不変。
  @debug.assert_eq(new_state.my_protean_locked[0], "")
}

///|
test "protean: 交代→再登場で再発動できる" {
  // my[0] が "ほのお" ロック済み → my[0]→my[1] へ Switch out で my[0] が "" に
  // 戻る → 後ターンで my[1]→my[0] へ Switch back で my[0] は "" のまま → さらに
  // 後ターンで my[0] が みず技を撃つと、新しいタイプ "みず" で再ロックされる。
  let water_move = pl_move(
    "ハイドロポンプ",
    type_="みず",
    category=@model.Special,
    power=90,
  )
  let attacker = pl_move_combatant("attacker", "ノーマル", water_move)
  let defender = pl_move_combatant(
    "defender",
    "ノーマル",
    water_move,
    ability="",
  )
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let state = { ..pl_state(), my_protean_locked: ["ほのお", "", ""] }
  let cache = new_damage_cache()
  // 1) my[0]→my[1] へ switch out。opp も Switch (テスト都合)。
  let outs1 = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::Switch(0),
    team,
    def_team,
    cache,
  )
  @debug.assert_eq(outs1.length(), 1)
  let (_, after_out) = outs1[0]
  @debug.assert_eq(after_out.my_protean_locked[0], "")
  @debug.assert_eq(after_out.my_active, 1)
  // 2) my[1]→my[0] へ switch back。my[0] は "" のまま (slot-scoped 永続)。
  let outs2 = transition_with_cache(
    after_out,
    ActionKind::Switch(0),
    ActionKind::Switch(0),
    team,
    def_team,
    cache,
  )
  @debug.assert_eq(outs2.length(), 1)
  let (_, after_back) = outs2[0]
  @debug.assert_eq(after_back.my_protean_locked[0], "")
  @debug.assert_eq(after_back.my_active, 0)
  // 3) my[0] が みず技を撃つ。再登場後なので新しいタイプ "みず" で再ロック。
  let outs3 = transition_with_cache(
    after_back,
    ActionKind::UseMove(0),
    ActionKind::Switch(0),
    team,
    def_team,
    cache,
  )
  assert_true(outs3.length() >= 1)
  for i = 0; i < outs3.length(); i = i + 1 {
    let (_, s) = outs3[i]
    @debug.assert_eq(s.my_protean_locked[0], "みず")
  }
}

///|
test "protean: 非交代ターンではロックが維持される" {
  // 対照 pin: UseMove だけのターン (Switch を含まない) では既存ロックが
  // リセットされない。my[0] が "ほのお" ロック済みで みず技を撃っても、
  // once-per-switch-in により再ロックされず "ほのお" のまま (= 維持)。
  let water_move = pl_move(
    "ハイドロポンプ",
    type_="みず",
    category=@model.Special,
    power=90,
  )
  let attacker = pl_move_combatant("attacker", "ノーマル", water_move)
  let defender = pl_move_combatant(
    "defender",
    "ノーマル",
    water_move,
    ability="",
  )
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let state = { ..pl_state(), my_protean_locked: ["ほのお", "", ""] }
  let cache = new_damage_cache()
  let outs = transition_with_cache(
    state,
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    team,
    def_team,
    cache,
  )
  assert_true(outs.length() >= 1)
  for i = 0; i < outs.length(); i = i + 1 {
    let (_, s) = outs[i]
    @debug.assert_eq(s.my_protean_locked[0], "ほのお")
  }
}

// ============================================================================
// Stage 5: メガ進化が Protean ロックをリセットし再発動可能にする。メガすると
// タイプが base に戻り Protean が再び発動する (= 引っ込めて出し直しと等価)。
// さらに「メガで初めて Protean を得る」(base 特性 ≠ メガ特性) ケースも実効特性
// 判定でカバーされる。
// ============================================================================

///|
/// Stage 5 用: mega_form を持つ Protean Combatant。base/mega それぞれの ability を
/// 指定できる。moves は 1 本 (Mega(0)/UseMove(0) が moves[0] を読む)。
fn pl_mega_combatant(
  name : String,
  type1 : String,
  mv : @model.Move,
  base_ability~ : String,
  mega_ability~ : String,
  mega_type1? : String = "ノーマル",
  mega_type2? : String = "",
) -> Combatant {
  let mega_form : @model.MegaForm = {
    atk: 120,
    def_: 120,
    spa: 120,
    spd: 120,
    spe: 120,
    type1: mega_type1,
    type2: mega_type2,
    ability: mega_ability,
    name_ja: "メガ" + name,
  }
  {
    pokemon: pl_pokemon(name, type1, ""),
    moves: [mv],
    ability: base_ability,
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: Some(mega_form),
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
}

///|
test "protean: メガでロックがリセットされ再発動する" {
  // base/mega 共に へんげんじざい。my[0] が pre-mega で "ほのお" ロック済みの
  // 状態から、Mega + みず技 を適用すると、mega トリガで "" にリセットされた後
  // その技で新タイプ "みず" に再ロックされるはず。リセットが無いと
  // once-per-switch-in で "ほのお" のまま残ってしまう。
  let water_move = pl_move(
    "ハイドロポンプ",
    type_="みず",
    category=@model.Special,
    power=90,
  )
  let attacker = pl_mega_combatant(
    "attacker",
    "ノーマル",
    water_move,
    base_ability="へんげんじざい",
    mega_ability="へんげんじざい",
  )
  let defender = pl_move_combatant(
    "defender",
    "ノーマル",
    water_move,
    ability="",
  )
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let state = { ..pl_state(), my_protean_locked: ["ほのお", "", ""] }
  let cache = new_damage_cache()
  let outs = transition_with_cache(
    state,
    ActionKind::Mega(0),
    ActionKind::UseMove(0),
    team,
    def_team,
    cache,
  )
  assert_true(outs.length() >= 1)
  for i = 0; i < outs.length(); i = i + 1 {
    let (_, s) = outs[i]
    @debug.assert_eq(s.my_protean_locked[0], "みず")
    @debug.assert_eq(s.my_megaed[0], true)
  }
}

///|
test "protean: メガ発動技に STAB が乗る" {
  // メガ発動技は protean_consumed=false 経路 (リセット済み) で撃たれ、未ロック
  // の Protean gate により技タイプが STAB へ push される。これを「同条件で
  // pre-mega ロックを別タイプに残した場合」と相対比較する。
  //   (a) Mega + みず技, pre-lock="ほのお" → mega リセットで "" → 発動技は
  //       未ロック扱いで STAB あり
  //   (b) Mega なし (UseMove) + みず技, lock="てつ" など別タイプを残す → STAB なし
  // STAB 有無のみが差となるよう、mega_form の stats は base と等しくし
  // (mega による攻撃数値変動を排除)、同じ技・同じ防御側で比較する。
  let water_move = pl_move(
    "ハイドロポンプ",
    type_="みず",
    category=@model.Special,
    power=90,
  )
  // mega_form stats を base と同一 (100) にして mega の数値影響を消す。
  let mega_form : @model.MegaForm = {
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    type1: "ノーマル",
    type2: "",
    ability: "へんげんじざい",
    name_ja: "メガattacker",
  }
  let mega_attacker : Combatant = {
    pokemon: pl_pokemon("attacker", "ノーマル", ""),
    moves: [water_move],
    ability: "へんげんじざい",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: Some(mega_form),
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
  let defender = pl_move_combatant(
    "defender",
    "ノーマル",
    water_move,
    ability="",
  )
  let team = [mega_attacker, mega_attacker, mega_attacker]
  let def_team = [defender, defender, defender]
  // (a) Mega + みず技。pre-lock を別タイプ "ほのお" にしておく。
  let state_stab = { ..pl_state(), my_protean_locked: ["ほのお", "", ""] }
  let cache_stab = new_damage_cache()
  let outs_stab = transition_with_cache(
    state_stab,
    ActionKind::Mega(0),
    ActionKind::UseMove(0),
    team,
    def_team,
    cache_stab,
  )
  // (b) Mega なし + みず技。別タイプ "でんき" ロックを残す → STAB 無し。
  let state_nostab = { ..pl_state(), my_protean_locked: ["でんき", "", ""] }
  let cache_nostab = new_damage_cache()
  let outs_nostab = transition_with_cache(
    state_nostab,
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    team,
    def_team,
    cache_nostab,
  )
  let dmg_stab = state_stab.opp_hps[0] - outs_stab[0].1.opp_hps[0]
  let dmg_nostab = state_nostab.opp_hps[0] - outs_nostab[0].1.opp_hps[0]
  // mega 発動技は STAB (1.5x) が乗るぶん大きい。
  assert_true(dmg_stab > dmg_nostab)
}

///|
test "protean: メガで初めて Protean を得る (base げきりゅう → mega へんげんじざい)" {
  // base ability=げきりゅう (非 Protean)、mega_form.ability=へんげんじざい。
  // メガして技を撃つと、実効特性が Protean なのでロックされるはず。実装2
  // (実効特性での発動判定) が無いと base ability=げきりゅう を見て記録漏れし、
  // locked="" のまま残る (= RED)。
  let water_move = pl_move(
    "ハイドロポンプ",
    type_="みず",
    category=@model.Special,
    power=90,
  )
  let attacker = pl_mega_combatant(
    "attacker",
    "みず",
    water_move,
    base_ability="げきりゅう",
    mega_ability="へんげんじざい",
  )
  let defender = pl_move_combatant(
    "defender",
    "ノーマル",
    water_move,
    ability="",
  )
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let cache = new_damage_cache()
  let outs = transition_with_cache(
    pl_state(),
    ActionKind::Mega(0),
    ActionKind::UseMove(0),
    team,
    def_team,
    cache,
  )
  assert_true(outs.length() >= 1)
  for i = 0; i < outs.length(); i = i + 1 {
    let (_, s) = outs[i]
    @debug.assert_eq(s.my_protean_locked[0], "みず")
    @debug.assert_eq(s.my_megaed[0], true)
  }
}

///|
test "protean: メガ + Status 技でもロックは記録される" {
  // mega + 変化技 (category=Status) でも STAB は無関係だが、実効特性が Protean
  // (mega_form.ability) なら mv.type_ でロックが記録される。base ability は
  // 非 Protein にして、mega で初めて得るケースも兼ねる。
  let status_move = pl_move(
    "でんこうそうげき",
    type_="でんき",
    category=@model.Status,
    power=0,
  )
  let attacker = pl_mega_combatant(
    "attacker",
    "ノーマル",
    status_move,
    base_ability="ちくでん",
    mega_ability="リベロ",
  )
  let defender = pl_move_combatant(
    "defender",
    "ノーマル",
    status_move,
    ability="",
  )
  let team = [attacker, attacker, attacker]
  let def_team = [defender, defender, defender]
  let cache = new_damage_cache()
  let outs = transition_with_cache(
    pl_state(),
    ActionKind::Mega(0),
    ActionKind::UseMove(0),
    team,
    def_team,
    cache,
  )
  assert_true(outs.length() >= 1)
  for i = 0; i < outs.length(); i = i + 1 {
    let (_, s) = outs[i]
    @debug.assert_eq(s.my_protean_locked[0], "でんき")
    @debug.assert_eq(s.my_megaed[0], true)
  }
}
