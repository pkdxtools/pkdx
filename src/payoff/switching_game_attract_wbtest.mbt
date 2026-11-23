///|
/// メロメロ。本文は WAZAINFO_SYN_213 / BTR_STATE_SYN_13_02 / TOKUSEIINFO_SYN_056。
/// 付与できない相手は fanout が 1 本のまま。行動不能は 1/2。メロメロボディは 30%。

///|
fn atr_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
fn atr_move() -> @model.Move {
  flch_move("メロメロ", "ノーマル", @model.Status, 0, 100, 0)
}

///|
fn atr_mass(
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
fn atr_pair(
  atk_name : String,
  def_name : String,
  atk_ability : String,
  def_ability : String,
  mv : @model.Move,
) -> (Array[Combatant], Array[Combatant], SwitchingGameState) {
  let atk = [flch_cmb(flch_pokemon(atk_name, "ノーマル", 200, 100), [mv], atk_ability)]
  let def = [flch_cmb(flch_pokemon(def_name, "ノーマル", 200, 100), [mv], def_ability)]
  (atk, def, flch_state(200, 200, @model.None, @model.None))
}

///|
test "attract fanout: a non-attract move is one unchanged leaf" {
  let mv = flch_tackle()
  let (atk, def, st) = atr_pair("ケンタロス", "ガルーラ", "", "", mv)
  let outs = maybe_apply_attract_fanout(st, false, 0, 0, atk, def, mv)
  assert_true(outs.length() == 1)
  assert_true(atr_close(outs[0].0, 1.0))
  assert_true(outs[0].1 == st)
}

///|
test "attract fanout: opposite fixed genders set the flag in one leaf" {
  let mv = atr_move()
  let (atk, def, st) = atr_pair("ケンタロス", "ガルーラ", "", "", mv)
  let outs = maybe_apply_attract_fanout(st, false, 0, 0, atk, def, mv)
  assert_true(outs.length() == 1)
  assert_true(atr_close(outs[0].0, 1.0))
  assert_true(outs[0].1.opp_attract == 1)
  assert_true(outs[0].1.my_attract == 0)
}

///|
test "attract fanout: same gender, unknown, and genderless do not branch" {
  let mv = atr_move()
  let (atk, def, st) = atr_pair("ガルーラ", "ユキメノコ", "", "", mv)
  let same = maybe_apply_attract_fanout(st, false, 0, 0, atk, def, mv)
  assert_true(same.length() == 1 && same[0].1 == st)
  let (uatk, udef, _) = atr_pair("fast", "slow", "", "", mv)
  let unknown = maybe_apply_attract_fanout(st, false, 0, 0, uatk, udef, mv)
  assert_true(unknown.length() == 1 && unknown[0].1 == st)
  let (gatk, gdef, _) = atr_pair("ケンタロス", "メタモン", "", "", mv)
  let none = maybe_apply_attract_fanout(st, false, 0, 0, gatk, gdef, mv)
  assert_true(none.length() == 1 && none[0].1 == st)
}

///|
test "attract gender: suffix beats the male base, and explicit gender loses to genderless" {
  let male = flch_cmb(flch_pokemon("イダイトウ", "みず", 200, 100), [flch_tackle()], "")
  let female = flch_cmb(
    flch_pokemon("イダイトウ（メス）", "みず", 200, 100),
    [flch_tackle()],
    "",
  )
  assert_true(resolve_gender(male) == Gender::Male)
  assert_true(resolve_gender(female) == Gender::Female)
  let ditto = {
    ..flch_cmb(flch_pokemon("メタモン", "ノーマル", 200, 100), [flch_tackle()], ""),
    gender: Gender::Male,
  }
  assert_true(resolve_gender(ditto) == Gender::Unknown)
  let named = {
    ..flch_cmb(flch_pokemon("fast", "ノーマル", 200, 100), [flch_tackle()], ""),
    gender: Gender::Female,
  }
  assert_true(resolve_gender(named) == Gender::Female)
}

///|
test "attract fanout: already infatuated is not refreshed" {
  let mv = atr_move()
  let (atk, def, base) = atr_pair("ケンタロス", "ガルーラ", "", "", mv)
  let st = { ..base, opp_attract: 1 }
  let outs = maybe_apply_attract_fanout(st, false, 0, 0, atk, def, mv)
  assert_true(outs.length() == 1)
  assert_true(outs[0].1.opp_attract == 1)
  assert_true(outs[0].1 == st)
}

///|
test "attract fanout: Oblivious and Aroma Veil block; Mold Breaker does not" {
  let mv = atr_move()
  let st = flch_state(200, 200, @model.None, @model.None)
  let (atk, oblivious, _) = atr_pair("ケンタロス", "ガルーラ", "", "どんかん", mv)
  let blocked = maybe_apply_attract_fanout(st, false, 0, 0, atk, oblivious, mv)
  assert_true(blocked.length() == 1 && blocked[0].1 == st)
  let (_, veil, _) = atr_pair("ケンタロス", "ガルーラ", "", "アロマベール", mv)
  let veiled = maybe_apply_attract_fanout(st, false, 0, 0, atk, veil, mv)
  assert_true(veiled.length() == 1 && veiled[0].1 == st)
  let (broken_atk, _, _) = atr_pair("ケンタロス", "ガルーラ", "かたやぶり", "どんかん", mv)
  let broken = maybe_apply_attract_fanout(
    st, false, 0, 0, broken_atk, oblivious, mv, attacker_ability="かたやぶり",
  )
  assert_true(broken.length() == 1 && broken[0].1.opp_attract == 1)
  let broken_veil = maybe_apply_attract_fanout(
    st, false, 0, 0, broken_atk, veil, mv, attacker_ability="かたやぶり",
  )
  assert_true(broken_veil.length() == 1 && broken_veil[0].1.opp_attract == 1)
}

///|
test "attract fanout: Mental Herb is consumed and the flag stays down" {
  let mv = atr_move()
  let atk = [flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 100), [mv], "")]
  let herb = {
    ..flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 100), [mv], ""),
    item: "メンタルハーブ",
  }
  let st = flch_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_attract_fanout(st, false, 0, 0, atk, [herb], mv)
  assert_true(outs.length() == 1)
  assert_true(outs[0].1.opp_attract == 0)
  assert_true(outs[0].1.opp_item_consumed[0])
  let used = { ..st, opp_item_consumed: [true] }
  let again = maybe_apply_attract_fanout(used, false, 0, 0, atk, [herb], mv)
  assert_true(again.length() == 1 && again[0].1.opp_attract == 1)
}

