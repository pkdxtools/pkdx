///|
/// 設置技。champout `50e7233` の本文と、層数の分数だけ Showdown。
/// 先発には掛からない。交代したときだけ。

///|
fn hz_mon(
  name : String,
  type1 : String,
  type2 : String,
  hp : Int,
  spe : Int,
  moves : Array[@model.Move],
  ability? : String = "",
  item? : String = "",
) -> Combatant {
  {
    ..rg_combatant(mk_pokemon(name, type1, type2, hp, 100, 100, 100, 100, spe)),
    moves,
    ability,
    item,
  }
}

///|
fn hz_set(name : String) -> @model.Move {
  mk_move(name, "いわ", @model.Status, 0, accuracy=101)
}

///|
test "entry hazards: stealth rock uses rock effectiveness, spikes use layers" {
  let normal = hz_mon("N", "ノーマル", "", 200, 100, [])
  let fire = hz_mon("F", "ほのお", "", 200, 100, [])
  let bug = hz_mon("B", "むし", "ひこう", 200, 100, [])
  let fight = hz_mon("K", "かくとう", "じめん", 200, 100, [])
  let tiny = hz_mon("T", "かくとう", "じめん", 1, 100, [])
  let hps = [200]
  let st = [@model.StatusCondition::None]
  let rk = [0, 0, 0, 0, 0]
  let weather = @model.Weather::None
  let _ = apply_entry_hazards(
    [normal], 0, [false], hps, st, rk, 1, 0, 0, 0, weather,
  )
  @debug.assert_eq(hps[0], 175)
  hps[0] = 200
  let _ = apply_entry_hazards(
    [fire], 0, [false], hps, st, rk, 1, 0, 0, 0, weather,
  )
  @debug.assert_eq(hps[0], 150)
  hps[0] = 200
  let _ = apply_entry_hazards(
    [bug], 0, [false], hps, st, rk, 1, 0, 0, 0, weather,
  )
  @debug.assert_eq(hps[0], 100)
  hps[0] = 200
  let _ = apply_entry_hazards(
    [fight], 0, [false], hps, st, rk, 1, 0, 0, 0, weather,
  )
  @debug.assert_eq(hps[0], 194)
  let tiny_hp = [1]
  let _ = apply_entry_hazards(
    [tiny], 0, [false], tiny_hp, st, rk, 1, 0, 0, 0, weather,
  )
  @debug.assert_eq(tiny_hp[0], 0)
  hps[0] = 200
  let _ = apply_entry_hazards(
    [normal], 0, [false], hps, st, rk, 0, 1, 0, 0, weather,
  )
  @debug.assert_eq(hps[0], 175)
  hps[0] = 200
  let _ = apply_entry_hazards(
    [normal], 0, [false], hps, st, rk, 0, 2, 0, 0, weather,
  )
  @debug.assert_eq(hps[0], 167)
  hps[0] = 200
  let _ = apply_entry_hazards(
    [normal], 0, [false], hps, st, rk, 0, 3, 0, 0, weather,
  )
  @debug.assert_eq(hps[0], 150)
  let untouched = [200]
  let tox = apply_entry_hazards(
    [normal], 0, [false], untouched, [@model.StatusCondition::None], [0, 0, 0, 0, 0], 0, 0, 0, 0,
    weather,
  )
  @debug.assert_eq(untouched[0], 200)
  @debug.assert_eq(tox, 0)
}

///|
test "toxic spikes poison or badly poison, poison absorbs, steel does not" {
  let normal = hz_mon("N", "ノーマル", "", 200, 100, [])
  let poison = hz_mon("P", "どく", "", 200, 100, [])
  let steel = hz_mon("S", "はがね", "", 200, 100, [])
  let weather = @model.Weather::None
  let hps = [200]
  let st = [@model.StatusCondition::None]
  let rk = [0, 0, 0, 0, 0]
  let left = apply_entry_hazards(
    [normal], 0, [false], hps, st, rk, 0, 0, 1, 0, weather,
  )
  @debug.assert_eq(left, 1)
  assert_true(st[0] is @model.Poison)
  st[0] = @model.StatusCondition::None
  let left2 = apply_entry_hazards(
    [normal], 0, [false], hps, st, rk, 0, 0, 2, 0, weather,
  )
  @debug.assert_eq(left2, 2)
  match st[0] {
    @model.BadPoison(0) => ()
    _ => fail("2 layers are bad poison")
  }
  st[0] = @model.StatusCondition::None
  let absorbed = apply_entry_hazards(
    [poison], 0, [false], hps, st, rk, 0, 0, 2, 0, weather,
  )
  @debug.assert_eq(absorbed, 0)
  assert_true(st[0] is @model.StatusCondition::None)
  let stayed = apply_entry_hazards(
    [steel], 0, [false], hps, st, rk, 0, 0, 1, 0, weather,
  )
  @debug.assert_eq(stayed, 1)
  assert_true(st[0] is @model.StatusCondition::None)
}

