///|
/// バインド。本文は 4–5 ターン、ターン終了に最大 HP の 1/8、交代不可。
/// バインド技でない入力は fanout が 1 本のまま。EOT はカウンタ 0 で HP を書かない。

///|
fn bnd_close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-12
}

///|
fn bnd_move(name : String) -> @model.Move {
  flch_move(name, "ノーマル", @model.Physical, 15, 100, 0)
}

///|
fn bnd_pair() -> (Array[Combatant], Array[Combatant]) {
  let mv = flch_tackle()
  let me = [flch_cmb(flch_pokemon("a", "ノーマル", 160, 100), [mv], "")]
  let opp = [flch_cmb(flch_pokemon("b", "みず", 160, 80), [mv], "")]
  (me, opp)
}

///|
test "bind move list matches wazainfo and skips moves without that text" {
  let names = [
    "しめつける", "まきつく", "ほのおのうず", "うずしお", "すなじごく", "まとわりつく",
    "トラバサミ",
  ]
  for name in names {
    assert_true(move_binds(name))
  }
  assert_true(!move_binds("たいあたり"))
  assert_true(!move_binds("からではさむ"))
  assert_true(!move_binds("マグマストーム"))
  assert_true(!move_binds("サンダープリズン"))
  assert_true(!move_binds("こうそくスピン"))
}

///|
test "bind fanout: a non-bind move is one unchanged leaf" {
  let mv = flch_tackle()
  let st = flch_state(160, 160, @model.None, @model.None)
  let outs = maybe_apply_bind_fanout(st, false, 0, mv)
  assert_true(outs.length() == 1)
  assert_true(bnd_close(outs[0].0, 1.0))
  assert_true(outs[0].1 == st)
  assert_true(outs[0].1.opp_bind == 0)
}

///|
test "bind fanout: a landed bind splits 4 then 5 at one half each" {
  let mv = bnd_move("ほのおのうず")
  let st = flch_state(160, 160, @model.None, @model.None)
  let outs = maybe_apply_bind_fanout(st, false, 0, mv)
  assert_true(outs.length() == 2)
  assert_true(bnd_close(outs[0].0, 0.5))
  assert_true(bnd_close(outs[1].0, 0.5))
  assert_true(outs[0].1.opp_bind == 4)
  assert_true(outs[1].1.opp_bind == 5)
  assert_true(outs[0].1.my_bind == 0)
  assert_true(outs[0].1.opp_hps[0] == 160)
}

///|
test "bind fanout: already bound or fainted does not refresh or roll" {
  let mv = bnd_move("しめつける")
  let bound = { ..flch_state(160, 160, @model.None, @model.None), opp_bind: 2 }
  let again = maybe_apply_bind_fanout(bound, false, 0, mv)
  assert_true(again.length() == 1)
  assert_true(again[0].1 == bound)
  let faint = flch_state(160, 0, @model.None, @model.None)
  let dead = maybe_apply_bind_fanout(faint, false, 0, mv)
  assert_true(dead.length() == 1)
  assert_true(dead[0].1.opp_bind == 0)
  assert_true(dead[0].1 == faint)
}

///|
test "apply_eot: bind 0 does not write HP" {
  let (me, opp) = bnd_pair()
  let st = flch_state(160, 160, @model.None, @model.None)
  let next = apply_eot(st, me, opp)
  assert_true(next.my_hps[0] == 160)
  assert_true(next.opp_hps[0] == 160)
  assert_true(next.my_bind == 0 && next.opp_bind == 0)
  assert_true(next.my_status[0] == @model.None)
}

///|
test "apply_eot: bind chip is max/8 and the counter ticks" {
  let (me, opp) = bnd_pair()
  let st = { ..flch_state(160, 160, @model.None, @model.None), opp_bind: 4 }
  let next = apply_eot(st, me, opp)
  assert_true(next.opp_hps[0] == 140)
  assert_true(next.opp_bind == 3)
  assert_true(next.my_hps[0] == 160)
  assert_true(next.my_bind == 0)
}