///|
test "cute charm: 30% contact, failure leaf first; non-contact is unchanged" {
  let tackle = flch_tackle()
  let atk = [flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 100), [tackle], "")]
  let charm = [flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 100), [tackle], "メロメロボディ")]
  let st = flch_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_cute_charm_fanout(st, true, 0, 0, atk, charm, tackle, hits_count=1)
  assert_true(outs.length() == 2)
  assert_true(atr_close(outs[0].0, 0.7))
  assert_true(outs[0].1 == st)
  assert_true(atr_close(outs[1].0, 0.3))
  assert_true(outs[1].1.my_attract == 1)
  let surf = flch_move("なみのり", "みず", @model.Special, 90, 100, 0)
  let wave = maybe_apply_cute_charm_fanout(st, true, 0, 0, atk, charm, surf, hits_count=1)
  assert_true(wave.length() == 1 && wave[0].1 == st)
}

///|
test "cute charm: same gender, Mold Breaker, Oblivious, zero hits, and a faint are unchanged" {
  let tackle = flch_tackle()
  let st = flch_state(200, 200, @model.None, @model.None)
  let charm = [flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 100), [tackle], "メロメロボディ")]
  let female = [flch_cmb(flch_pokemon("ユキメノコ", "こおり", 200, 100), [tackle], "")]
  let same = maybe_apply_cute_charm_fanout(st, true, 0, 0, female, charm, tackle)
  assert_true(same.length() == 1 && same[0].1 == st)
  let breaker = [flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 100), [tackle], "かたやぶり")]
  let broken = maybe_apply_cute_charm_fanout(st, true, 0, 0, breaker, charm, tackle)
  assert_true(broken.length() == 1 && broken[0].1 == st)
  let oblivious = [flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 100), [tackle], "どんかん")]
  let dull = maybe_apply_cute_charm_fanout(st, true, 0, 0, oblivious, charm, tackle)
  assert_true(dull.length() == 1 && dull[0].1 == st)
  let male = [flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 100), [tackle], "")]
  let no_hit = maybe_apply_cute_charm_fanout(st, true, 0, 0, male, charm, tackle, hits_count=0)
  assert_true(no_hit.length() == 1 && no_hit[0].1 == st)
  let faint = { ..st, opp_hps: [0] }
  let dead = maybe_apply_cute_charm_fanout(faint, true, 0, 0, male, charm, tackle)
  assert_true(dead.length() == 1 && dead[0].1 == faint)
}

///|
test "cute charm: two hits use 1 - 0.7^2 and keep the failure leaf first" {
  let tackle = flch_tackle()
  let atk = [flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 100), [tackle], "")]
  let charm = [flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 100), [tackle], "メロメロボディ")]
  let st = flch_state(200, 200, @model.None, @model.None)
  let outs = maybe_apply_cute_charm_fanout(st, true, 0, 0, atk, charm, tackle, hits_count=2)
  let miss = 0.7 * 0.7
  assert_true(outs.length() == 2)
  assert_true(atr_close(outs[0].0, miss))
  assert_true(outs[0].1.my_attract == 0)
  assert_true(atr_close(outs[1].0, 1.0 - miss))
  assert_true(outs[1].1.my_attract == 1)
}

