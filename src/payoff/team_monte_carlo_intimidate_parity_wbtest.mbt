///|
/// 登場時いかくの MC/DP parity テスト。DP 側 (switching_game_turn.mbt) は
/// transition の 3 Switch arm + partial_act_outcomes の 2 arm + 初期 lead で
/// `apply_intimidate_entry` を配線済み。本ファイルは MC rollout
/// (`team_rollout` / `team_monte_carlo_value`) 側の配線 (初期 lead + Step 2
/// switch 解決直後) が DP と同一セマンティクスであることを pin する。
/// `apply_intimidate_on_entry` の分岐網羅 (ばんけん / ミラーアーマー / びびり /
/// あまのじゃく / 無効化) は entry_abilities_test.mbt、DP 経路の発動確認は
/// switching_game_intimidate_wbtest.mbt が担う。
///
/// pin する観点 (protean parity テストと同 posture):
///   1. value-tol parity (own 側いかく): `|dp - mc| < 0.15` (sign-agreement
///      のみでは不可、value-tol 必須)。
///   2. value-tol parity (opp 側いかく): 対称。
///   3. 非いかくチームの no-op: ability="" と ability="あくしゅう" (いかく
///      以外の文字列、engine のどの分岐にも一致しない) で同 seed の MC 値が
///      bit 一致 = いかく配線が非いかく entrant に対して分岐・乱数消費を一切
///      変えないこと + 同 seed 再現の決定性。
///   4. MC 単体の方向性: いかく持ち入りチームの rollout 値が、同構成で特性を
///      外した場合より高い (物理相手で有利方向)。switch 経路 (wiring 箇所 2/3)
///      を通る 2 体構成で検証する。
///
/// 方針メモ: MC の greedy (`greedy_team_action`) は `best_expected_damage`
/// ベースで行動を選ぶため、「いかくを撃つために交代する」ことを見込まない
/// (DP の minimax は見込む)。この方策差は ε-greedy の探索と value-tol 0.15 が
/// 吸収する前提で、parity fixture は 1v1 (交代方策の乖離が出ない構成) に固定
/// している。

///|
/// **Case 1 (value-tol parity, own 側いかく)**: 1v1。own = いかく持ち物理受け
/// (無威力技のみ)、opp = 物理アタッカー。双方 KO なしの horizon で terminal
/// value = HP 比率差になる fixture なので、value が ±1 に飽和せず「opp の与ダメ
/// が A-1 で 2/3 になった量」がそのまま value に現れる。初期 lead で own の
/// いかくが opp の A を -1 → DP (`switching_game_winrate`, 初期 lead で適用)
/// と MC (`team_monte_carlo_value`, rollout 開始時に適用) が `|dp - mc| < 0.15`
/// で一致することを pin。fixture 感度ガードとして「いかく有無の DP 差 > 0.15」
/// も assert する — MC 側の lead 配線が無ければ mc はいかくなし側の値
/// (≈ dp_plain) に張り付き、parity が tol を超えて fail する構成であることの
/// 自己検証。
test "MC/DP value parity under lead Intimidate (own side)" {
  let wall_p = mk_pokemon(
    "IntimWall", "ノーマル", "", 280, 60, 105, 60, 105, 60,
  )
  let atk_p = mk_pokemon(
    "Basher", "ノーマル", "", 240, 130, 100, 95, 100, 110,
  )
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let tackle = mk_move("のしかかり", "ノーマル", @model.Physical, 80)
  let own = [pl_cmb(wall_p, [splash], ability="いかく")]
  let own_plain = [pl_cmb(wall_p, [splash])]
  let opp = [pl_cmb(atk_p, [tackle])]
  let turn_limit = 4
  let dp_value = switching_game_winrate(own, opp, turn_limit)
  let dp_plain = switching_game_winrate(own_plain, opp, turn_limit)
  // fixture 感度ガード: いかくの有無が tol を超えて value を動かす構成である
  // こと (= 飽和 fixture の「trivially |dp-mc|=0」を排除)。
  assert_true((dp_value - dp_plain).abs() > 0.15)
  let mc_value = team_monte_carlo_value(own, opp, 64, 4242UL, turn_limit~)
  let diff = (dp_value - mc_value).abs()
  assert_true(diff < 0.15)
}