///|
test "flying, levitate and balloon skip grounded hazards; iron ball does not" {
  let flying = hz_mon("F", "ひこう", "", 200, 100, [])
  let lev = hz_mon("L", "ノーマル", "", 200, 100, [], ability="ふゆう")
  let balloon = hz_mon("A", "ノーマル", "", 200, 100, [], item="ふうせん")
  let ball = hz_mon("I", "ひこう", "", 200, 100, [], item="くろいてっきゅう")
  let weather = @model.Weather::None
  let hps = [200]
  let st = [@model.StatusCondition::None]
  let rk = [0, 0, 0, 0, 0]
  let _ = apply_entry_hazards(
    [flying], 0, [false], hps, st, rk, 1, 3, 2, 1, weather,
  )
  @debug.assert_eq(hps[0], 150)
  @debug.assert_eq(rk[4], 0)
  assert_true(st[0] is @model.StatusCondition::None)
  hps[0] = 200
  let tox = apply_entry_hazards(
    [lev], 0, [false], hps, st, rk, 0, 3, 2, 1, weather,
  )
  @debug.assert_eq(hps[0], 200)
  @debug.assert_eq(rk[4], 0)
  @debug.assert_eq(tox, 2)
  hps[0] = 200
  let _ = apply_entry_hazards(
    [balloon], 0, [false], hps, st, rk, 0, 3, 0, 1, weather,
  )
  @debug.assert_eq(hps[0], 200)
  @debug.assert_eq(rk[4], 0)
  hps[0] = 200
  let _ = apply_entry_hazards(
    [ball], 0, [false], hps, st, rk, 0, 1, 0, 0, weather,
  )
  @debug.assert_eq(hps[0], 175)
}

///|
test "magic guard blocks hazard chip but not web or toxic spikes" {
  let mon = hz_mon("G", "ノーマル", "", 200, 100, [], ability="マジックガード")
  let hps = [200]
  let st = [@model.StatusCondition::None]
  let rk = [0, 0, 0, 0, 0]
  let _ = apply_entry_hazards(
    [mon], 0, [false], hps, st, rk, 1, 3, 1, 1, @model.Weather::None,
  )
  @debug.assert_eq(hps[0], 200)
  @debug.assert_eq(rk[4], -1)
  assert_true(st[0] is @model.Poison)
}

