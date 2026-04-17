///|
/// 4096-base rounding (五捨五超入).
pub fn round5(value : Int, mult_4096 : Int) -> Int {
  (value * mult_4096 + 2047) / 4096
}

///|
/// stage >= 0: stat * (2 + stage) / 2
/// stage <  0: stat * 2 / (2 - stage)
pub fn apply_rank(stat : Int, stage : Int) -> Int {
  let s = if stage > 6 { 6 } else if stage < -6 { -6 } else { stage }
  if s >= 0 {
    stat * (2 + s) / 2
  } else {
    stat * 2 / (2 - s)
  }
}

// ──────────────────────────────────────────────
// Raw stat formulas (low-level; used by StatModel below)
// ──────────────────────────────────────────────

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
/// Champions HP: base + sp + 75
pub fn calc_hp_champions(base : Int, sp : Int) -> Int {
  base + sp + 75
}

///|
/// Champions non-HP: floor((base + sp + 20) * nature_num / nature_den)
pub fn calc_other_champions(
  base : Int,
  sp : Int,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  (base + sp + 20) * nature_num / nature_den
}

///|
/// Minimum EV (0..=252, multiple of 4) required to reach a given HP actual value,
/// given base and IV. Returns 256 sentinel if unreachable.
pub fn ev_for_hp(base : Int, iv : Int, target : Int) -> Int {
  let needed_q = 2 * (target - 60) - base * 2 - iv
  let q = if needed_q < 0 { 0 } else { needed_q }
  let ev = q * 4
  if ev > 252 {
    return 256
  }
  if calc_hp_full(base, iv, ev) >= target {
    return ev
  }
  let ev2 = ev + 4
  if ev2 > 252 {
    return 256
  }
  ev2
}

///|
/// Minimum EV (0..=252, multiple of 4) required to reach a given non-HP actual value.
/// Returns 256 sentinel if unreachable.
pub fn ev_for_non_hp(
  base : Int,
  iv : Int,
  target : Int,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  let raw_min = if nature_num == nature_den {
    target
  } else {
    (target * nature_den + nature_num - 1) / nature_num
  }
  let inner_floor_min = raw_min - 5
  let needed = 2 * inner_floor_min - base * 2 - iv
  let q = if needed < 0 { 0 } else { needed }
  let ev = q * 4
  if ev > 252 {
    return 256
  }
  if calc_other_full(base, iv, ev, nature_num, nature_den) >= target {
    return ev
  }
  let ev2 = ev + 4
  if ev2 > 252 {
    return 256
  }
  if calc_other_full(base, iv, ev2, nature_num, nature_den) >= target {
    return ev2
  }
  let ev3 = ev2 + 4
  if ev3 > 252 {
    return 256
  }
  ev3
}

///|
/// Champions: minimum SP (0..=32) to reach target HP. Returns 33 if unreachable.
pub fn sp_for_hp_champions(base : Int, target : Int) -> Int {
  let sp = target - base - 75
  if sp < 0 {
    return 0
  }
  if sp > 32 {
    return 33
  }
  sp
}

///|
/// Champions: minimum SP (0..=32) to reach target non-HP stat. Returns 33 if unreachable.
pub fn sp_for_non_hp_champions(
  base : Int,
  target : Int,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  let raw_min = if nature_num == nature_den {
    target
  } else {
    (target * nature_den + nature_num - 1) / nature_num
  }
  let sp = raw_min - base - 20
  if sp < 0 {
    return 0
  }
  if sp > 32 {
    return 33
  }
  if calc_other_champions(base, sp, nature_num, nature_den) >= target {
    return sp
  }
  let sp2 = sp + 1
  if sp2 > 32 {
    return 33
  }
  sp2
}

// ──────────────────────────────────────────────
// StatModel: abstraction over EV/IV and SP stat systems
// ──────────────────────────────────────────────

///|
/// Stat system abstraction. `Standard` carries the IV array used by EV-based
/// formulas; `Champions` ignores IVs entirely.
///
/// Budget semantics (exposed via `full_budget` / `hbd_budget`):
/// Standard: total EV ≤ 510, HBD-relevant sum ≤ 508.
/// Champions: total SP ≤ 66 (no separate HBD budget).
pub(all) enum StatModel {
  Standard(ivs~ : FixedArray[Int])
  Champions
}

///|
pub fn StatModel::step(self : StatModel) -> Int {
  match self {
    Standard(_) => 4
    Champions => 1
  }
}

///|
pub fn StatModel::max_per_stat(self : StatModel) -> Int {
  match self {
    Standard(_) => 252
    Champions => 32
  }
}

///|
pub fn StatModel::sentinel(self : StatModel) -> Int {
  match self {
    Standard(_) => 256
    Champions => 33
  }
}

///|
pub fn StatModel::step_cap(self : StatModel) -> Int {
  match self {
    Standard(_) => 600
    Champions => 200
  }
}

