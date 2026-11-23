///|
/// こんらん。本文は 1–4 ターン・自傷 1/3。カウンタは Showdown の 2..5。
/// 付与されない技 (confusion_chance = 0) は fanout が 1 本のまま。

///|
fn cnf_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
fn cnf_ray() -> @model.Move {
  {
    ..flch_move("あやしいひかり", "ゴースト", @model.Status, 0, 100, 0),
    confusion_chance: 100,
  }
}

///|
fn cnf_mass(
  outs : Array[(Double, SwitchingGameState)],
  pred : (SwitchingGameState) -> Bool,
) -> Double {
  let mut total = 0.0
  for item in outs {
    let (p, s) = item
    if pred(s) {
      total = total + p
    }
  }
  total
}

///|
test "confusion fanout: chance 0 is a single unchanged leaf" {
  let mv = flch_tackle()
  let team = [flch_cmb(flch_pokemon("t", "ノーマル", 200, 100), [mv], "")]
  let st = flch_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_confusion_fanout(st, false, 0, team, mv)
  assert_true(outs.length() == 1)
  assert_true(cnf_close(outs[0].0, 1.0))
  assert_true(outs[0].1.opp_confusion == 0)
  assert_true(outs[0].1.my_confusion == 0)
}

///|
test "confusion fanout: 100% is uniform over counters 2, 3, 4, 5" {
  let mv = cnf_ray()
  let team = [flch_cmb(flch_pokemon("t", "ノーマル", 200, 100), [mv], "")]
  let st = flch_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_confusion_fanout(st, false, 0, team, mv)
  assert_true(outs.length() == 4)
  let starts = [2, 3, 4, 5]
  for i = 0; i < starts.length(); i = i + 1 {
    let want = starts[i]
    assert_true(
      cnf_close(cnf_mass(outs, fn(s) { s.opp_confusion == want }), 0.25),
    )
  }
}

///|
test "confusion fanout: 20% keeps an unchanged branch then four equal shares" {
  let mv = {
    ..flch_move("みずのはどう", "みず", @model.Special, 60, 100, 0),
    confusion_chance: 20,
  }
  let team = [flch_cmb(flch_pokemon("t", "みず", 200, 100), [mv], "")]
  let st = flch_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_confusion_fanout(st, false, 0, team, mv)
  assert_true(cnf_close(cnf_mass(outs, fn(s) { s.opp_confusion == 0 }), 0.8))
  assert_true(cnf_close(cnf_mass(outs, fn(s) { s.opp_confusion == 2 }), 0.05))
  assert_true(cnf_close(cnf_mass(outs, fn(s) { s.opp_confusion == 5 }), 0.05))
}

///|
test "confusion fanout: already confused is not refreshed" {
  let mv = cnf_ray()
  let team = [flch_cmb(flch_pokemon("t", "ノーマル", 200, 100), [mv], "")]
  let st = { ..flch_state(200, 200, @model.None, @model.None), opp_confusion: 4 }
  let outs = maybe_apply_confusion_fanout(st, false, 0, team, mv)
  assert_true(outs.length() == 1)
  assert_true(outs[0].1.opp_confusion == 4)
}

///|
test "confusion fanout: Own Tempo blocks, Mold Breaker does not" {
  let mv = cnf_ray()
  let plain = [flch_cmb(flch_pokemon("t", "ノーマル", 200, 100), [mv], "マイペース")]
  let st = flch_state(200, 200, @model.None, @model.None)
  let blocked = maybe_apply_confusion_fanout(st, false, 0, plain, mv, attacker_ability="")
  assert_true(blocked.length() == 1 && blocked[0].1.opp_confusion == 0)
  let broken = maybe_apply_confusion_fanout(
    st, false, 0, plain, mv, attacker_ability="かたやぶり",
  )
  assert_true(broken.length() == 4)
}

///|
test "confusion fanout: Misty blocks a grounded target and not a Flying one" {
  let mv = cnf_ray()
  let ground = [flch_cmb(flch_pokemon("t", "ノーマル", 200, 100), [mv], "")]
  let flying = [flch_cmb(flch_pokemon("f", "ひこう", 200, 100), [mv], "")]
  let st = {
    ..flch_state(200, 200, @model.None, @model.None),
    field: @model.Field::Misty,
  }
  let blocked = maybe_apply_confusion_fanout(st, false, 0, ground, mv)
  assert_true(blocked.length() == 1 && blocked[0].1.opp_confusion == 0)
  let hit = maybe_apply_confusion_fanout(st, false, 0, flying, mv)
  assert_true(hit.length() == 4)
}

///|
test "confusion fanout: Sheer Force strips a damaging confusion secondary" {
  let punch = {
    ..flch_move("ばくれつパンチ", "かくとう", @model.Physical, 100, 50, 0),
    confusion_chance: 100,
  }
  assert_true(@damage.move_has_sheer_force_effect(punch))
  let cleared = @damage.clear_damaging_secondaries(punch)
  assert_true(cleared.confusion_chance == 0)
  assert_true(!@damage.move_has_sheer_force_effect(cleared))
  let me = flch_my_first_team(punch, "ちからずく")
  let opp = flch_opp_team(flch_tackle(), "")
  let st = flch_state(200, 200, @model.None, @model.None)
  let outs = flch_turn(st, me, opp)
  assert_true(cnf_close(cnf_mass(outs, fn(s) { s.opp_confusion == 0 }), 1.0))
}