///|
test "setting hazards caps layers and magic bounce only reflects setters" {
  let sr = hz_set("ステルスロック")
  let spikes = hz_set("まきびし")
  let web = hz_set("ねばねばネット")
  let fast = hz_mon("Fast", "ノーマル", "", 200, 200, [sr])
  let mirror = hz_mon("Mirror", "ノーマル", "", 200, 40, [hz_set("はねる")], ability="マジックミラー")
  let both = hz_mon("Both", "ノーマル", "", 200, 200, [sr], ability="マジックミラー")
  let mold = hz_mon("Mold", "ノーマル", "", 200, 200, [sr], ability="かたやぶり")
  let slow = hz_mon("Slow", "ノーマル", "", 200, 40, [hz_set("はねる")])
  let cache = new_damage_cache()
  let st = rg_state([200, 200], [200, 200])
  let (my_t, opp_t) = ([fast, fast], [slow, slow])
  let set = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my_t, opp_t, cache,
  )
  @debug.assert_eq(set.length(), 1)
  @debug.assert_eq(set[0].1.opp_stealth, 1)
  @debug.assert_eq(set[0].1.my_stealth, 0)
  @debug.assert_eq(set[0].1.my_hps[0], 200)
  @debug.assert_eq(set[0].1.opp_hps[0], 200)
  let capped = { ..set[0].1, opp_spikes: 3 }
  let (my_sp, _) = ([hz_mon("S", "ノーマル", "", 200, 200, [spikes]), fast], opp_t)
  let again = transition_with_cache(
    capped, ActionKind::UseMove(0), ActionKind::UseMove(0), my_sp, opp_t, cache,
  )
  @debug.assert_eq(again[0].1.opp_spikes, 3)
  let (my_m, opp_m) = ([fast, fast], [mirror, mirror])
  let bounced = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my_m, opp_m, cache,
  )
  @debug.assert_eq(bounced[0].1.my_stealth, 1)
  @debug.assert_eq(bounced[0].1.opp_stealth, 0)
  let (my_b, opp_b) = ([both, both], [mirror, mirror])
  let failed = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my_b, opp_b, cache,
  )
  @debug.assert_eq(failed[0].1.my_stealth, 0)
  @debug.assert_eq(failed[0].1.opp_stealth, 0)
  let (my_mb, _) = ([mold, mold], opp_m)
  let broken = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my_mb, opp_m, cache,
  )
  @debug.assert_eq(broken[0].1.opp_stealth, 1)
  @debug.assert_eq(broken[0].1.my_stealth, 0)
  let (my_w, _) = ([hz_mon("W", "ノーマル", "", 200, 200, [web]), fast], opp_t)
  let webbed = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my_w, opp_t, cache,
  )
  @debug.assert_eq(webbed[0].1.opp_web, 1)
  let switched = transition_with_cache(
    webbed[0].1, ActionKind::Switch(1), ActionKind::Switch(1), my_w, opp_t, cache,
  )
  @debug.assert_eq(switched[0].1.opp_web, 1)
  @debug.assert_eq(switched[0].1.opp_ranks[4], -1)
  @debug.assert_eq(switched[0].1.opp_hps[1], 200)
}

///|
test "switch-in takes stealth rock; layers survive another switch and eot" {
  let sr = hz_set("ステルスロック")
  let splash = hz_set("はねる")
  let fast = hz_mon("Fast", "ノーマル", "", 200, 200, [sr])
  let bench = hz_mon("Bench", "ほのお", "", 200, 40, [splash])
  let slow = hz_mon("Slow", "ノーマル", "", 200, 40, [splash])
  let cache = new_damage_cache()
  let st = rg_state([200, 200], [200, 200])
  let my = [fast, fast]
  let opp = [slow, bench]
  let set = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my, opp, cache,
  )
  let came = transition_with_cache(
    set[0].1, ActionKind::Switch(1), ActionKind::Switch(1), my, opp, cache,
  )
  @debug.assert_eq(came[0].1.opp_stealth, 1)
  @debug.assert_eq(came[0].1.opp_active, 1)
  @debug.assert_eq(came[0].1.opp_hps[1], 150)
  @debug.assert_eq(came[0].1.my_hps[1], 200)
  let stayed = transition_with_cache(
    came[0].1, ActionKind::Switch(0), ActionKind::Switch(0), my, opp, cache,
  )
  @debug.assert_eq(stayed[0].1.opp_stealth, 1)
  let ticked = apply_eot(stayed[0].1, my, opp)
  @debug.assert_eq(ticked.opp_stealth, 1)
}