///|
/// Budget used by HBD optimizers (sum of HP+B+D+fixed non-HBD must stay ≤).
pub fn StatModel::hbd_budget(self : StatModel) -> Int {
  match self {
    Standard(_) => 508
    Champions => 66
  }
}

///|
/// Budget used by reverse-spread (total of all 6 points must stay ≤).
pub fn StatModel::full_budget(self : StatModel) -> Int {
  match self {
    Standard(_) => 510
    Champions => 66
  }
}

///|
/// Calculate HP actual value from base and point amount.
pub fn StatModel::calc_hp(self : StatModel, base : Int, pt : Int) -> Int {
  match self {
    Standard(ivs~) => calc_hp_full(base, ivs[0], pt)
    Champions => calc_hp_champions(base, pt)
  }
}

///|
/// Calculate non-HP actual value. `stat_idx` selects the IV slot for Standard.
pub fn StatModel::calc_other(
  self : StatModel,
  stat_idx : Int,
  base : Int,
  pt : Int,
  num : Int,
  den : Int,
) -> Int {
  match self {
    Standard(ivs~) => calc_other_full(base, ivs[stat_idx], pt, num, den)
    Champions => calc_other_champions(base, pt, num, den)
  }
}

///|
/// Minimum point amount (EV or SP) required to reach target HP.
/// Returns `sentinel()` if unreachable within the per-stat cap.
pub fn StatModel::point_for_hp(
  self : StatModel,
  base : Int,
  target : Int,
) -> Int {
  match self {
    Standard(ivs~) => ev_for_hp(base, ivs[0], target)
    Champions => sp_for_hp_champions(base, target)
  }
}

///|
/// Minimum point amount required to reach target non-HP stat.
/// Returns `sentinel()` if unreachable within the per-stat cap.
pub fn StatModel::point_for_other(
  self : StatModel,
  stat_idx : Int,
  base : Int,
  target : Int,
  num : Int,
  den : Int,
) -> Int {
  match self {
    Standard(ivs~) => ev_for_non_hp(base, ivs[stat_idx], target, num, den)
    Champions => sp_for_non_hp_champions(base, target, num, den)
  }
}

// ──────────────────────────────────────────────
// Public stat calculation API (thin wrappers over StatModel)
// ──────────────────────────────────────────────

///|
/// Lv50 stat shortcut (IV31, EV252).
/// `nature_num` / `nature_den` で性格補正を指定 (default +10% = 11/10)。
pub fn calc_stat(
  base : Int,
  is_hp? : Bool = false,
  nature_num? : Int = 11,
  nature_den? : Int = 10,
  custom? : Int = 0,
) -> Int {
  if custom > 0 {
    return custom
  }
  if is_hp {
    return calc_hp_full(base, 31, 252)
  }
  calc_other_full(base, 31, 252, nature_num, nature_den)
}

///|
/// Champions stat shortcut (SP=32 default).
/// `nature_num` / `nature_den` で性格補正を指定 (default +10% = 11/10)。
pub fn calc_stat_champions(
  base : Int,
  is_hp? : Bool = false,
  nature_num? : Int = 11,
  nature_den? : Int = 10,
  custom? : Int = 0,
) -> Int {
  if custom > 0 {
    return custom
  }
  if is_hp {
    return calc_hp_champions(base, 32)
  }
  calc_other_champions(base, 32, nature_num, nature_den)
}

///|
/// 防御側デフォルト (Lv50, IV31, EV0)。
/// Showdown など主要ダメ計と同じ「相手は最低投資」前提。
/// `nature_num` / `nature_den` で性格補正を指定 (default 無補正 = 1/1)。
pub fn calc_def_stat(
  base : Int,
  is_hp? : Bool = false,
  nature_num? : Int = 1,
  nature_den? : Int = 1,
  custom? : Int = 0,
) -> Int {
  if custom > 0 {
    return custom
  }
  if is_hp {
    return calc_hp_full(base, 31, 0)
  }
  calc_other_full(base, 31, 0, nature_num, nature_den)
}

///|
/// Champions 防御側デフォルト (SP=0)。
/// `nature_num` / `nature_den` で性格補正を指定 (default 無補正 = 1/1)。
pub fn calc_def_stat_champions(
  base : Int,
  is_hp? : Bool = false,
  nature_num? : Int = 1,
  nature_den? : Int = 1,
  custom? : Int = 0,
) -> Int {
  if custom > 0 {
    return custom
  }
  if is_hp {
    return calc_hp_champions(base, 0)
  }
  calc_other_champions(base, 0, nature_num, nature_den)
}

///|
/// Calculate all 6 stats via the given StatModel.
/// `points` is the 6-length EV (Standard) or SP (Champions) array.
pub fn calc_all_stats_with_model(
  model : StatModel,
  pokemon : @model.Pokemon,
  points : FixedArray[Int],
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
      result[i] = model.calc_hp(bases[i], points[i])
    } else {
      let (num, den) = @model.nature_mult_int(nature, stat_indices[i])
      result[i] = model.calc_other(i, bases[i], points[i], num, den)
    }
  }
  result
}