///|
test "apply_eot: Binding Band on the source uses max/6" {
  let mv = flch_tackle()
  let me = [
    {
      ..flch_cmb(flch_pokemon("a", "ノーマル", 160, 100), [mv], ""),
      item: "しめつけバンド",
    },
  ]
  let opp = [flch_cmb(flch_pokemon("b", "みず", 160, 80), [mv], "")]
  let st = { ..flch_state(160, 160, @model.None, @model.None), opp_bind: 5 }
  let next = apply_eot(st, me, opp)
  // 160 / 6 = 26。相手がバインドされているので付与元は自分の持ち物。
  assert_true(next.opp_hps[0] == 134)
  assert_true(next.opp_bind == 4)
  assert_true(next.my_hps[0] == 160)
}

///|
test "apply_eot: Magic Guard takes no bind chip and still ticks" {
  let mv = flch_tackle()
  let me = [flch_cmb(flch_pokemon("a", "ノーマル", 160, 100), [mv], "")]
  let opp = [flch_cmb(flch_pokemon("b", "みず", 160, 80), [mv], "マジックガード")]
  let st = { ..flch_state(160, 160, @model.None, @model.None), opp_bind: 4 }
  let next = apply_eot(st, me, opp)
  assert_true(next.opp_hps[0] == 160)
  assert_true(next.opp_bind == 3)
}

///|
test "apply_eot: a fainted source clears bind without damage" {
  let (me, opp) = bnd_pair()
  let st = {
    ..flch_state(0, 160, @model.None, @model.None),
    opp_bind: 4,
  }
  let next = apply_eot(st, me, opp)
  assert_true(next.opp_hps[0] == 160)
  assert_true(next.opp_bind == 0)
}

///|
test "apply_eot: poison that KOs runs before bind and clears the counter" {
  let (me, opp) = bnd_pair()
  let st = {
    ..flch_state(20, 160, @model.Poison, @model.None),
    my_bind: 4,
  }
  let next = apply_eot(st, me, opp)
  assert_true(next.my_hps[0] == 0)
  assert_true(next.my_bind == 0)
  assert_true(next.my_status[0] == @model.Poison)
}

///|
test "apply_eot: my bind KO removes the source before opp bind deals damage" {
  let (me, opp) = bnd_pair()
  let st = {
    ..flch_state(20, 160, @model.None, @model.None),
    my_bind: 1,
    opp_bind: 1,
  }
  let next = apply_eot(st, me, opp)
  assert_true(next.my_hps[0] == 0)
  assert_true(next.my_bind == 0)
  assert_true(next.opp_hps[0] == 160)
  assert_true(next.opp_bind == 0)
}

///|
test "bind switch freedom: ghost, shed shell, and runaway; turns 0 is always free" {
  let mv = flch_tackle()
  let normal = flch_cmb(flch_pokemon("n", "ノーマル", 100, 100), [mv], "")
  let ghost = flch_cmb(flch_pokemon("g", "ゴースト", 100, 100), [mv], "")
  let shell = { ..normal, item: "きれいなぬけがら" }
  let run = flch_cmb(flch_pokemon("r", "ノーマル", 100, 100), [mv], "にげあし")
  assert_true(!bind_switch_free(4, normal, false, ""))
  assert_true(bind_switch_free(4, ghost, false, ""))
  assert_true(bind_switch_free(4, shell, false, ""))
  assert_true(bind_switch_free(4, run, false, ""))
  assert_true(bind_switch_free(0, normal, false, ""))
  assert_true(bind_switch_free(4, normal, false, "ゴースト"))
}

///|
test "alive_actions: bind blocks a living switch and still allows a fainted one" {
  let mv = flch_tackle()
  let a = flch_cmb(flch_pokemon("a", "ノーマル", 100, 100), [mv], "")
  let b = flch_cmb(flch_pokemon("b", "ノーマル", 100, 50), [mv], "")
  let team = [a, b]
  let open = alive_actions(0, [100, 100], team, false)
  let mut switches = 0
  for act in open {
    match act {
      Switch(_) => switches = switches + 1
      _ => ()
    }
  }
  assert_true(switches == 1)
  let trapped = alive_actions(0, [100, 100], team, false, can_switch=false)
  let mut trapped_switches = 0
  for act in trapped {
    match act {
      Switch(_) => trapped_switches = trapped_switches + 1
      _ => ()
    }
  }
  assert_true(trapped_switches == 0)
  assert_true(trapped.length() == open.length() - 1)
  let fainted = alive_actions(0, [0, 100], team, false, can_switch=false)
  let mut faint_switches = 0
  for act in fainted {
    match act {
      Switch(_) => faint_switches = faint_switches + 1
      _ => ()
    }
  }
  assert_true(faint_switches == 1)
}