///|
test "attract deferral: only a live flag or a move that can land" {
  let tackle = flch_tackle()
  let me = flch_my_first_team(tackle, "")
  let opp = flch_opp_team(tackle, "")
  let plain = flch_state(200, 200, @model.None, @model.None)
  assert_true(!attract_roll_deferred(plain, true, UseMove(0), me, UseMove(0), opp))
  let live = { ..plain, my_attract: 1 }
  assert_true(attract_roll_deferred(live, true, UseMove(0), me, UseMove(0), opp))
  let faint_src = { ..plain, my_attract: 1, opp_hps: [0] }
  assert_true(!attract_roll_deferred(faint_src, true, UseMove(0), me, UseMove(0), opp))
  let mv = atr_move()
  let girl = [flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 50), [tackle], "")]
  let boy = [flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 120), [mv], "")]
  assert_true(attract_roll_deferred(plain, true, UseMove(0), girl, UseMove(0), boy))
  let both_girls = [flch_cmb(flch_pokemon("ユキメノコ", "こおり", 200, 120), [mv], "")]
  assert_true(!attract_roll_deferred(plain, true, UseMove(0), girl, UseMove(0), both_girls))
  let dull = [flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 50), [tackle], "どんかん")]
  assert_true(!attract_roll_deferred(plain, true, UseMove(0), dull, UseMove(0), boy))
  let mold = [flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 120), [mv], "かたやぶり")]
  assert_true(attract_roll_deferred(plain, true, UseMove(0), dull, UseMove(0), mold))
  assert_true(!attract_roll_deferred(live, true, UseMove(0), me, Switch(0), opp))
}

///|
test "attract turn: a live flag immobilizes half the time and is not cleared by attacking" {
  let me = flch_my_first_team(flch_tackle(), "")
  let opp = flch_opp_team(flch_tackle(), "")
  let st = { ..flch_state(200, 200, @model.None, @model.None), my_attract: 1 }
  let outs = flch_turn(st, me, opp)
  assert_true(atr_close(atr_mass(outs, fn(s) { s.opp_hps[0] == 200 && s.my_attract == 1 }), 0.5))
  assert_true(atr_close(atr_mass(outs, fn(s) { s.opp_hps[0] < 200 && s.my_attract == 1 }), 0.5))
}

///|
test "attract turn: full sleep does not roll the 50 percent" {
  let me = flch_my_first_team(flch_tackle(), "")
  let opp = flch_opp_team(flch_tackle(), "")
  let st = {
    ..flch_state(200, 200, @model.Sleep(2), @model.None),
    my_attract: 1,
  }
  let outs = flch_turn(st, me, opp)
  assert_true(outs.length() == 1)
  assert_true(outs[0].1.my_attract == 1)
  assert_true(outs[0].1.opp_hps[0] == 200)
  assert_true(outs[0].1.my_status[0] == @model.Sleep(1))
}

///|
test "attract turn: paralysis is rolled only on the half that can move" {
  let me = flch_my_first_team(flch_tackle(), "")
  let opp = flch_opp_team(flch_tackle(), "")
  let st = {
    ..flch_state(200, 200, @model.Paralyze, @model.None),
    my_attract: 1,
  }
  let outs = flch_turn(st, me, opp)
  let skip = 0.5 + 0.5 * 0.125
  let act = 0.5 * 0.875
  assert_true(atr_close(atr_mass(outs, fn(s) { s.opp_hps[0] == 200 }), skip))
  assert_true(atr_close(atr_mass(outs, fn(s) { s.opp_hps[0] < 200 }), act))
  assert_true(atr_close(atr_mass(outs, fn(s) { s.my_attract == 1 }), 1.0))
}