///|
/// Calculate all 6 stats for a Pokemon at Lv50 (Standard EV/IV system).
pub fn calc_all_stats(
  pokemon : @model.Pokemon,
  ivs : FixedArray[Int],
  evs : FixedArray[Int],
  nature : @model.Nature,
) -> FixedArray[Int] {
  calc_all_stats_with_model(Standard(ivs~), pokemon, evs, nature)
}

///|
/// Calculate all 6 stats for Champions (SP system).
pub fn calc_all_stats_champions(
  pokemon : @model.Pokemon,
  sps : FixedArray[Int],
  nature : @model.Nature,
) -> FixedArray[Int] {
  calc_all_stats_with_model(Champions, pokemon, sps, nature)
}

// ──────────────────────────────────────────────
// Reverse derivation
// ──────────────────────────────────────────────

///|
/// Reverse: given actual stat value, derive the base stat (EV/IV system).
pub fn reverse_base_from_stat(
  actual : Int,
  iv : Int,
  ev : Int,
  is_hp : Bool,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  if is_hp {
    let inner = actual - 60
    let base = (inner * 2 - iv - ev / 4) / 2
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
  let raw = if nature_num != nature_den {
    (actual * nature_den + nature_num - 1) / nature_num
  } else {
    actual
  }
  let inner = raw - 5
  let base = (inner * 2 - iv - ev / 4) / 2
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
/// Champions: reverse derive base stat from actual value + SP.
pub fn reverse_base_from_stat_champions(
  actual : Int,
  sp : Int,
  is_hp : Bool,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  if is_hp {
    return actual - sp - 75
  }
  let raw = if nature_num != nature_den {
    (actual * nature_den + nature_num - 1) / nature_num
  } else {
    actual
  }
  let base = raw - sp - 20
  if calc_other_champions(base, sp, nature_num, nature_den) == actual {
    return base
  }
  if calc_other_champions(base + 1, sp, nature_num, nature_den) == actual {
    return base + 1
  }
  if base > 0 &&
    calc_other_champions(base - 1, sp, nature_num, nature_den) == actual {
    return base - 1
  }
  base
}

///|
/// Reverse: given Pokemon + 6 actual stats, find all valid (nature, point spread)
/// combinations whose total points stay within `full_budget()`.
pub fn reverse_spread_with_model(
  model : StatModel,
  pokemon : @model.Pokemon,
  actual_stats : FixedArray[Int],
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
  let step = model.step()
  let max_per = model.max_per_stat()
  let budget = model.full_budget()
  for ni = 0; ni < natures.length(); ni = ni + 1 {
    let nature = natures[ni]
    let points : FixedArray[Int] = FixedArray::make(6, -1)
    let mut valid = true
    for si = 0; si < 6; si = si + 1 {
      if not(valid) {
        break
      }
      let actual = actual_stats[si]
      let base = bases[si]
      let mut found = -1
      let mut pt = 0
      while pt <= max_per {
        let calc_actual = if si == 0 {
          model.calc_hp(base, pt)
        } else {
          let (num, den) = @model.nature_mult_int(nature, stat_indices[si])
          model.calc_other(si, base, pt, num, den)
        }
        if calc_actual == actual {
          found = pt
          break
        }
        pt = pt + step
      }
      if found < 0 {
        valid = false
      } else {
        points[si] = found
      }
    }
    if valid {
      let mut total = 0
      for si = 0; si < 6; si = si + 1 {
        total = total + points[si]
      }
      if total <= budget {
        results.push((nature, points))
      }
    }
  }
  results.sort_by(fn(a, b) {
    let (_, pa) = a
    let (_, pb) = b
    let mut sa = 0
    let mut sb = 0
    for i = 0; i < 6; i = i + 1 {
      sa = sa + pa[i]
      sb = sb + pb[i]
    }
    sa - sb
  })
  results
}

///|
/// Reverse: given Pokemon + 6 actual stats + IV, find nature + EV spread (Standard).
pub fn reverse_spread(
  pokemon : @model.Pokemon,
  actual_stats : FixedArray[Int],
  iv : Int,
) -> Array[(@model.Nature, FixedArray[Int])] {
  let ivs : FixedArray[Int] = FixedArray::make(6, iv)
  reverse_spread_with_model(Standard(ivs~), pokemon, actual_stats)
}

///|
/// Reverse: given Pokemon + 6 actual stats, find nature + SP spread (Champions).
pub fn reverse_spread_champions(
  pokemon : @model.Pokemon,
  actual_stats : FixedArray[Int],
) -> Array[(@model.Nature, FixedArray[Int])] {
  reverse_spread_with_model(Champions, pokemon, actual_stats)
}
