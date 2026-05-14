///|
test "calc_hp_full: ガブリアス HP108, IV31, EV0" {
  @debug.debug_inspect(calc_hp_full(108, 31, 0), content="183")
}

///|
test "calc_hp_full: ガブリアス HP108, IV31, EV252" {
  @debug.debug_inspect(calc_hp_full(108, 31, 252), content="215")
}

///|
test "calc_hp_full: IV0, EV0" {
  // floor((108*2 + 0 + 0) * 50 / 100) + 60 = 108 + 60 = 168
  @debug.debug_inspect(calc_hp_full(108, 0, 0), content="168")
}

///|
test "calc_hp_full: ヌケニン base=1" {
  // floor((1*2 + 31 + 0) * 50 / 100) + 60 = floor(16.5) + 60 = 16 + 60 = 76
  // But Shedinja always has 1 HP — handled at caller level
  @debug.debug_inspect(calc_hp_full(1, 31, 0), content="76")
}

///|
test "calc_other_full: ガブリアス Atk130, IV31, EV252, nature up" {
  @debug.debug_inspect(calc_other_full(130, 31, 252, 11, 10), content="200")
}

///|
test "calc_other_full: ガブリアス Spe102, IV31, EV252, neutral" {
  // floor((102*2 + 31 + 63) * 50 / 100) + 5 = floor(148.5) + 5 = 148 + 5 = 153
  // neutral: 153 * 1 / 1 = 153
  @debug.debug_inspect(calc_other_full(102, 31, 252, 1, 1), content="154")
}

///|
test "calc_other_full: nature down" {
  // base=130, iv=31, ev=252: raw = floor((130*2+31+63)*50/100)+5 = 182+5 = 182
  // Wait: (260+31+63)=354, 354*50/100=177, +5=182
  // down: 182 * 9 / 10 = 163
  @debug.debug_inspect(calc_other_full(130, 31, 252, 9, 10), content="163")
}

///|
test "calc_other_full: IV0, EV0, neutral" {
  // (130*2+0+0)*50/100+5 = 130+5 = 135
  @debug.debug_inspect(calc_other_full(130, 0, 0, 1, 1), content="135")
}

///|
test "calc_stat refactor: HP matches calc_hp_full" {
  // existing calc_stat with is_hp=true uses base+107 (IV31, EV252)
  // calc_hp_full(108, 31, 252) should equal 108+107=215
  @debug.debug_inspect(calc_hp_full(108, 31, 252), content="215")
  @debug.debug_inspect(calc_stat(108, is_hp=true), content="215")
}

///|
test "calc_stat refactor: Atk matches calc_other_full with nature boost" {
  // existing calc_stat uses (base+52)*11/10 (IV31, EV252, nature_boost=true)
  // calc_other_full(130, 31, 252, 11, 10) should match
  let old_result = calc_stat(130)
  let new_result = calc_other_full(130, 31, 252, 11, 10)
  assert_true(old_result == new_result)
}

///|
test "calc_stat refactor: no nature boost" {
  let old_result = calc_stat(130, nature_num=1, nature_den=1)
  let new_result = calc_other_full(130, 31, 252, 1, 1)
  assert_true(old_result == new_result)
}

///|
test "calc_all_stats: ガブリアス いじっぱり AS252 D4" {
  let pokemon : @model.Pokemon = {
    global_no: "0445",
    name_ja: "ガブリアス",
    name_en: "Garchomp",
    type1: "ドラゴン",
    type2: "じめん",
    hp: 108,
    atk: 130,
    def_: 95,
    spa: 80,
    spd: 85,
    spe: 102,
    bst: 600,
    ability1: "すながくれ",
    ability2: "",
    dream_ability: "さめはだ",
    weight: 95.0,
    forms: [],
  }
  let ivs : FixedArray[Int] = [31, 31, 31, 31, 31, 31]
  let evs : FixedArray[Int] = [0, 252, 0, 0, 4, 252]
  match @model.nature_from_ja("いじっぱり") {
    Some(nature) => {
      let stats = calc_all_stats(pokemon, ivs, evs, nature)
      @debug.debug_inspect(stats[0], content="183") // HP
      @debug.debug_inspect(stats[1], content="200") // Atk (↑)
      @debug.debug_inspect(stats[2], content="115") // Def
      @debug.debug_inspect(stats[3], content="90") // SpA (↓)
      @debug.debug_inspect(stats[4], content="106") // SpD
      @debug.debug_inspect(stats[5], content="154") // Spe (neutral, EV252)
    }
    None => fail("nature not found")
  }
}