///|
test "rapid spin and killer spin clear the user side; defog clears the target" {
  let spin = mk_move("こうそくスピン", "ノーマル", @model.Physical, 50, accuracy=101)
  let killer = mk_move("キラースピン", "どく", @model.Physical, 30, accuracy=101)
  let defog = hz_set("きりばらい")
  let splash = hz_set("はねる")
  let brick = mk_move("かわらわり", "かくとう", @model.Physical, 75, accuracy=101)
  let cache = new_damage_cache()
  let st = {
    ..rg_state([200, 200], [200, 200]),
    my_stealth: 1,
    my_spikes: 2,
    my_bind: 3,
    opp_stealth: 1,
    opp_reflect: 5,
    opp_light: 4,
  }
  let spinner = hz_mon("Spin", "ノーマル", "", 200, 200, [spin])
  let foe = hz_mon("Foe", "ノーマル", "", 200, 40, [splash])
  let my = [spinner, spinner]
  let opp = [foe, foe]
  let spun = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), my, opp, cache,
  )
  for leaf in spun {
    @debug.assert_eq(leaf.1.my_stealth, 0)
    @debug.assert_eq(leaf.1.my_spikes, 0)
    @debug.assert_eq(leaf.1.my_bind, 0)
    @debug.assert_eq(leaf.1.opp_stealth, 1)
    @debug.assert_eq(leaf.1.my_ranks[4], 1)
  }
  let poisoner = hz_mon("Kill", "ノーマル", "", 200, 200, [killer])
  let poisoned = transition_with_cache(
    { ..st, my_bind: 0 },
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    [poisoner, poisoner],
    opp,
    cache,
  )
  for leaf in poisoned {
    @debug.assert_eq(leaf.1.my_stealth, 0)
    assert_true(leaf.1.opp_status[0] is @model.Poison)
  }
  let fogger = hz_mon("Fog", "ノーマル", "", 200, 200, [defog])
  let fogged = transition_with_cache(
    st, ActionKind::UseMove(0), ActionKind::UseMove(0), [fogger, fogger], opp, cache,
  )
  @debug.assert_eq(fogged.length(), 1)
  @debug.assert_eq(fogged[0].1.opp_stealth, 0)
  @debug.assert_eq(fogged[0].1.opp_reflect, 0)
  @debug.assert_eq(fogged[0].1.opp_light, 0)
  @debug.assert_eq(fogged[0].1.my_stealth, 1)
  @debug.assert_eq(fogged[0].1.my_spikes, 2)
  let clear = { ..st, my_stealth: 0, my_spikes: 0, my_bind: 0, opp_stealth: 0 }
  let fog_only = transition_with_cache(
    clear, ActionKind::UseMove(0), ActionKind::UseMove(0), [fogger, fogger], opp, cache,
  )
  @debug.assert_eq(fog_only[0].1.opp_reflect, 0)
  @debug.assert_eq(fog_only[0].1.opp_light, 0)
  @debug.assert_eq(fog_only[0].1.opp_stealth, 0)
  @debug.assert_eq(fog_only[0].1.my_hps[0], 200)
  @debug.assert_eq(fog_only[0].1.opp_hps[0], 200)
  let breaker = hz_mon("Brick", "ノーマル", "", 200, 200, [brick])
  let smashed = transition_with_cache(
    { ..st, my_bind: 0 },
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    [breaker, breaker],
    opp,
    cache,
  )
  for leaf in smashed {
    @debug.assert_eq(leaf.1.opp_reflect, 0)
    @debug.assert_eq(leaf.1.opp_stealth, 1)
  }
}

///|
test "court change swaps hazards only; tidy up clears both; stone axe sets rocks" {
  let court = hz_set("コートチェンジ")
  let tidy = hz_set("おかたづけ")
  let axe = mk_move("がんせきアックス", "いわ", @model.Physical, 65, accuracy=101)
  let splash = hz_set("はねる")
  let cache = new_damage_cache()
  let st = {
    ..rg_state([200, 200], [200, 200]),
    my_spikes: 2,
    opp_stealth: 1,
    my_reflect: 5,
    opp_reflect: 3,
  }
  let user = hz_mon("U", "ノーマル", "", 200, 200, [court])
  let foe = hz_mon("F", "ノーマル", "", 200, 40, [splash])
  let swapped = transition_with_cache(
    st,
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    [user, user],
    [foe, foe],
    cache,
  )
  @debug.assert_eq(swapped[0].1.my_spikes, 0)
  @debug.assert_eq(swapped[0].1.opp_spikes, 2)
  @debug.assert_eq(swapped[0].1.my_stealth, 1)
  @debug.assert_eq(swapped[0].1.opp_stealth, 0)
  @debug.assert_eq(swapped[0].1.my_reflect, 5)
  @debug.assert_eq(swapped[0].1.opp_reflect, 3)
  let none = transition_with_cache(
    rg_state([200, 200], [200, 200]),
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    [user, user],
    [foe, foe],
    cache,
  )
  @debug.assert_eq(none[0].1.my_stealth, 0)
  @debug.assert_eq(none[0].1.opp_stealth, 0)
  let cleaner = hz_mon("C", "ノーマル", "", 200, 200, [tidy])
  let cleaned = transition_with_cache(
    st,
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    [cleaner, cleaner],
    [foe, foe],
    cache,
  )
  @debug.assert_eq(cleaned[0].1.my_spikes, 0)
  @debug.assert_eq(cleaned[0].1.opp_stealth, 0)
  @debug.assert_eq(cleaned[0].1.my_ranks[0], 1)
  @debug.assert_eq(cleaned[0].1.my_ranks[4], 1)
  @debug.assert_eq(cleaned[0].1.my_reflect, 5)
  let axer = hz_mon("A", "ノーマル", "", 200, 200, [axe])
  let axed = transition_with_cache(
    rg_state([200, 200], [200, 200]),
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    [axer, axer],
    [foe, foe],
    cache,
  )
  for leaf in axed {
    @debug.assert_eq(leaf.1.opp_stealth, 1)
  }
  let sheer = hz_mon("Sh", "ノーマル", "", 200, 200, [axe], ability="ちからずく")
  let stripped = transition_with_cache(
    rg_state([200, 200], [200, 200]),
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    [sheer, sheer],
    [foe, foe],
    cache,
  )
  for leaf in stripped {
    @debug.assert_eq(leaf.1.opp_stealth, 0)
  }
}