///|
test "attract turn: either switch clears both flags before the remaining attack" {
  let tackle = flch_tackle()
  let lead = flch_cmb(flch_pokemon("lead", "ノーマル", 200, 120), [tackle], "")
  let bench = flch_cmb(flch_pokemon("bench", "ノーマル", 200, 50), [tackle], "")
  let opp = flch_opp_team(tackle, "")
  let st = {
    ..flch_state(200, 200, @model.None, @model.None),
    my_attract: 1,
    opp_attract: 1,
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
  assert_true(atr_close(atr_mass(outs, fn(s) { s.my_attract == 0 && s.opp_attract == 0 }), 1.0))
  assert_true(atr_close(atr_mass(outs, fn(s) { s.my_hps[1] < 200 }), 1.0))
  let foe_lead = flch_cmb(flch_pokemon("foe", "ノーマル", 200, 40), [tackle], "")
  let foe_bench = flch_cmb(flch_pokemon("foe2", "ノーマル", 200, 30), [tackle], "")
  let mine = flch_my_first_team(tackle, "")
  let src = {
    ..flch_state(200, 200, @model.None, @model.None),
    my_attract: 1,
    opp_hps: [200, 200],
    opp_megaed: [false, false],
    opp_status: [@model.None, @model.None],
    opp_must_recharge: [false, false],
    opp_item_consumed: [false, false],
    opp_disguise_busted: [false, false],
    opp_leech_seeded: [false, false],
    opp_protean_locked: ["", ""],
  }
  let left = attempt_turn_with_cache(
    src, UseMove(0), Switch(1), mine, [foe_lead, foe_bench], new_damage_cache(),
  )
  assert_true(atr_close(atr_mass(left, fn(s) { s.my_attract == 0 }), 1.0))
  assert_true(atr_close(atr_mass(left, fn(s) { s.opp_hps[1] < 200 }), 1.0))
}

///|
test "attract turn: a faster Attract infatuates before the slower move" {
  let mv = atr_move()
  let me = [flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 120), [mv], "")]
  let opp = [flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 60), [flch_tackle()], "")]
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), me, opp)
  assert_true(atr_close(atr_mass(outs, fn(s) { s.opp_attract == 1 }), 1.0))
  assert_true(atr_close(atr_mass(outs, fn(s) { s.my_hps[0] == 200 }), 0.5))
  assert_true(atr_close(atr_mass(outs, fn(s) { s.my_hps[0] < 200 }), 0.5))
}

///|
test "attract turn: same gender Attract does not immobilize" {
  let mv = atr_move()
  let me = [flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 120), [mv], "")]
  let opp = [flch_cmb(flch_pokemon("ユキメノコ", "こおり", 200, 60), [flch_tackle()], "")]
  let outs = flch_turn(flch_state(200, 200, @model.None, @model.None), me, opp)
  assert_true(atr_close(atr_mass(outs, fn(s) { s.opp_attract == 0 }), 1.0))
  assert_true(atr_close(atr_mass(outs, fn(s) { s.my_hps[0] < 200 }), 1.0))
}

///|
test "attract state: the flag is part of the cache key" {
  let base = flch_state(200, 200, @model.None, @model.None)
  let marked = { ..base, my_attract: 1 }
  assert_true(base != marked)
}

///|
test "attract MC: a live flag stops about half, and a plain move draws no extra rng" {
  let rng = seeded_rng(11)
  let mut stopped = 0
  let n = 3000
  for i = 0; i < n; i = i + 1 {
    let (_, acts, _, t, self_hit) = mc_resolve_attracted(rng, @model.None, 100, false, 0)
    if !acts {
      stopped = stopped + 1
    }
    assert_true(!self_hit && t == 0)
  }
  let rate = stopped.to_double() / n.to_double()
  assert_true((rate - 0.5).abs() < 0.03)
  let tackle = flch_tackle()
  let atk = flch_cmb(flch_pokemon("ケンタロス", "ノーマル", 200, 100), [tackle], "")
  let def = flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 100), [tackle], "")
  let consumed : Array[Bool] = [false]
  let rng_a = seeded_rng(3)
  let rng_b = seeded_rng(3)
  let flag = mc_apply_attract_move(def, 200, atk, 200, "", tackle, 0, consumed, 0)
  assert_true(flag == 0)
  assert_true(rng_a.int(limit=1000000) == rng_b.int(limit=1000000))
  let charm = flch_cmb(flch_pokemon("ガルーラ", "ノーマル", 200, 100), [tackle], "メロメロボディ")
  let rng_c = seeded_rng(5)
  let rng_d = seeded_rng(5)
  let kept = mc_apply_cute_charm(
    rng_c, tackle, atk, 200, 0, consumed, 0, charm, 200, true, 0,
  )
  assert_true(kept == 0)
  assert_true(rng_c.int(limit=1000000) == rng_d.int(limit=1000000))
}

///|
test "attract MC: full sleep does not draw the immobilize roll" {
  let rng = seeded_rng(1)
  let plain = seeded_rng(1)
  let (st, acts, _, t, _) = mc_resolve_attracted(rng, @model.Sleep(2), 100, false, 4)
  assert_true(st == @model.Sleep(1) && !acts && t == 4)
  // 眠り継続は乱数を使わない。次の乱数はシードだけ進めた列と一致する。
  assert_true(rng.int(limit=1000000) == plain.int(limit=1000000))
}