///|
test "reverse_base_from_stat: Atk 200 → base 130" {
  @debug.debug_inspect(reverse_base_from_stat(200, 31, 252, false, 11, 10), content="130")
}

///|
test "reverse_base_from_stat: HP 183 → base 108" {
  @debug.debug_inspect(reverse_base_from_stat(183, 31, 0, true, 1, 1), content="108")
}

///|
test "reverse_base_from_stat: round-trip various bases" {
  // Test HP round-trip
  let bases = [1, 50, 80, 108, 130, 200, 255]
  for i = 0; i < bases.length(); i = i + 1 {
    let base = bases[i]
    let actual = calc_hp_full(base, 31, 0)
    let recovered = reverse_base_from_stat(actual, 31, 0, true, 1, 1)
    assert_true(recovered == base)
  }
  // Test other stat round-trip (nature up)
  for i = 0; i < bases.length(); i = i + 1 {
    let base = bases[i]
    let actual = calc_other_full(base, 31, 252, 11, 10)
    let recovered = reverse_base_from_stat(actual, 31, 252, false, 11, 10)
    assert_true(recovered == base)
  }
}

///|
test "reverse_spread: ガブリアス 183/200/115/90/106/154" {
  let pokemon : @model.Pokemon = {
    global_no: "0445",
    name_ja: "ガブリアス",
    name_en: "Garchomp",
    type1: "ドラゴン",
    type2: "じめん",
    hp: 108,
    atk: 130,
    def_: 95,
    spa: 80,
    spd: 85,
    spe: 102,
    bst: 600,
    ability1: "すながくれ",
    ability2: "",
    dream_ability: "さめはだ",
    weight: 95.0,
    forms: [],
  }
  let actual_stats : FixedArray[Int] = [183, 200, 115, 90, 106, 154]
  let results = reverse_spread(pokemon, actual_stats, 31)
  // Should find いじっぱり with EVs 0/252/0/0/4/252
  assert_true(results.length() > 0)
  let found = {
    let mut f = false
    for i = 0; i < results.length(); i = i + 1 {
      let (nature, evs) = results[i]
      if nature.name_ja == "いじっぱり" &&
        evs[0] == 0 &&
        evs[1] == 252 &&
        evs[2] == 0 &&
        evs[3] == 0 &&
        evs[4] == 4 &&
        evs[5] == 252 {
        f = true
      }
    }
    f
  }
  assert_true(found)
}

///|
test "ev_for_hp: ガブリアス HP108 target=183 (=EV0 value)" {
  // calc_hp_full(108, 31, 0) == 183, so target 183 should need EV 0
  @debug.debug_inspect(ev_for_hp(108, 31, 183), content="0")
}

///|
test "ev_for_hp: ガブリアス target=184 one above baseline" {
  // inner(0)=247 → 247*50/100=123 → HP 183
  // inner(4 EV, f(4/4)=1)=248 → 124 → HP 184
  @debug.debug_inspect(ev_for_hp(108, 31, 184), content="4")
}

///|
test "ev_for_hp: ガブリアス target=215 (=EV252 value)" {
  @debug.debug_inspect(ev_for_hp(108, 31, 215), content="252")
}

///|
test "ev_for_hp: target unreachable → 256 sentinel" {
  @debug.debug_inspect(ev_for_hp(108, 31, 999), content="256")
}

