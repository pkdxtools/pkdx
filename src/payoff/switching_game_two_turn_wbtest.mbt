///|
/// 2ターン技。champout `50e7233` の wazainfo / BTR_STATE に合わせた分岐。

///|
fn tt_move(name : String, category : @model.MoveCategory, power : Int) -> @model.Move {
  flch_move(name, "ノーマル", category, power, 100, 0)
}

///|
fn tt_fast(mv : @model.Move) -> Array[Combatant] {
  [flch_cmb(flch_pokemon("fast", "ノーマル", 200, 120), [mv], "")]
}

///|
fn tt_slow(mv : @model.Move) -> Array[Combatant] {
  [flch_cmb(flch_pokemon("slow", "ノーマル", 200, 60), [mv], "")]
}

///|
fn tt_turn(
  state : SwitchingGameState,
  my_team : Array[Combatant],
  opp_team : Array[Combatant],
) -> Array[(Double, SwitchingGameState)] {
  attempt_turn_with_cache(
    state, UseMove(0), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
}

///|
fn tt_only(outs : Array[(Double, SwitchingGameState)]) -> SwitchingGameState {
  outs[0].1
}

///|
test "two turn names: charge and vanish are recognized, recharge and absent moves are not" {
  assert_true(is_two_turn_name("ソーラービーム"))
  assert_true(is_two_turn_name("ソーラーブレード"))
  assert_true(is_two_turn_name("エレクトロビーム"))
  assert_true(is_two_turn_name("メテオビーム"))
  assert_true(is_two_turn_name("ゴッドバード"))
  assert_true(is_two_turn_name("そらをとぶ"))
  assert_true(is_two_turn_name("とびはねる"))
  assert_true(is_two_turn_name("あなをほる"))
  assert_true(is_two_turn_name("ダイビング"))
  assert_true(is_two_turn_name("ゴーストダイブ"))
  assert_true(!is_two_turn_name("はかいこうせん"))
  assert_true(!is_two_turn_name("ロケットずつき"))
  assert_true(!is_two_turn_name("シャドーダイブ"))
  assert_true(!is_two_turn_name("たいあたり"))
}

///|
test "two turn power and hit table follow champout state text" {
  @debug.assert_eq(two_turn_power_mod("ソーラービーム", @model.Rain, ""), 2048)
  @debug.assert_eq(two_turn_power_mod("ソーラーブレード", @model.Sand, ""), 2048)
  @debug.assert_eq(two_turn_power_mod("ソーラービーム", @model.Snow, ""), 2048)
  @debug.assert_eq(two_turn_power_mod("ソーラービーム", @model.Sun, ""), 4096)
  @debug.assert_eq(two_turn_power_mod("ソーラービーム", @model.None, ""), 4096)
  @debug.assert_eq(two_turn_power_mod("じしん", @model.None, "あなをほる"), 8192)
  @debug.assert_eq(two_turn_power_mod("なみのり", @model.None, "ダイビング"), 8192)
  @debug.assert_eq(two_turn_power_mod("うずしお", @model.None, "ダイビング"), 8192)
  @debug.assert_eq(two_turn_power_mod("たいあたり", @model.None, ""), 4096)
  assert_true(two_turn_hits("かみなり", "そらをとぶ"))
  assert_true(two_turn_hits("ぼうふう", "とびはねる"))
  assert_true(two_turn_hits("うちおとす", "そらをとぶ"))
  assert_true(!two_turn_hits("たいあたり", "そらをとぶ"))
  assert_true(two_turn_hits("じしん", "あなをほる"))
  assert_true(!two_turn_hits("じしん", "ダイビング"))
  assert_true(!two_turn_hits("かみなり", "ゴーストダイブ"))
  assert_true(two_turn_hits("たいあたり", ""))
}

///|
test "solar beam charges without damage, then the locked move hits and clears" {
  let my_team = tt_fast(tt_move("ソーラービーム", @model.Special, 120))
  let opp_team = tt_slow(flch_tackle())
  let s0 = flch_state(200, 200, @model.None, @model.None)
  let s1 = tt_only(tt_turn(s0, my_team, opp_team))
  @debug.assert_eq(s1.opp_hps[0], 200)
  assert_true(s1.my_hps[0] < 200)
  @debug.assert_eq(s1.my_two_turn, 0)
  let actions = alive_actions(
    0, s1.my_hps, my_team, false, two_turn_lock=s1.my_two_turn,
  )
  @debug.assert_eq(actions.length(), 1)
  let s2 = tt_only(tt_turn(s1, my_team, opp_team))
  assert_true(s2.opp_hps[0] < 200)
  @debug.assert_eq(s2.my_two_turn, -1)
}

///|
test "solar beam in sun hits on the same turn and does not lock" {
  let my_team = tt_fast(tt_move("ソーラービーム", @model.Special, 120))
  let opp_team = tt_slow(flch_tackle())
  let s0 = { ..flch_state(200, 200, @model.None, @model.None), weather: @model.Sun }
  let s1 = tt_only(tt_turn(s0, my_team, opp_team))
  assert_true(s1.opp_hps[0] < 200)
  @debug.assert_eq(s1.my_two_turn, -1)
}

///|
test "electro shot in rain hits immediately and raises SpA" {
  let my_team = tt_fast(tt_move("エレクトロビーム", @model.Special, 130))
  let opp_team = tt_slow(flch_tackle())
  let s0 = { ..flch_state(200, 200, @model.None, @model.None), weather: @model.Rain }
  let s1 = tt_only(tt_turn(s0, my_team, opp_team))
  assert_true(s1.opp_hps[0] < 200)
  @debug.assert_eq(s1.my_ranks[2], 1)
  @debug.assert_eq(s1.my_two_turn, -1)
}

///|
test "meteor beam raises SpA on the charge turn and spends it on release" {
  let my_team = tt_fast(tt_move("メテオビーム", @model.Special, 120))
  let opp_team = tt_slow(flch_tackle())
  let s0 = flch_state(200, 200, @model.None, @model.None)
  let s1 = tt_only(tt_turn(s0, my_team, opp_team))
  @debug.assert_eq(s1.opp_hps[0], 200)
  @debug.assert_eq(s1.my_ranks[2], 1)
  @debug.assert_eq(s1.my_two_turn, 0)
  let s2 = tt_only(tt_turn(s1, my_team, opp_team))
  assert_true(s2.opp_hps[0] < 200)
  @debug.assert_eq(s2.my_ranks[2], 1)
  @debug.assert_eq(s2.my_two_turn, -1)
}

///|
test "faster fly vanishes before the slower tackle, so neither HP changes" {
  let my_team = tt_fast(tt_move("そらをとぶ", @model.Physical, 90))
  let opp_team = tt_slow(flch_tackle())
  let s1 = tt_only(tt_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team))
  @debug.assert_eq(s1.my_hps[0], 200)
  @debug.assert_eq(s1.opp_hps[0], 200)
  @debug.assert_eq(s1.my_two_turn, 0)
  let s2 = tt_only(tt_turn(s1, my_team, opp_team))
  assert_true(s2.opp_hps[0] < 200)
  @debug.assert_eq(s2.my_two_turn, -1)
}

