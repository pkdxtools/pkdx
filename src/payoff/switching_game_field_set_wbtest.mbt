///|
/// Stage E (field-setting moves + Field counter tick) wbtest 群。
///
/// `with_post_hit_effects` 末尾で `mv.field_set` を消費して
/// `state.field` / `state.field_turns_left` を書き換え、`apply_eot` 末尾で
/// field counter を tick する。Weather と完全対称の構造で実装し、本ファイル
/// は weather_set テスト (`switching_game_healing_wbtest.mbt` Stage 5 セクション)
/// と隣接する形で field 版 set / tick / reset / overwrite の境界を pin する。
///
/// 取り扱う field は 4 種類: Electric / Grassy / Misty / Psychic。
/// 持続: base 5 ターン固定 (Terrain Extender は別 PR)。

///|
/// Stage E 用の最小 Combatant ヘルパー。Stage 5 の `mk_weather_combatant`
/// と同じ pokemon を使うが、ファイル間共有を避けるため per-file 定義。
fn mk_field_combatant() -> Combatant {
  let p : @model.Pokemon = {
    global_no: "0001",
    name_ja: "テスト",
    name_en: "Test",
    type1: "ノーマル",
    type2: "",
    hp: 100,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 600,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 1.0,
    forms: [],
  }
  {
    pokemon: p,
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: Some([100, 100, 100, 100, 100, 100]),
    ivs: None,
  }
}

///|
/// Stage E 用の baseline state。HP は両側 100/100 で満タン、weather/field とも
/// None。個別テストでこの state を渡し、with_post_hit_effects / apply_eot の
/// 戻り値で field を assert する。
fn mk_field_state() -> SwitchingGameState {
  {
    my_active: 0,
    opp_active: 0,
    my_hps: [100, 100],
    opp_hps: [100, 100],
    my_ranks: [0, 0, 0, 0, 0],
    opp_ranks: [0, 0, 0, 0, 0],
    my_mega_used: false,
    opp_mega_used: false,
    my_megaed: [false, false],
    opp_megaed: [false, false],
    my_status: [@model.None, @model.None],
    opp_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    opp_must_recharge: [false, false],
    my_item_consumed: [false, false],
    opp_item_consumed: [false, false],
    my_moves_used: [],
    opp_moves_used: [],
    weather: @model.Weather::None,
    weather_turns_left: 0,
    my_leech_seeded: [false, false],
    opp_leech_seeded: [false, false],
    my_wish_turns: -1,
    opp_wish_turns: -1,
    field: @model.Field::None,
    field_turns_left: 0,
    turn: 0,
  }
}

///|
/// Stage E 用の field 設定技ヘルパー。`mk_heal_move` が field_set 引数を
/// 受けないため、本ファイル内では `mk_heal_move` を呼んだ上で field_set を
/// override した struct を返す。
fn mk_field_move(name : String, type_ : String, fld : @model.Field) -> @model.Move {
  { ..mk_heal_move(name, type_, @model.Status, 0), field_set: Some(fld) }
}

// =================================================================
// E-1: with_post_hit_effects が mv.field_set を消費し、state.field と
// state.field_turns_left を書き換える。
// =================================================================

///|
/// Case E-A1: エレキフィールドを撃つと state.field = Electric、
/// field_turns_left = 5 に書き換わる。HP / weather は不変。
test "with_post_hit_effects: エレキフィールド sets field=Electric, turns_left=5" {
  let state = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("エレキフィールド", "でんき", @model.Field::Electric)
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.field, @model.Field::Electric)
  @debug.assert_eq(new_state.field_turns_left, 5)
  // HP は不変 (field 設定技は補助技で damage を与えない)。
  @debug.assert_eq(new_state.my_hps[0], 100)
  @debug.assert_eq(new_state.opp_hps[0], 100)
  // weather は不変 (field と weather は独立 state)。
  @debug.assert_eq(new_state.weather, @model.Weather::None)
  @debug.assert_eq(new_state.weather_turns_left, 0)
}

///|
/// Case E-A2: グラスフィールド → Grassy / 5 ターン。
test "with_post_hit_effects: グラスフィールド sets field=Grassy, turns_left=5" {
  let state = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("グラスフィールド", "くさ", @model.Field::Grassy)
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.field, @model.Field::Grassy)
  @debug.assert_eq(new_state.field_turns_left, 5)
}

