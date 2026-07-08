///|
/// 登場時いかくの DP 配線テスト。`apply_intimidate_on_entry` の分岐網羅は
/// entry_abilities_test.mbt が担うので、ここでは entry 経路
/// (transition_with_cache の 3 arm / partial_act_outcomes の 2 arm / 初期 lead)
/// で確実に発動すること・mega 後の実効特性で判定されることのみを pin する。

///|
fn im_pokemon(
  name : String,
  hp? : Int = 100,
  atk? : Int = 100,
  def_? : Int = 100,
  spe? : Int = 100,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1: "ノーマル",
    type2: "",
    hp,
    atk,
    def_,
    spa: 100,
    spd: 100,
    spe,
    bst: hp + atk + def_ + 200 + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
}

///|
fn im_combatant(
  pokemon : @model.Pokemon,
  moves : Array[@model.Move],
  ability? : String = "",
  mega_form? : @model.MegaForm? = None,
) -> Combatant {
  {
    pokemon,
    moves,
    ability,
    item: "",
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
fn im_state(
  my_hps? : Array[Int] = [100, 100, 100],
  opp_hps? : Array[Int] = [100, 100, 100],
  my_megaed? : Array[Bool] = [false, false, false],
  my_mega_used? : Bool = false,
) -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps,
    opp_hps,
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used,
    opp_mega_used: false,
    my_megaed,
    opp_megaed: [false, false, false],
    my_status: [@model.None, @model.None, @model.None],
    opp_status: [@model.None, @model.None, @model.None],
    my_must_recharge: [false, false, false],
    opp_must_recharge: [false, false, false],
    my_item_consumed: [false, false, false],
    my_disguise_busted: [false, false, false],
    opp_item_consumed: [false, false, false],
    opp_disguise_busted: [false, false, false],
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
fn im_tackle() -> @model.Move {
  mk_move("たいあたり", "ノーマル", @model.Physical, 60)
}

///|
test "いかく: 双方同時交代で両 active の A が -1 (Switch,Switch)" {
  let mv = im_tackle()
  let intimidator = im_combatant(
    im_pokemon("いかく持ち"),
    [mv],
    ability="いかく",
  )
  let plain = im_combatant(im_pokemon("ふつう"), [mv])
  let my_team = [plain, intimidator, plain]
  let opp_team = [plain, intimidator, plain]
  let outs = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::Switch(1),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  @debug.assert_eq(s.my_ranks[0], -1)
  @debug.assert_eq(s.opp_ranks[0], -1)
}

///|
test "いかく: 片側のみ持つ場合は相手 active のみ A -1 (Switch,Switch)" {
  let mv = im_tackle()
  let intimidator = im_combatant(
    im_pokemon("いかく持ち"),
    [mv],
    ability="いかく",
  )
  let plain = im_combatant(im_pokemon("ふつう"), [mv])
  let my_team = [plain, intimidator, plain]
  let opp_team = [plain, plain, plain]
  let outs = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::Switch(1),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  @debug.assert_eq(s.opp_ranks[0], -1)
  @debug.assert_eq(s.my_ranks[0], 0)
}

///|
test "いかく: 交代先へ飛ぶ物理技が A-1 で計算される (Switch,UseMove)" {
  // 交代→いかく→技 の本家順序: いかく持ちへの交代に合わせて撃たれる opp の
  // 物理技は A-1 の opp_ranks で計算され、非いかく時より被ダメが減る。
  let mv = im_tackle()
  let plain = im_combatant(im_pokemon("ふつう"), [mv])
  let intim_target = im_combatant(
    im_pokemon("いかく持ち"),
    [mv],
    ability="いかく",
  )
  let attacker = im_combatant(im_pokemon("アタッカー", atk=120), [mv])
  let opp_team = [attacker, attacker, attacker]
  let team_intim = [plain, intim_target, plain]
  let outs_intim = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    team_intim,
    opp_team,
    new_damage_cache(),
  )
  let team_plain = [plain, plain, plain]
  let outs_plain = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    team_plain,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs_intim.length(), 1)
  @debug.assert_eq(outs_plain.length(), 1)
  let (_, s_intim) = outs_intim[0]
  let (_, s_plain) = outs_plain[0]
  @debug.assert_eq(s_intim.opp_ranks[0], -1)
  // A-1 計算のぶん交代先 (my slot1) の残 HP が多い。damage 自体は入っている。
  assert_true(s_intim.my_hps[1] > s_plain.my_hps[1])
  assert_true(s_intim.my_hps[1] < 100)
}