///|
test "earthquake hits an underground target harder than a target that is not" {
  let my_team = tt_fast(tt_move("じしん", @model.Physical, 100))
  let opp_team = tt_slow(tt_move("あなをほる", @model.Physical, 80))
  let base = flch_state(200, 200, @model.None, @model.None)
  let underground = tt_only(tt_turn({ ..base, opp_two_turn: 0 }, my_team, opp_team))
  let charging = tt_only(tt_turn(base, my_team, opp_team))
  assert_true(underground.opp_hps[0] < charging.opp_hps[0])
  @debug.assert_eq(charging.opp_two_turn, 0)
  @debug.assert_eq(underground.opp_two_turn, -1)
}

///|
test "thunder hits sky-high and tackle does not" {
  let fly = tt_slow(tt_move("そらをとぶ", @model.Physical, 90))
  let locked = { ..flch_state(200, 200, @model.None, @model.None), opp_two_turn: 0 }
  let thunder = tt_only(tt_turn(locked, tt_fast(tt_move("かみなり", @model.Special, 110)), fly))
  let tackle = tt_only(tt_turn(locked, tt_fast(flch_tackle()), fly))
  assert_true(thunder.opp_hps[0] < 200)
  @debug.assert_eq(tackle.opp_hps[0], 200)
}