///|
/// Case E-A3: ミストフィールド → Misty / 5 ターン。
test "with_post_hit_effects: ミストフィールド sets field=Misty, turns_left=5" {
  let state = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("ミストフィールド", "フェアリー", @model.Field::Misty)
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.field, @model.Field::Misty)
  @debug.assert_eq(new_state.field_turns_left, 5)
}

///|
/// Case E-A4: サイコフィールド → Psychic / 5 ターン。
test "with_post_hit_effects: サイコフィールド sets field=Psychic, turns_left=5" {
  let state = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("サイコフィールド", "エスパー", @model.Field::Psychic)
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.field, @model.Field::Psychic)
  @debug.assert_eq(new_state.field_turns_left, 5)
}

///|
/// 対戦相手 (opp 側) が field 技を撃った場合も同様に field を書き換える。
/// attacker_is_me=false でも field フィールドはサイド非依存なので同じ。
test "with_post_hit_effects: opp 側の エレキフィールド も field を書き換える" {
  let state = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("エレキフィールド", "でんき", @model.Field::Electric)
  let new_state = with_post_hit_effects(state, false, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.field, @model.Field::Electric)
  @debug.assert_eq(new_state.field_turns_left, 5)
}

///|
/// 既存挙動が崩れないこと: field を持たない通常技 (じしん) は field を一切
/// 書き換えない。field 処理が誤って全 with_post_hit_effects 呼び出しで発火
/// していないことを negative pin。
test "with_post_hit_effects: 通常技は field を書き換えない" {
  let mut state = mk_field_state()
  state = { ..state, field: @model.Field::Electric, field_turns_left: 3 }
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_heal_move("じしん", "じめん", @model.Physical, 100)
  let new_state = with_post_hit_effects(state, true, 0, 0, team, team, mv, 0)
  @debug.assert_eq(new_state.field, @model.Field::Electric)
  @debug.assert_eq(new_state.field_turns_left, 3)
}

// =================================================================
// E-2: apply_eot が field_turns_left を tick し、0 になったら field=None
// にリセット。
// =================================================================

///|
/// Case E-B: エレキフィールド使用直後の state に対し apply_eot を 1 回呼ぶと
/// field_turns_left=5 → 4、field=Electric は維持される。
test "apply_eot: field counter decrement by 1 (5 → 4, Electric keeps)" {
  let state0 = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("エレキフィールド", "でんき", @model.Field::Electric)
  let state_after_set = with_post_hit_effects(
    state0, true, 0, 0, team, team, mv, 0,
  )
  @debug.assert_eq(state_after_set.field_turns_left, 5)
  let state_after_eot = apply_eot(state_after_set, team, team)
  @debug.assert_eq(state_after_eot.field, @model.Field::Electric)
  @debug.assert_eq(state_after_eot.field_turns_left, 4)
}

///|
/// Case E-C: エレキフィールド使用 + 5 EOT 経過で field_turns_left=0、
/// field=None にリセットされる。境界: 5 EOT で 0 へ落とした時点で
/// `field=None` に切り替える (Weather と完全対称)。
test "apply_eot: エレキフィールド expires after 5 EOTs (Electric → None)" {
  let state0 = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("エレキフィールド", "でんき", @model.Field::Electric)
  let mut state = with_post_hit_effects(state0, true, 0, 0, team, team, mv, 0)
  // 4 EOT 経過後: turns_left=1, field=Electric (まだ持続)
  for _ in 0..<4 {
    state = apply_eot(state, team, team)
  }
  @debug.assert_eq(state.field, @model.Field::Electric)
  @debug.assert_eq(state.field_turns_left, 1)
  // 5 EOT 目: turns_left=0 + field=None にリセット
  state = apply_eot(state, team, team)
  @debug.assert_eq(state.field, @model.Field::None)
  @debug.assert_eq(state.field_turns_left, 0)
}

///|
/// Case E-C-extra: field 切れ後の追加 EOT は field=None / turns_left=0 で
/// idempotent。0 を下回って負値にならないこと、None 状態で再度 None に落ち
/// ないことを pin。
test "apply_eot: field=None / turns_left=0 is fixpoint" {
  let state0 = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let state1 = apply_eot(state0, team, team)
  @debug.assert_eq(state1.field, @model.Field::None)
  @debug.assert_eq(state1.field_turns_left, 0)
  let state2 = apply_eot(state1, team, team)
  @debug.assert_eq(state2.field, @model.Field::None)
  @debug.assert_eq(state2.field_turns_left, 0)
}

