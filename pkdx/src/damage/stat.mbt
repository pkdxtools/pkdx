///|
/// 4096-base rounding (五捨五超入).
pub fn round5(value : Int, mult_4096 : Int) -> Int {
  (value * mult_4096 + 2047) / 4096
}

///|
/// Full HP stat calculation at Lv50.
/// floor((base*2 + iv + floor(ev/4)) * 50 / 100) + 60
pub fn calc_hp_full(base : Int, iv : Int, ev : Int) -> Int {
  (base * 2 + iv + ev / 4) * 50 / 100 + 60
}

///|
/// Full non-HP stat calculation at Lv50.
/// floor((floor((base*2 + iv + floor(ev/4)) * 50 / 100) + 5) * nature_num / nature_den)
pub fn calc_other_full(
  base : Int,
  iv : Int,
  ev : Int,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  let raw = (base * 2 + iv + ev / 4) * 50 / 100 + 5
  raw * nature_num / nature_den
}

///|
/// Lv50 stat calculation (IV31, EV252 shortcut).
/// Delegates to calc_hp_full / calc_other_full.
pub fn calc_stat(
  base : Int,
  is_hp? : Bool = false,
  nature_boost? : Bool = true,
  custom? : Int = 0,
) -> Int {
  if custom > 0 {
    return custom
  }
  if is_hp {
    return calc_hp_full(base, 31, 252)
  }
  let (num, den) = if nature_boost { (11, 10) } else { (1, 1) }
  calc_other_full(base, 31, 252, num, den)
}

///|
/// Calculate all 6 stats for a Pokemon at Lv50.
/// ivs/evs: FixedArray of 6 values in HP,Atk,Def,SpA,SpD,Spe order.
pub fn calc_all_stats(
  pokemon : @model.Pokemon,
  ivs : FixedArray[Int],
  evs : FixedArray[Int],
  nature : @model.Nature,
) -> FixedArray[Int] {
  let bases : FixedArray[Int] = [
    pokemon.hp, pokemon.atk, pokemon.def_, pokemon.spa, pokemon.spd,
    pokemon.spe,
  ]
  let stat_indices : FixedArray[@model.StatIndex] = [
    HP, Atk, Def, SpA, SpD, Spe,
  ]
  let result : FixedArray[Int] = FixedArray::make(6, 0)
  for i = 0; i < 6; i = i + 1 {
    if i == 0 {
      result[i] = calc_hp_full(bases[i], ivs[i], evs[i])
    } else {
      let (num, den) = @model.nature_mult_int(nature, stat_indices[i])
      result[i] = calc_other_full(bases[i], ivs[i], evs[i], num, den)
    }
  }
  result
}

///|
/// Reverse: given actual stat value, derive the base stat.
/// Uses algebraic inversion + forward verification with ±1 adjustment.
pub fn reverse_base_from_stat(
  actual : Int,
  iv : Int,
  ev : Int,
  is_hp : Bool,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  if is_hp {
    // actual = floor((base*2 + iv + ev/4) * 50 / 100) + 60
    // actual - 60 = floor((base*2 + iv + ev/4) / 2)
    // base = ((actual - 60) * 2 - iv - ev/4) / 2
    let inner = actual - 60
    let base = (inner * 2 - iv - ev / 4) / 2
    // forward verify and adjust
    if calc_hp_full(base, iv, ev) == actual {
      return base
    }
    if calc_hp_full(base + 1, iv, ev) == actual {
      return base + 1
    }
    if base > 0 && calc_hp_full(base - 1, iv, ev) == actual {
      return base - 1
    }
    return base
  }
  // Non-HP: undo nature first
  // actual = floor(raw * nature_num / nature_den)
  // raw = ceil(actual * nature_den / nature_num)
  let raw = if nature_num != nature_den {
    (actual * nature_den + nature_num - 1) / nature_num
  } else {
    actual
  }
  // raw = floor((base*2 + iv + ev/4) * 50 / 100) + 5
  // raw - 5 = floor((base*2 + iv + ev/4) / 2)
  let inner = raw - 5
  let base = (inner * 2 - iv - ev / 4) / 2
  // forward verify and adjust
  if calc_other_full(base, iv, ev, nature_num, nature_den) == actual {
    return base
  }
  if calc_other_full(base + 1, iv, ev, nature_num, nature_den) == actual {
    return base + 1
  }
  if base > 0 &&
    calc_other_full(base - 1, iv, ev, nature_num, nature_den) == actual {
    return base - 1
  }
  base
}

///|
/// Reverse: given Pokemon + 6 actual stats + IV, find nature + EV spread.
/// Returns all valid (Nature, evs[6]) combinations with total EV ≤ 510.
pub fn reverse_spread(
  pokemon : @model.Pokemon,
  actual_stats : FixedArray[Int],
  iv : Int,
) -> Array[(@model.Nature, FixedArray[Int])] {
  let bases : FixedArray[Int] = [
    pokemon.hp, pokemon.atk, pokemon.def_, pokemon.spa, pokemon.spd,
    pokemon.spe,
  ]
  let stat_indices : FixedArray[@model.StatIndex] = [
    HP, Atk, Def, SpA, SpD, Spe,
  ]
  let natures = @model.all_natures()
  let results : Array[(@model.Nature, FixedArray[Int])] = []
  for ni = 0; ni < natures.length(); ni = ni + 1 {
    let nature = natures[ni]
    let evs : FixedArray[Int] = FixedArray::make(6, -1)
    let mut valid = true
    for si = 0; si < 6; si = si + 1 {
      if not(valid) {
        break
      }
      let actual = actual_stats[si]
      let base = bases[si]
      if si == 0 {
        // HP: try EV values 0,4,8,...,252
        let mut found_ev = -1
        for ev_idx = 0; ev_idx <= 63; ev_idx = ev_idx + 1 {
          let ev = ev_idx * 4
          if calc_hp_full(base, iv, ev) == actual {
            found_ev = ev
            break
          }
        }
        if found_ev < 0 {
          valid = false
        } else {
          evs[si] = found_ev
        }
      } else {
        let (num, den) = @model.nature_mult_int(nature, stat_indices[si])
        let mut found_ev = -1
        for ev_idx = 0; ev_idx <= 63; ev_idx = ev_idx + 1 {
          let ev = ev_idx * 4
          if calc_other_full(base, iv, ev, num, den) == actual {
            found_ev = ev
            break
          }
        }
        if found_ev < 0 {
          valid = false
        } else {
          evs[si] = found_ev
        }
      }
    }
    if valid {
      let mut total = 0
      for si = 0; si < 6; si = si + 1 {
        total = total + evs[si]
      }
      if total <= 510 {
        results.push((nature, evs))
      }
    }
  }
  // Sort by total EV ascending
  results.sort_by(fn(a, b) {
    let (_, evs_a) = a
    let (_, evs_b) = b
    let mut sum_a = 0
    let mut sum_b = 0
    for i = 0; i < 6; i = i + 1 {
      sum_a = sum_a + evs_a[i]
      sum_b = sum_b + evs_b[i]
    }
    sum_a - sum_b
  })
  results
}