///|
test "いかく: opp 交代先のいかくが my の物理技を A-1 にする (UseMove,Switch)" {
  // 対称ケース: opp がいかく持ちへ交代 → my の技は A-1 の my_ranks で計算され、
  // opp 交代先の被ダメが非いかく時より減る。
  let mv = im_tackle()
  let plain = im_combatant(im_pokemon("ふつう"), [mv])
  let intim_target = im_combatant(
    im_pokemon("いかく持ち"),
    [mv],
    ability="いかく",
  )
  let attacker = im_combatant(im_pokemon("アタッカー", atk=120), [mv])
  let my_team = [attacker, attacker, attacker]
  let opp_intim = [plain, intim_target, plain]
  let outs_intim = transition_with_cache(
    im_state(),
    ActionKind::UseMove(0),
    ActionKind::Switch(1),
    my_team,
    opp_intim,
    new_damage_cache(),
  )
  let opp_plain = [plain, plain, plain]
  let outs_plain = transition_with_cache(
    im_state(),
    ActionKind::UseMove(0),
    ActionKind::Switch(1),
    my_team,
    opp_plain,
    new_damage_cache(),
  )
  @debug.assert_eq(outs_intim.length(), 1)
  @debug.assert_eq(outs_plain.length(), 1)
  let (_, s_intim) = outs_intim[0]
  let (_, s_plain) = outs_plain[0]
  @debug.assert_eq(s_intim.my_ranks[0], -1)
  assert_true(s_intim.opp_hps[1] > s_plain.opp_hps[1])
  assert_true(s_intim.opp_hps[1] < 100)
}