///|
test "sleep on the release turn drops the lock and the vanished target stays missed" {
  let my_team = tt_fast(flch_tackle())
  let opp_team = tt_slow(tt_move("そらをとぶ", @model.Physical, 90))
  let locked = {
    ..flch_state(200, 200, @model.None, @model.Sleep(2)),
    opp_two_turn: 0,
  }
  let s1 = tt_only(tt_turn(locked, my_team, opp_team))
  @debug.assert_eq(s1.my_hps[0], 200)
  @debug.assert_eq(s1.opp_hps[0], 200)
  @debug.assert_eq(s1.opp_two_turn, -1)
}

///|
test "a switch clears the charge lock" {
  let my_mv = tt_move("ソーラービーム", @model.Special, 120)
  let my_team = [
    flch_cmb(flch_pokemon("a", "ノーマル", 200, 120), [my_mv], ""),
    flch_cmb(flch_pokemon("b", "ノーマル", 200, 80), [flch_tackle()], ""),
  ]
  let opp_team = tt_slow(flch_tackle())
  let st = flch_state(200, 200, @model.None, @model.None)
  let st2 = {
    ..st,
    my_hps: [180, 180],
    my_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    my_megaed: [false, false],
    my_item_consumed: [false, false],
    my_disguise_busted: [false, false],
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
    my_two_turn: 0,
  }
  let outs = attempt_turn_with_cache(
    st2, Switch(1), UseMove(0), my_team, opp_team, new_damage_cache(),
  )
  let s1 = tt_only(outs)
  @debug.assert_eq(s1.my_active, 1)
  @debug.assert_eq(s1.my_two_turn, -1)
}

///|
test "tackle versus tackle does not set a two-turn lock" {
  let my_team = tt_fast(flch_tackle())
  let opp_team = tt_slow(flch_tackle())
  let s1 = tt_only(tt_turn(flch_state(200, 200, @model.None, @model.None), my_team, opp_team))
  assert_true(s1.opp_hps[0] < 200)
  assert_true(s1.my_hps[0] < 200)
  @debug.assert_eq(s1.my_two_turn, -1)
  @debug.assert_eq(s1.opp_two_turn, -1)
}

///|
test "state cache key: two_turn distinguishes the key" {
  let base = flch_state(200, 200, @model.None, @model.None)
  assert_distinct_state_keys(base, { ..base, my_two_turn: 0 })
  assert_distinct_state_keys(base, { ..base, opp_two_turn: 1 })
}

///|
test "mc charge does not deal damage and the release does" {
  let atk = flch_cmb(
    flch_pokemon("beam", "ノーマル", 200, 100),
    [tt_move("ソーラービーム", @model.Special, 120)],
    "",
  )
  let def = flch_cmb(flch_pokemon("wall", "ノーマル", 200, 50), [flch_tackle()], "")
  let rng = seeded_rng(1)
  let buf = [-1]
  let (hp1, _, _, _) = team_perform_attack(
    atk, def, 200, atk.moves[0], rng, [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
    track_two_turn=true, two_turn_lock=-1, move_index=0, lock_out=buf,
  )
  @debug.assert_eq(hp1, 200)
  @debug.assert_eq(buf[0], 0)
  let (hp2, _, _, _) = team_perform_attack(
    atk, def, 200, atk.moves[0], rng, [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
    track_two_turn=true, two_turn_lock=0, move_index=0, lock_out=buf,
  )
  assert_true(hp2 < 200)
  @debug.assert_eq(buf[0], -1)
}