// =================================================================
// E-3: 4 フィールドの set / tick / reset の境界 test
// =================================================================
//
// 各 field について以下を pin:
//   - set: state.field=X, field_turns_left=5
//   - tick: 5 ターン後に field=None (上記 E-2 で代表として Electric を pin)
//   - reset: tick 途中で同じ field 技を再使用すると field_turns_left=5 に
//     リセット
//   - cross-field overwrite: 別 field 技を撃つと state.field が新 field に
//     上書きされ field_turns_left=5

///|
/// Case E-D-1: 同じ field 技の再使用で field_turns_left がリセット。
/// エレキフィールド → 3 EOT 経過 (turns_left=2) → エレキフィールド再使用 →
/// turns_left=5 にリセット (1 にデクリメントされない)。Weather と同じ
/// later-wins semantics。
test "with_post_hit_effects: 同じ field 技再使用で field_turns_left=5 にリセット" {
  let state0 = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("エレキフィールド", "でんき", @model.Field::Electric)
  let mut state = with_post_hit_effects(state0, true, 0, 0, team, team, mv, 0)
  // 3 EOT 経過: turns_left = 5 → 4 → 3 → 2
  for _ in 0..<3 {
    state = apply_eot(state, team, team)
  }
  @debug.assert_eq(state.field, @model.Field::Electric)
  @debug.assert_eq(state.field_turns_left, 2)
  // 同じエレキフィールドを再使用 → turns_left=5 にリセット
  let state_after_reset = with_post_hit_effects(
    state, true, 0, 0, team, team, mv, 0,
  )
  @debug.assert_eq(state_after_reset.field, @model.Field::Electric)
  @debug.assert_eq(state_after_reset.field_turns_left, 5)
}

///|
/// Case E-D-2: 別 field 技で上書き (cross-field overwrite)。
/// エレキフィールド中に グラスフィールド を撃つと state.field=Grassy、
/// field_turns_left=5 になる。
test "with_post_hit_effects: 別 field 技で cross-field overwrite (Electric → Grassy)" {
  let state0 = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let elec_mv = mk_field_move("エレキフィールド", "でんき", @model.Field::Electric)
  let grass_mv = mk_field_move("グラスフィールド", "くさ", @model.Field::Grassy)
  let state_after_elec = with_post_hit_effects(
    state0, true, 0, 0, team, team, elec_mv, 0,
  )
  @debug.assert_eq(state_after_elec.field, @model.Field::Electric)
  @debug.assert_eq(state_after_elec.field_turns_left, 5)
  // 同じ ply ではないが連続使用で state.field を上書き。Weather と同じ。
  let state_after_grass = with_post_hit_effects(
    state_after_elec, true, 0, 0, team, team, grass_mv, 0,
  )
  @debug.assert_eq(state_after_grass.field, @model.Field::Grassy)
  @debug.assert_eq(state_after_grass.field_turns_left, 5)
}

///|
/// Case E-D-3: グラスフィールド → 5 EOT で None。
test "apply_eot: グラスフィールド expires after 5 EOTs (Grassy → None)" {
  let state0 = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("グラスフィールド", "くさ", @model.Field::Grassy)
  let mut state = with_post_hit_effects(state0, true, 0, 0, team, team, mv, 0)
  for _ in 0..<5 {
    state = apply_eot(state, team, team)
  }
  @debug.assert_eq(state.field, @model.Field::None)
  @debug.assert_eq(state.field_turns_left, 0)
}

///|
/// Case E-D-4: ミストフィールド → 5 EOT で None。
test "apply_eot: ミストフィールド expires after 5 EOTs (Misty → None)" {
  let state0 = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("ミストフィールド", "フェアリー", @model.Field::Misty)
  let mut state = with_post_hit_effects(state0, true, 0, 0, team, team, mv, 0)
  for _ in 0..<5 {
    state = apply_eot(state, team, team)
  }
  @debug.assert_eq(state.field, @model.Field::None)
  @debug.assert_eq(state.field_turns_left, 0)
}

///|
/// Case E-D-5: サイコフィールド → 5 EOT で None。
test "apply_eot: サイコフィールド expires after 5 EOTs (Psychic → None)" {
  let state0 = mk_field_state()
  let team = [mk_field_combatant(), mk_field_combatant()]
  let mv = mk_field_move("サイコフィールド", "エスパー", @model.Field::Psychic)
  let mut state = with_post_hit_effects(state0, true, 0, 0, team, team, mv, 0)
  for _ in 0..<5 {
    state = apply_eot(state, team, team)
  }
  @debug.assert_eq(state.field, @model.Field::None)
  @debug.assert_eq(state.field_turns_left, 0)
}