///|
test "a hazard ko skips the opponent move and that side's intimidate" {
  let splash = hz_set("はねる")
  let spikes = hz_set("まきびし")
  let lead = hz_mon("Lead", "ノーマル", "", 200, 50, [splash])
  let frail = hz_mon("Frail", "ほのお", "", 1, 50, [splash], ability="いかく")
  let foe = hz_mon("Foe", "ノーマル", "", 200, 200, [spikes])
  let cache = new_damage_cache()
  let st = { ..rg_state([200, 1], [200, 200]), my_stealth: 1 }
  let my = [lead, frail]
  let opp = [foe, foe]
  let outs = transition_with_cache(
    st, ActionKind::Switch(1), ActionKind::UseMove(0), my, opp, cache,
  )
  @debug.assert_eq(outs.length(), 1)
  @debug.assert_eq(outs[0].1.my_hps[1], 0)
  @debug.assert_eq(outs[0].1.my_spikes, 0)
  @debug.assert_eq(outs[0].1.opp_ranks[0], 0)
}

///|
test "moves that are not hazards leave every layer at zero" {
  let splash = hz_set("はねる")
  let tackle = mk_move("たいあたり", "ノーマル", @model.Physical, 40, accuracy=101)
  let fast = hz_mon("Fast", "ノーマル", "", 200, 200, [splash])
  let slow = hz_mon("Slow", "ノーマル", "", 200, 40, [tackle])
  let cache = new_damage_cache()
  let st = rg_state([200, 200], [200, 200])
  let outs = transition_with_cache(
    st,
    ActionKind::UseMove(0),
    ActionKind::UseMove(0),
    [fast, fast],
    [slow, slow],
    cache,
  )
  assert_true(outs.length() > 0)
  for leaf in outs {
    assert_false(state_any_hazard(leaf.1))
  }
}

///|
test "mc sets stealth rock on the foe side and chips the switch-in" {
  let sr = hz_set("ステルスロック")
  let atk = hz_mon("A", "ノーマル", "", 200, 100, [sr])
  let def = hz_mon("D", "ほのお", "", 200, 100, [sr])
  let buf = [0, 0, 0, 0, 0, 0, 0, 0]
  let (hp, _, _, _) = team_perform_attack(
    atk,
    def,
    200,
    sr,
    seeded_rng(1),
    [0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0],
    hazard_io=buf,
    attacker_is_own=true,
  )
  @debug.assert_eq(hp, 200)
  @debug.assert_eq(buf[4], 1)
  let hps = [200]
  let st = [@model.StatusCondition::None]
  let rk = [0, 0, 0, 0, 0]
  let ko = mc_entry_hazards(
    buf, false, [def], 0, hps, st, rk, @model.Weather::None,
  )
  @debug.assert_eq(hps[0], 150)
  assert_false(ko)
  buf[0] = 1
  let spin = mk_move("こうそくスピン", "ノーマル", @model.Physical, 50, accuracy=101)
  let _ = team_perform_attack(
    atk, def, hps[0], spin, seeded_rng(2), rk, [0, 0, 0, 0, 0],
    hazard_io=buf, attacker_is_own=false,
  )
  @debug.assert_eq(buf[4], 0)
  @debug.assert_eq(buf[0], 1)
}
