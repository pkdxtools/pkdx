///|
test "calc_hp_full: ガブリアス HP108, IV31, EV0" {
  inspect(calc_hp_full(108, 31, 0), content="183")
}

///|
test "calc_hp_full: ガブリアス HP108, IV31, EV252" {
  inspect(calc_hp_full(108, 31, 252), content="215")
}

///|
test "calc_hp_full: IV0, EV0" {
  // floor((108*2 + 0 + 0) * 50 / 100) + 60 = 108 + 60 = 168
  inspect(calc_hp_full(108, 0, 0), content="168")
}

///|
test "calc_hp_full: ヌケニン base=1" {
  // floor((1*2 + 31 + 0) * 50 / 100) + 60 = floor(16.5) + 60 = 16 + 60 = 76
  // But Shedinja always has 1 HP — handled at caller level
  inspect(calc_hp_full(1, 31, 0), content="76")
}

///|
test "calc_other_full: ガブリアス Atk130, IV31, EV252, nature up" {
  inspect(calc_other_full(130, 31, 252, 11, 10), content="200")
}

///|
test "calc_other_full: ガブリアス Spe102, IV31, EV252, neutral" {
  // floor((102*2 + 31 + 63) * 50 / 100) + 5 = floor(148.5) + 5 = 148 + 5 = 153
  // neutral: 153 * 1 / 1 = 153
  inspect(calc_other_full(102, 31, 252, 1, 1), content="154")
}

///|
test "calc_other_full: nature down" {
  // base=130, iv=31, ev=252: raw = floor((130*2+31+63)*50/100)+5 = 182+5 = 182
  // Wait: (260+31+63)=354, 354*50/100=177, +5=182
  // down: 182 * 9 / 10 = 163
  inspect(calc_other_full(130, 31, 252, 9, 10), content="163")
}

///|
test "calc_other_full: IV0, EV0, neutral" {
  // (130*2+0+0)*50/100+5 = 130+5 = 135
  inspect(calc_other_full(130, 0, 0, 1, 1), content="135")
}

///|
test "calc_stat refactor: HP matches calc_hp_full" {
  // existing calc_stat with is_hp=true uses base+107 (IV31, EV252)
  // calc_hp_full(108, 31, 252) should equal 108+107=215
  inspect(calc_hp_full(108, 31, 252), content="215")
  inspect(calc_stat(108, is_hp=true), content="215")
}

///|
test "calc_stat refactor: Atk matches calc_other_full with nature boost" {
  // existing calc_stat uses (base+52)*11/10 (IV31, EV252, nature_boost=true)
  // calc_other_full(130, 31, 252, 11, 10) should match
  let old_result = calc_stat(130)
  let new_result = calc_other_full(130, 31, 252, 11, 10)
  inspect(old_result == new_result, content="true")
}

///|
test "calc_stat refactor: no nature boost" {
  let old_result = calc_stat(130, nature_boost=false)
  let new_result = calc_other_full(130, 31, 252, 1, 1)
  inspect(old_result == new_result, content="true")
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
  }
  let ivs : FixedArray[Int] = [31, 31, 31, 31, 31, 31]
  let evs : FixedArray[Int] = [0, 252, 0, 0, 4, 252]
  match @model.nature_from_ja("いじっぱり") {
    Some(nature) => {
      let stats = calc_all_stats(pokemon, ivs, evs, nature)
      inspect(stats[0], content="183") // HP
      inspect(stats[1], content="200") // Atk (↑)
      inspect(stats[2], content="115") // Def
      inspect(stats[3], content="90") // SpA (↓)
      inspect(stats[4], content="106") // SpD
      inspect(stats[5], content="154") // Spe (neutral, EV252)
    }
    None => fail("nature not found")
  }
}

///|
test "reverse_base_from_stat: Atk 200 → base 130" {
  inspect(reverse_base_from_stat(200, 31, 252, false, 11, 10), content="130")
}

///|
test "reverse_base_from_stat: HP 183 → base 108" {
  inspect(reverse_base_from_stat(183, 31, 0, true, 1, 1), content="108")
}

///|
test "reverse_base_from_stat: round-trip various bases" {
  // Test HP round-trip
  let bases = [1, 50, 80, 108, 130, 200, 255]
  for i = 0; i < bases.length(); i = i + 1 {
    let base = bases[i]
    let actual = calc_hp_full(base, 31, 0)
    let recovered = reverse_base_from_stat(actual, 31, 0, true, 1, 1)
    inspect(recovered == base, content="true")
  }
  // Test other stat round-trip (nature up)
  for i = 0; i < bases.length(); i = i + 1 {
    let base = bases[i]
    let actual = calc_other_full(base, 31, 252, 11, 10)
    let recovered = reverse_base_from_stat(actual, 31, 252, false, 11, 10)
    inspect(recovered == base, content="true")
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