///|
/// **Case 2 (value-tol parity, opp 側いかく)**: Case 1 の対称。opp = いかく
/// 持ち物理受け、own = 物理アタッカー。opp lead のいかくが own の A を -1 する
/// 方向でも DP / MC が value-tol で一致することを pin する。感度ガードも対称に
/// 置く。
test "MC/DP value parity under lead Intimidate (opp side)" {
  let atk_p = mk_pokemon(
    "Basher", "ノーマル", "", 240, 130, 100, 95, 100, 110,
  )
  let wall_p = mk_pokemon(
    "IntimWall", "ノーマル", "", 280, 60, 105, 60, 105, 60,
  )
  let tackle = mk_move("のしかかり", "ノーマル", @model.Physical, 80)
  let splash = mk_move("はねる", "ノーマル", @model.Status, 0)
  let own = [pl_cmb(atk_p, [tackle])]
  let opp = [pl_cmb(wall_p, [splash], ability="いかく")]
  let opp_plain = [pl_cmb(wall_p, [splash])]
  let turn_limit = 4
  let dp_value = switching_game_winrate(own, opp, turn_limit)
  let dp_plain = switching_game_winrate(own, opp_plain, turn_limit)
  assert_true((dp_value - dp_plain).abs() > 0.15)
  let mc_value = team_monte_carlo_value(own, opp, 64, 5151UL, turn_limit~)
  let diff = (dp_value - mc_value).abs()
  assert_true(diff < 0.15)
}

///|
/// **Case 3 (非いかくチームの no-op 証明)**: `apply_intimidate_on_entry` は
/// entrant が いかく 以外なら early return する。いかく配線が非いかくチームの
/// rollout に対して「分岐も乱数消費も一切変えない」ことを、
///   (a) ability="" チームと ability="あくしゅう" (どの engine 分岐にも一致
///       しない中立文字列) チームの同 seed MC 値が bit 一致すること
///   (b) 同 seed で 2 回呼んで bit 一致する決定性
/// の 2 点で pin する。
test "MC no-op: non-Intimidate team value is bit-exact across neutral abilities" {
  let own_p = mk_pokemon(
    "PlainA", "ノーマル", "", 200, 100, 100, 100, 100, 100,
  )
  let opp_p = mk_pokemon(
    "PlainB", "ノーマル", "", 200, 110, 95, 100, 100, 90,
  )
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 60)
  let opp = [pl_cmb(opp_p, [tackle])]
  // (a) entrant ability の文字列だけ変えても (いかく以外)、いかく配線は
  //     early return で完全 no-op → 同 seed で bit 一致。
  let own_empty = [pl_cmb(own_p, [tackle], ability="")]
  let own_stench = [pl_cmb(own_p, [tackle], ability="あくしゅう")]
  let v_empty = team_monte_carlo_value(
    own_empty,
    opp,
    64,
    31415UL,
    turn_limit=4,
  )
  let v_stench = team_monte_carlo_value(
    own_stench,
    opp,
    64,
    31415UL,
    turn_limit=4,
  )
  @debug.assert_eq(v_empty, v_stench)
  // (b) 同 seed 再現の決定性 (いかく配線が乱数列を変えていないことの control)。
  let v_again = team_monte_carlo_value(
    own_empty,
    opp,
    64,
    31415UL,
    turn_limit=4,
  )
  @debug.assert_eq(v_empty, v_again)
}

///|
/// **Case 4 (MC 単体の方向性 + switch 経路の発動)**: 2 体構成の own チーム
/// (先発は火力の低い個体、控えに物理タンク) vs 物理アタッカー 1 体。greedy は
/// タンクの期待与ダメが高いので交代 (voluntary switch) を選ぶか、先発が KO
/// されて死に出し (forced switch) でタンクが登場する — どちらの経路でも Step 2
/// の TmSwitch arm を通り、タンクのいかくが opp の A を -1 する。同 seed ・同
/// 構成で「タンクの特性 = いかく」の rollout 値が「特性なし」より高い (物理
/// 相手で被ダメ 2/3 のぶん HP 比率が有利) ことを pin する。lead はいかくを
/// 持たないため、初期 lead 配線ではなく switch 配線 (wiring 箇所 2/3) が値を
/// 動かしていることの直接確認になる。
test "MC direction: Intimidate switch-in improves rollout value vs physical attacker" {
  let frail_p = mk_pokemon("Frail", "ノーマル", "", 60, 60, 60, 60, 60, 50)
  let tank_p = mk_pokemon(
    "Tank", "ノーマル", "", 240, 100, 110, 90, 110, 80,
  )
  let atk_p = mk_pokemon(
    "Basher", "ノーマル", "", 220, 130, 95, 95, 100, 120,
  )
  let weak = mk_move("たいあたり", "ノーマル", @model.Physical, 30)
  let tackle = mk_move("のしかかり", "ノーマル", @model.Physical, 75)
  let bash = mk_move(
    "すてみタックル",
    "ノーマル",
    @model.Physical,
    90,
  )
  let opp = [pl_cmb(atk_p, [bash])]
  let own_intim = [
    pl_cmb(frail_p, [weak]),
    pl_cmb(tank_p, [tackle], ability="いかく"),
  ]
  let own_plain = [pl_cmb(frail_p, [weak]), pl_cmb(tank_p, [tackle])]
  let v_intim = team_monte_carlo_value(
    own_intim,
    opp,
    128,
    6060UL,
    turn_limit=6,
  )
  let v_plain = team_monte_carlo_value(
    own_plain,
    opp,
    128,
    6060UL,
    turn_limit=6,
  )
  assert_true(v_intim > v_plain)
}