///|
test "いかく: partial_act_outcomes (true,Switch) で opp active の A -1" {
  let mv = im_tackle()
  let plain = im_combatant(im_pokemon("ふつう"), [mv])
  let intimidator = im_combatant(
    im_pokemon("いかく持ち"),
    [mv],
    ability="いかく",
  )
  let my_team = [plain, intimidator, plain]
  let opp_team = [plain, plain, plain]
  let outs = partial_act_outcomes(
    im_state(),
    ActionKind::Switch(1),
    true,
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  @debug.assert_eq(s.opp_ranks[0], -1)
  @debug.assert_eq(s.my_ranks[0], 0)
}

///|
test "いかく: partial_act_outcomes (false,Switch) で my active の A -1" {
  let mv = im_tackle()
  let plain = im_combatant(im_pokemon("ふつう"), [mv])
  let intimidator = im_combatant(
    im_pokemon("いかく持ち"),
    [mv],
    ability="いかく",
  )
  let my_team = [plain, plain, plain]
  let opp_team = [plain, intimidator, plain]
  let outs = partial_act_outcomes(
    im_state(),
    ActionKind::Switch(1),
    false,
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  @debug.assert_eq(s.my_ranks[0], -1)
  @debug.assert_eq(s.opp_ranks[0], 0)
}

///|
test "いかく: 死に出し (forced switch) でも発動する" {
  // my active (slot0) が HP0。alive_actions は Switch のみを返すため、死に出し
  // は通常の (Switch,UseMove) arm を通る = 追加配線が不要なことを pin する。
  let mv = im_tackle()
  let plain = im_combatant(im_pokemon("ふつう"), [mv])
  let intimidator = im_combatant(
    im_pokemon("いかく持ち"),
    [mv],
    ability="いかく",
  )
  let attacker = im_combatant(im_pokemon("アタッカー", atk=120), [mv])
  let my_team = [plain, intimidator, plain]
  let opp_team = [attacker, attacker, attacker]
  let state = im_state(my_hps=[0, 100, 100])
  let acts = alive_actions(0, state.my_hps, my_team, false)
  @debug.assert_eq(acts.length(), 2)
  for a in acts {
    assert_true(
      match a {
        Switch(_) => true
        _ => false
      },
    )
  }
  let outs = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  @debug.assert_eq(s.opp_ranks[0], -1)
  @debug.assert_eq(s.my_active, 1)
}

///|
test "いかく: mega で得た いかく は megaed=true の再登場でのみ発動する" {
  // base 特性は非いかく / mega_form.ability="いかく"。megaed[slot]=true の
  // slot が交代で再登場すると実効特性 (mega 後) で判定され発動する。
  // megaed=false のままなら base 特性を見て非発動。
  let mv = im_tackle()
  let mega_form : @model.MegaForm = {
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    type1: "ノーマル",
    type2: "",
    ability: "いかく",
    name_ja: "メガいかく",
  }
  let mega_holder = im_combatant(
    im_pokemon("メガ個体"),
    [mv],
    ability="げきりゅう",
    mega_form=Some(mega_form),
  )
  let plain = im_combatant(im_pokemon("ふつう"), [mv])
  let attacker = im_combatant(im_pokemon("アタッカー", atk=120), [mv])
  let my_team = [plain, mega_holder, plain]
  let opp_team = [attacker, attacker, attacker]
  let state_mega = im_state(my_megaed=[false, true, false], my_mega_used=true)
  let outs_mega = transition_with_cache(
    state_mega,
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs_mega.length(), 1)
  @debug.assert_eq(outs_mega[0].1.opp_ranks[0], -1)
  let outs_base = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs_base.length(), 1)
  @debug.assert_eq(outs_base[0].1.opp_ranks[0], 0)
}

///|
test "いかく: ミラーアーマー target は entrant が A-1 / target 不変" {
  let mv = im_tackle()
  let plain = im_combatant(im_pokemon("ふつう"), [mv])
  let intimidator = im_combatant(
    im_pokemon("いかく持ち"),
    [mv],
    ability="いかく",
  )
  let mirror = im_combatant(
    im_pokemon("ミラー"),
    [mv],
    ability="ミラーアーマー",
  )
  let my_team = [plain, intimidator, plain]
  let opp_team = [mirror, mirror, mirror]
  let outs = transition_with_cache(
    im_state(),
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs.length(), 1)
  let (_, s) = outs[0]
  // 反射: entrant (my 側) の A が -1、target (opp 側) は不変。
  @debug.assert_eq(s.my_ranks[0], -1)
  @debug.assert_eq(s.opp_ranks[0], 0)
}

///|
test "いかく: 連続で浴びても A は -2 で飽和 (clamp)" {
  // いかく持ちを交互に出し入れして 3 回発動させても、payoff 層の reduced
  // range [-2,+2] の clamp により opp の A は -2 で止まる。
  let mv = im_tackle()
  let intimidator = im_combatant(
    im_pokemon("いかく持ち", hp=300),
    [mv],
    ability="いかく",
  )
  let receiver = im_combatant(im_pokemon("受け", hp=300), [mv])
  let my_team = [intimidator, intimidator, intimidator]
  let opp_team = [receiver, receiver, receiver]
  let state = im_state(my_hps=[300, 300, 300], opp_hps=[300, 300, 300])
  let outs1 = transition_with_cache(
    state,
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let s1 = outs1[0].1
  @debug.assert_eq(s1.opp_ranks[0], -1)
  let outs2 = transition_with_cache(
    s1,
    ActionKind::Switch(0),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  let s2 = outs2[0].1
  @debug.assert_eq(s2.opp_ranks[0], -2)
  let outs3 = transition_with_cache(
    s2,
    ActionKind::Switch(1),
    ActionKind::UseMove(0),
    my_team,
    opp_team,
    new_damage_cache(),
  )
  @debug.assert_eq(outs3[0].1.opp_ranks[0], -2)
}

///|
test "いかく: value-level — 物理アタッカー相手の value がいかく側に有利へ動く" {
  // 初期 lead の登場時いかくで my の A が -1 → my の与ダメが減り、my 視点の
  // value は「同条件・特性なし」より下がるはず。受け側は高 HP + 無威力技で
  // 双方 KO なしに固定し、terminal の HP 比率差だけを比較する。
  let tackle = im_tackle()
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let attacker = im_combatant(im_pokemon("ぶつりアタッカー", atk=120), [
    tackle,
  ])
  let intim_def = im_combatant(
    im_pokemon("うけがた", hp=300, def_=110, spe=60),
    [splash],
    ability="いかく",
  )
  let plain_def = im_combatant(
    im_pokemon("うけがた", hp=300, def_=110, spe=60),
    [splash],
  )
  let v_intim = switching_game_winrate([attacker], [intim_def], 4)
  let v_plain = switching_game_winrate([attacker], [plain_def], 4)
  assert_true(v_intim < v_plain)
}