///|
test "confusion self-hit: counter 2 is 1/3 self-hit then 1; counter 1 snaps and acts" {
  let me = flch_my_first_team(flch_tackle(), "")
  let opp = flch_opp_team(flch_tackle(), "")
  let confused = {
    ..flch_state(200, 200, @model.None, @model.None),
    my_confusion: 2,
  }
  let outs = flch_turn(confused, me, opp)
  // 自傷した枝は相手の HP が減らない。技を出した枝は減る。
  assert_true(cnf_close(cnf_mass(outs, fn(s) { s.opp_hps[0] == 200 }), 1.0 / 3.0))
  assert_true(
    cnf_close(cnf_mass(outs, fn(s) { s.opp_hps[0] < 200 && s.my_confusion == 1 }), 2.0 / 3.0),
  )
  assert_true(cnf_close(cnf_mass(outs, fn(s) { s.my_confusion == 1 }), 1.0))
  let snap = { ..flch_state(200, 200, @model.None, @model.None), my_confusion: 1 }
  let woke = flch_turn(snap, me, opp)
  assert_true(cnf_close(cnf_mass(woke, fn(s) { s.my_confusion == 0 && s.opp_hps[0] < 200 }), 1.0))
}

///|
test "confusion: full sleep does not tick the counter" {
  let me = flch_my_first_team(flch_tackle(), "")
  let opp = flch_opp_team(flch_tackle(), "")
  let st = {
    ..flch_state(200, 200, @model.Sleep(2), @model.None),
    my_confusion: 3,
  }
  let outs = flch_turn(st, me, opp)
  assert_true(cnf_close(cnf_mass(outs, fn(s) { s.my_confusion == 3 }), 1.0))
}

///|
test "confusion: switching out clears it before the opponent's move" {
  let tackle = flch_tackle()
  let lead = flch_cmb(flch_pokemon("lead", "ノーマル", 200, 120), [tackle], "")
  let bench = flch_cmb(flch_pokemon("bench", "ノーマル", 200, 50), [tackle], "")
  let opp = flch_opp_team(tackle, "")
  let st = {
    ..flch_state(200, 200, @model.None, @model.None),
    my_confusion: 4,
    my_hps: [200, 200],
    my_megaed: [false, false],
    my_status: [@model.None, @model.None],
    my_must_recharge: [false, false],
    my_item_consumed: [false, false],
    my_disguise_busted: [false, false],
    my_leech_seeded: [false, false],
    my_protean_locked: ["", ""],
  }
  let outs = attempt_turn_with_cache(
    st, Switch(1), UseMove(0), [lead, bench], opp, new_damage_cache(),
  )
  assert_true(cnf_close(cnf_mass(outs, fn(s) { s.my_confusion == 0 }), 1.0))
}

///|
test "confusion berry: Persim and Lum cure at end of turn, and do nothing if not confused" {
  let berry = {
    ..flch_cmb(flch_pokemon("b", "ノーマル", 200, 100), [flch_tackle()], ""),
    item: "キーのみ",
  }
  let lum = { ..berry, item: "ラムのみ" }
  let plain = flch_cmb(flch_pokemon("p", "ノーマル", 200, 100), [flch_tackle()], "")
  let confused = { ..flch_state(200, 200, @model.None, @model.None), my_confusion: 3 }
  let cured = apply_eot(confused, [berry], [plain])
  assert_true(cured.my_confusion == 0)
  assert_true(cured.my_item_consumed[0])
  let cured_lum = apply_eot(confused, [lum], [plain])
  assert_true(cured_lum.my_confusion == 0)
  assert_true(cured_lum.my_item_consumed[0])
  // こんらんしていない所持者は消費しない (既存 EOT を変えない)。
  let idle = apply_eot(flch_state(200, 200, @model.None, @model.None), [berry], [plain])
  assert_true(idle.my_confusion == 0)
  assert_true(!idle.my_item_consumed[0])
  // ラムはこんらんだけ。やけどは残る。
  let burned = {
    ..flch_state(200, 200, @model.Burn, @model.None),
    my_confusion: 2,
  }
  let still_burned = apply_eot(burned, [lum], [plain])
  assert_true(still_burned.my_confusion == 0)
  assert_true(still_burned.my_status[0] == @model.Burn)
}

///|
test "confusion MC: counter 2 self-hits about 1/3; counter 1 never self-hits" {
  let rng = seeded_rng(7)
  let mut hits = 0
  let n = 3000
  for i = 0; i < n; i = i + 1 {
    let (_, _, _, t, self_hit) = mc_resolve_confused(
      rng, @model.None, 100, false, 2,
    )
    if self_hit {
      hits = hits + 1
    }
    assert_true(t == 1)
  }
  let rate = hits.to_double() / n.to_double()
  assert_true((rate - 1.0 / 3.0).abs() < 0.03)
  let rng2 = seeded_rng(9)
  for i = 0; i < 200; i = i + 1 {
    let (_, acts, _, t, self_hit) = mc_resolve_confused(
      rng2, @model.None, 100, false, 1,
    )
    assert_true(!self_hit && acts && t == 0)
  }
}