///|
test "ev_for_hp: monotonic forward↔reverse" {
  let base = 100
  for ev_idx = 0; ev_idx <= 63; ev_idx = ev_idx + 1 {
    let ev = ev_idx * 4
    let stat = calc_hp_full(base, 31, ev)
    let back = ev_for_hp(base, 31, stat)
    assert_true(back <= ev)
    assert_true(calc_hp_full(base, 31, back) == stat)
  }
}

///|
test "ev_for_non_hp: neutral nature" {
  // base=95 iv=31 ev=0: inner=221, floor(221/2)=110, raw=115
  @debug.debug_inspect(calc_other_full(95, 31, 0, 1, 1), content="115")
  @debug.debug_inspect(ev_for_non_hp(95, 31, 115, 1, 1), content="0")
  // ev=4: inner=222, floor=111, raw=116
  @debug.debug_inspect(calc_other_full(95, 31, 4, 1, 1), content="116")
  @debug.debug_inspect(ev_for_non_hp(95, 31, 116, 1, 1), content="4")
}

///|
test "ev_for_non_hp: +10% nature" {
  // calc_other_full(108, 31, 252, 11, 10): raw=(108*2+31+63)*50/100+5=floor(310/2)+5=155+5=160, then 160*11/10=176
  @debug.debug_inspect(calc_other_full(108, 31, 252, 11, 10), content="176")
  @debug.debug_inspect(ev_for_non_hp(108, 31, 176, 11, 10), content="252")
}

///|
test "ev_for_non_hp: -10% nature" {
  // calc_other_full(95, 31, 0, 9, 10): raw=115, 115*9/10=103
  @debug.debug_inspect(calc_other_full(95, 31, 0, 9, 10), content="103")
  @debug.debug_inspect(ev_for_non_hp(95, 31, 103, 9, 10), content="0")
}

///|
test "ev_for_non_hp: unreachable → 256" {
  @debug.debug_inspect(ev_for_non_hp(95, 31, 9999, 11, 10), content="256")
}

///|
test "ev_for_non_hp: monotonic forward↔reverse (neutral)" {
  let base = 85
  for ev_idx = 0; ev_idx <= 63; ev_idx = ev_idx + 1 {
    let ev = ev_idx * 4
    let stat = calc_other_full(base, 31, ev, 1, 1)
    let back = ev_for_non_hp(base, 31, stat, 1, 1)
    assert_true(back <= ev)
    assert_true(calc_other_full(base, 31, back, 1, 1) == stat)
  }
}

///|
test "ev_for_non_hp: monotonic forward↔reverse (+10%)" {
  let base = 85
  for ev_idx = 0; ev_idx <= 63; ev_idx = ev_idx + 1 {
    let ev = ev_idx * 4
    let stat = calc_other_full(base, 31, ev, 11, 10)
    let back = ev_for_non_hp(base, 31, stat, 11, 10)
    assert_true(back <= ev)
    assert_true(calc_other_full(base, 31, back, 11, 10) == stat)
  }
}

///|
test "apply_rank: stage 0" {
  @debug.debug_inspect(apply_rank(100, 0), content="100")
}

///|
test "apply_rank: stage +1" {
  @debug.debug_inspect(apply_rank(100, 1), content="150")
}

///|
test "apply_rank: stage +2" {
  @debug.debug_inspect(apply_rank(100, 2), content="200")
}

///|
test "apply_rank: stage +6" {
  @debug.debug_inspect(apply_rank(100, 6), content="400")
}

///|
test "apply_rank: stage -1" {
  @debug.debug_inspect(apply_rank(100, -1), content="66")
}

///|
test "apply_rank: stage -2" {
  @debug.debug_inspect(apply_rank(100, -2), content="50")
}

///|
test "apply_rank: stage -6" {
  @debug.debug_inspect(apply_rank(100, -6), content="25")
}

///|
test "apply_rank: floor -1 on 133" {
  @debug.debug_inspect(apply_rank(133, -1), content="88")
}

///|
test "apply_rank: clamp upper" {
  @debug.debug_inspect(apply_rank(100, 10), content="400")
}