///|
test "bind turn: a switch clears both counters before end of turn chip" {
  let mv = flch_tackle()
  let lead = flch_cmb(flch_pokemon("lead", "ノーマル", 200, 120), [mv], "")
  let bench = flch_cmb(flch_pokemon("bench", "ノーマル", 200, 50), [mv], "")
  let opp = flch_opp_team(mv, "")
  let st = {
    ..flch_state(200, 200, @model.None, @model.None),
    my_bind: 4,
    opp_bind: 3,
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
  let clear = {
    ..st,
    my_bind: 0,
    opp_bind: 0,
  }
  let base = attempt_turn_with_cache(
    clear, Switch(1), UseMove(0), [lead, bench], opp, new_damage_cache(),
  )
  assert_true(outs.length() == base.length())
  for i = 0; i < outs.length(); i = i + 1 {
    let (p, s) = outs[i]
    let (bp, b) = base[i]
    assert_true(bnd_close(p, bp))
    assert_true(s.my_bind == 0 && s.opp_bind == 0)
    assert_true(s.my_hps[0] == b.my_hps[0] && s.my_hps[1] == b.my_hps[1])
    assert_true(s.opp_hps[0] == b.opp_hps[0])
  }
}

///|
test "bind turn: an existing counter chips max/8 at end of turn" {
  let mv = flch_move("てだすけ", "ノーマル", @model.Status, 0, 100, 0)
  let me = flch_my_first_team(mv, "")
  let opp = flch_opp_team(mv, "")
  let st = { ..flch_state(200, 200, @model.None, @model.None), opp_bind: 4 }
  let outs = attempt_turn_with_cache(
    st, UseMove(0), UseMove(0), me, opp, new_damage_cache(),
  )
  let mut mass = 0.0
  for item in outs {
    let (p, s) = item
    if s.opp_bind == 3 && s.opp_hps[0] == 175 && s.my_hps[0] == 200 {
      mass = mass + p
    }
  }
  assert_true(bnd_close(mass, 1.0))
}

///|
test "mc bind roll: non-bind and blocked cases do not draw, a hit is 4 or 5" {
  let plain = flch_tackle()
  let wrap = bnd_move("まきつく")
  let rng_a = seeded_rng(11UL)
  let rng_b = seeded_rng(11UL)
  assert_true(mc_apply_bind(rng_a, plain, 100, 0, false) == 0)
  assert_true(mc_apply_bind(rng_a, wrap, 0, 0, false) == 0)
  assert_true(mc_apply_bind(rng_a, wrap, 100, 2, false) == 2)
  assert_true(mc_apply_bind(rng_a, wrap, 100, 0, true) == 0)
  assert_true(rng_a.int(limit=1000000) == rng_b.int(limit=1000000))
  let mut fours = 0
  let trials = 400
  let rng = seeded_rng(23UL)
  for _i = 0; _i < trials; _i = _i + 1 {
    let got = mc_apply_bind(rng, wrap, 100, 0, false)
    assert_true(got == 4 || got == 5)
    if got == 4 {
      fours = fours + 1
    }
  }
  let rate = fours.to_double() / trials.to_double()
  assert_true((rate - 0.5).abs() < 0.08)
}

///|
test "mc greedy: epsilon 1 while bound never switches" {
  let weak = flch_move("ひっかく", "ノーマル", @model.Physical, 40, 100, 0)
  let strong = flch_move("はかいこうせん", "ノーマル", @model.Physical, 150, 100, 0)
  let active = flch_cmb(flch_pokemon("a", "ノーマル", 200, 100), [weak], "")
  let bench = flch_cmb(flch_pokemon("b", "ノーマル", 200, 80), [strong], "")
  let foe = flch_cmb(flch_pokemon("c", "ノーマル", 200, 50), [weak], "")
  let rng = seeded_rng(5UL)
  for _i = 0; _i < 30; _i = _i + 1 {
    match
      greedy_team_action(
        0,
        [active, bench],
        [200, 200],
        [0, 0, 0, 0, 0],
        0,
        [foe],
        [0, 0, 0, 0, 0],
        rng,
        1.0,
        can_switch=false,
      ) {
      Some(TmUseMove(_)) => ()
      _ => abort("bound side switched")
    }
  }
}