///|
test "apply_rank: clamp lower" {
  @debug.debug_inspect(apply_rank(100, -10), content="25")
}

// ──────────────────────────────────────────────
// Champions SP calculation tests
// ──────────────────────────────────────────────

///|
test "calc_hp_champions: ガブリアス HP108, SP=0" {
  @debug.debug_inspect(calc_hp_champions(108, 0), content="183")
}

///|
test "calc_hp_champions: ガブリアス HP108, SP=32" {
  // 108 + 32 + 75 = 215
  // (same result as traditional IV31/EV252, different formula)
  @debug.debug_inspect(calc_hp_champions(108, 32), content="215")
}

///|
test "calc_hp_champions: base=1, SP=0" {
  @debug.debug_inspect(calc_hp_champions(1, 0), content="76")
}

///|
test "calc_other_champions: ガブリアス Atk130, SP=32, nature up" {
  // (130 + 32 + 20) * 11 / 10 = 182 * 11 / 10 = 200
  @debug.debug_inspect(calc_other_champions(130, 32, 11, 10), content="200")
}

///|
test "calc_other_champions: ガブリアス SpA80, SP=0, nature down" {
  // (80 + 0 + 20) * 9 / 10 = 100 * 9 / 10 = 90
  @debug.debug_inspect(calc_other_champions(80, 0, 9, 10), content="90")
}

///|
test "calc_other_champions: ガブリアス Def95, SP=0, neutral" {
  // (95 + 0 + 20) * 1 / 1 = 115
  @debug.debug_inspect(calc_other_champions(95, 0, 1, 1), content="115")
}

///|
test "calc_other_champions: nature up +2 at 11n boundary" {
  // (102 + 32 + 20) = 154, 154 * 11 / 10 = 1694 / 10 = 169
  @debug.debug_inspect(calc_other_champions(102, 32, 11, 10), content="169")
  // SP=31: (102 + 31 + 20) = 153, 153 * 11 / 10 = 1683 / 10 = 168
  @debug.debug_inspect(calc_other_champions(102, 31, 11, 10), content="168")
}

///|
test "calc_stat_champions: HP shortcut (SP=32)" {
  @debug.debug_inspect(calc_stat_champions(108, is_hp=true), content="215")
}

///|
test "calc_stat_champions: Atk shortcut with nature boost" {
  @debug.debug_inspect(calc_stat_champions(130), content="200")
}

///|
test "calc_stat_champions: custom override" {
  @debug.debug_inspect(calc_stat_champions(130, custom=999), content="999")
}

///|
test "calc_all_stats_champions: ガブリアス ようき SP=[0,32,0,0,0,32]" {
  let pokemon = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let sps : FixedArray[Int] = [0, 32, 0, 0, 0, 32]
  match @model.nature_from_ja("ようき") {
    Some(nature) => {
      let stats = calc_all_stats_champions(pokemon, sps, nature)
      @debug.debug_inspect(stats[0], content="183") // HP: 108+0+75
      @debug.debug_inspect(stats[1], content="182") // Atk: (130+32+20)*1/1 (ようき neutral for Atk)
      @debug.debug_inspect(stats[2], content="115") // Def: (95+0+20)*1/1
      @debug.debug_inspect(stats[3], content="90") // SpA: (80+0+20)*9/10 (↓)
      @debug.debug_inspect(stats[4], content="105") // SpD: (85+0+20)*1/1
      @debug.debug_inspect(stats[5], content="169") // Spe: (102+32+20)*11/10 (↑)
    }
    None => fail("nature not found")
  }
}

///|
test "sp_for_hp_champions: target=183 (SP=0)" {
  @debug.debug_inspect(sp_for_hp_champions(108, 183), content="0")
}

///|
test "sp_for_hp_champions: target=215 (SP=32)" {
  @debug.debug_inspect(sp_for_hp_champions(108, 215), content="32")
}

///|
test "sp_for_hp_champions: unreachable → 33 sentinel" {
  @debug.debug_inspect(sp_for_hp_champions(108, 999), content="33")
}

///|
test "sp_for_hp_champions: target below minimum → 0" {
  // target = 100 < 108+0+75=183, sp would be negative → clamp to 0
  @debug.debug_inspect(sp_for_hp_champions(108, 100), content="0")
}

///|
test "sp_for_non_hp_champions: neutral, target=115 (SP=0)" {
  @debug.debug_inspect(sp_for_non_hp_champions(95, 115, 1, 1), content="0")
}

///|
test "sp_for_non_hp_champions: neutral, target=147 (SP=32)" {
  // (95+32+20)*1/1 = 147
  @debug.debug_inspect(sp_for_non_hp_champions(95, 147, 1, 1), content="32")
}

///|
test "sp_for_non_hp_champions: nature up, target=200" {
  // (130+sp+20)*11/10 >= 200 → sp+150 >= ceil(200*10/11)=182 → sp >= 32
  @debug.debug_inspect(sp_for_non_hp_champions(130, 200, 11, 10), content="32")
}

///|
test "sp_for_non_hp_champions: nature down, target=90" {
  // (80+sp+20)*9/10 >= 90 → sp+100 >= ceil(90*10/9)=100 → sp >= 0
  @debug.debug_inspect(sp_for_non_hp_champions(80, 90, 9, 10), content="0")
}

///|
test "sp_for_non_hp_champions: unreachable → 33 sentinel" {
  @debug.debug_inspect(sp_for_non_hp_champions(95, 9999, 11, 10), content="33")
}

///|
test "sp_for_non_hp_champions: round-trip all SP values" {
  let base = 100
  for sp = 0; sp <= 32; sp = sp + 1 {
    let stat = calc_other_champions(base, sp, 11, 10)
    let back = sp_for_non_hp_champions(base, stat, 11, 10)
    assert_true(back <= sp)
    assert_true(calc_other_champions(base, back, 11, 10) == stat)
  }
}

///|
test "reverse_base_from_stat_champions: HP 183 → base 108" {
  @debug.debug_inspect(reverse_base_from_stat_champions(183, 0, true, 1, 1), content="108")
}

///|
test "reverse_base_from_stat_champions: Atk 200, SP=32, nature up → base 130" {
  @debug.debug_inspect(
    reverse_base_from_stat_champions(200, 32, false, 11, 10), content="130",
  )
}

///|
test "reverse_base_from_stat_champions: round-trip" {
  let bases = [1, 50, 80, 108, 130, 200, 255]
  for i = 0; i < bases.length(); i = i + 1 {
    let base = bases[i]
    let actual_hp = calc_hp_champions(base, 16)
    let recovered_hp = reverse_base_from_stat_champions(
      actual_hp, 16, true, 1, 1,
    )
    assert_true(recovered_hp == base)
    let actual_other = calc_other_champions(base, 16, 11, 10)
    let recovered_other = reverse_base_from_stat_champions(
      actual_other, 16, false, 11, 10,
    )
    assert_true(recovered_other == base)
  }
}

///|
test "reverse_spread_champions: ガブリアス 183/182/115/90/105/169" {
  let pokemon = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let actual_stats : FixedArray[Int] = [183, 182, 115, 90, 105, 169]
  let results = reverse_spread_champions(pokemon, actual_stats)
  assert_true(results.length() > 0)
  let found = {
    let mut f = false
    for i = 0; i < results.length(); i = i + 1 {
      let (nature, sps) = results[i]
      if nature.name_ja == "ようき" &&
        sps[0] == 0 &&
        sps[1] == 32 &&
        sps[2] == 0 &&
        sps[3] == 0 &&
        sps[4] == 0 &&
        sps[5] == 32 {
        f = true
      }
    }
    f
  }
  assert_true(found)
}

///|
test "reverse_spread_champions: total SP <= 66 enforced" {
  let pokemon = mk_pokemon("ガブリアス", 108, 130, 95, 80, 85, 102)
  let actual_stats : FixedArray[Int] = [183, 182, 115, 90, 105, 169]
  let results = reverse_spread_champions(pokemon, actual_stats)
  for i = 0; i < results.length(); i = i + 1 {
    let (_, sps) = results[i]
    let mut total = 0
    for j = 0; j < 6; j = j + 1 {
      total = total + sps[j]
    }
    assert_true(total <= 66)
  }
}

// ──────────────────────────────────────────────
// B-4-pre: calc_stat* wrappers parameterised golden pin (pre-H7 refactor)
//
// These tests pin the numeric output of the 4 public wrappers and the
// equivalence between StatModel methods and the underlying primitives.
// The H7 refactor will route calc_stat through Standard(ivs=...).calc_other;
// any regression in stat_idx selection, IV dispatch, or rounding will
// surface here as a snapshot mismatch. Standard with IV=31/EV=252 has the
// invariant that values equal Champions with SP=32 (and IV=31/EV=0 == SP=0),
// which lets the same expected-value table cover both systems.
// ──────────────────────────────────────────────

///|
test "calc_stat wrappers: HP-side parameterised golden" {
  // is_hp=true: nature args ignored. Standard IV=31/EV=252 == Champions SP=32 == base+107.
  // Standard IV=31/EV=0 == Champions SP=0 == base+75.
  let bases = [60, 90, 130]
  for i = 0; i < bases.length(); i = i + 1 {
    let b = bases[i]
    let off = b + 107
    let def_ = b + 75
    assert_true(calc_stat(b, is_hp=true) == off)
    assert_true(calc_stat_champions(b, is_hp=true) == off)
    assert_true(calc_def_stat(b, is_hp=true) == def_)
    assert_true(calc_def_stat_champions(b, is_hp=true) == def_)
  }
}

///|
test "calc_stat wrappers: non-HP parameterised golden across natures" {
  // EV=252/SP=32 raw = base + 52; EV=0/SP=0 raw = base + 20. Then floor(raw * num/den).
  // Cases: (base, nature_num, nature_den, expected_offense, expected_defense)
  let cases : Array[(Int, Int, Int, Int, Int)] = [
    (60, 1, 1, 112, 80), // 112*1/1, 80*1/1
    (60, 11, 10, 123, 88), // 1232/10=123, 880/10=88
    (60, 9, 10, 100, 72), // 1008/10=100, 720/10=72
    (90, 1, 1, 142, 110),
    (90, 11, 10, 156, 121), // 1562/10=156, 1210/10=121
    (90, 9, 10, 127, 99), // 1278/10=127, 990/10=99
    (130, 1, 1, 182, 150),
    (130, 11, 10, 200, 165), // 2002/10=200, 1650/10=165
    (130, 9, 10, 163, 135), // 1638/10=163, 1350/10=135
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (b, nn, nd, off, def_) = cases[i]
    assert_true(calc_stat(b, nature_num=nn, nature_den=nd) == off)
    assert_true(calc_stat_champions(b, nature_num=nn, nature_den=nd) == off)
    assert_true(calc_def_stat(b, nature_num=nn, nature_den=nd) == def_)
    assert_true(calc_def_stat_champions(b, nature_num=nn, nature_den=nd) == def_)
  }
}

///|
test "calc_stat wrappers: custom override short-circuits all 4" {
  assert_true(calc_stat(130, custom=999) == 999)
  assert_true(calc_def_stat(130, custom=999) == 999)
  assert_true(calc_stat_champions(130, custom=999) == 999)
  assert_true(calc_def_stat_champions(130, custom=999) == 999)
}

///|
test "StatModel: Standard methods equal primitives across (ivs, base, ev, idx, nature)" {
  // After H7, calc_stat dispatches via Standard(ivs).calc_hp/calc_other.
  // Pin: model.calc_hp(base, ev) == calc_hp_full(base, ivs[0], ev) and
  //      model.calc_other(idx, base, ev, nn, nd) == calc_other_full(base, ivs[idx], ev, nn, nd).
  // The non-uniform IV row catches stat_idx mistakes (e.g., picking ivs[0] instead of ivs[idx]).
  let iv_rows : Array[FixedArray[Int]] = [
    [28, 28, 28, 28, 28, 28],
    [29, 29, 29, 29, 29, 29],
    [30, 30, 30, 30, 30, 30],
    [31, 31, 31, 31, 31, 31],
    [28, 31, 30, 29, 31, 28], // non-uniform: stat_idx canary
  ]
  let bases = [60, 90, 130]
  let evs = [0, 252]
  let natures : Array[(Int, Int)] = [(1, 1), (11, 10), (9, 10)]
  for ri = 0; ri < iv_rows.length(); ri = ri + 1 {
    let ivs = iv_rows[ri]
    let model : StatModel = Standard(ivs~)
    for bi = 0; bi < bases.length(); bi = bi + 1 {
      let b = bases[bi]
      for ei = 0; ei < evs.length(); ei = ei + 1 {
        let ev = evs[ei]
        assert_true(model.calc_hp(b, ev) == calc_hp_full(b, ivs[0], ev))
        for idx = 0; idx < 6; idx = idx + 1 {
          for ni = 0; ni < natures.length(); ni = ni + 1 {
            let (nn, nd) = natures[ni]
            let via_model = model.calc_other(idx, b, ev, nn, nd)
            let direct = calc_other_full(b, ivs[idx], ev, nn, nd)
            assert_true(via_model == direct)
          }
        }
      }
    }
  }
}

///|
test "StatModel: Champions methods equal primitives across (sp, base, idx, nature)" {
  // Champions ignores stat_idx (no IV system). Pin model.calc_other for all idx ∈ 0..5.
  let model : StatModel = Champions
  let bases = [60, 90, 130]
  let sps = [0, 16, 32]
  let natures : Array[(Int, Int)] = [(1, 1), (11, 10), (9, 10)]
  for bi = 0; bi < bases.length(); bi = bi + 1 {
    let b = bases[bi]
    for si = 0; si < sps.length(); si = si + 1 {
      let sp = sps[si]
      assert_true(model.calc_hp(b, sp) == calc_hp_champions(b, sp))
      for ni = 0; ni < natures.length(); ni = ni + 1 {
        let (nn, nd) = natures[ni]
        for idx = 0; idx < 6; idx = idx + 1 {
          let via_model = model.calc_other(idx, b, sp, nn, nd)
          let direct = calc_other_champions(b, sp, nn, nd)
          assert_true(via_model == direct)
        }
      }
    }
  }
}

// ──────────────────────────────────────────────
// B-6-pre: StatLimits values pin (pre-H6 destructive replacement)
//
// limits() returns a struct bundling the 6 scalar limits. The expected values
// must match the 6 scalar methods today, and remain stable after B-6 removes
// those scalar methods.
// ──────────────────────────────────────────────

///|
test "StatModel limits: Standard values pinned" {
  let std : StatModel = Standard(ivs=FixedArray::make(6, 31))
  let limits = std.limits()
  @debug.debug_inspect(limits.step, content="4")
  @debug.debug_inspect(limits.max_per_stat, content="252")
  @debug.debug_inspect(limits.sentinel, content="256")
  @debug.debug_inspect(limits.step_cap, content="600")
  @debug.debug_inspect(limits.hbd_budget, content="508")
  @debug.debug_inspect(limits.full_budget, content="510")
}

///|
test "StatModel limits: Champions values pinned" {
  let champ : StatModel = Champions
  let limits = champ.limits()
  @debug.debug_inspect(limits.step, content="1")
  @debug.debug_inspect(limits.max_per_stat, content="32")
  @debug.debug_inspect(limits.sentinel, content="33")
  @debug.debug_inspect(limits.step_cap, content="200")
  @debug.debug_inspect(limits.hbd_budget, content="66")
  @debug.debug_inspect(limits.full_budget, content="66")
}
