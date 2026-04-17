///|
/// Weights for the asymmetric bulk objective `f = HBD / (s·B + p·D)`.
/// `phys` is the assumed physical damage coefficient (p),
/// `spec` the assumed special damage coefficient (s).
pub(all) struct HbdWeights {
  phys : Int
  spec : Int
} derive(Show, Eq)

///|
/// A single optimization candidate.
/// `evs` is a 6-length array in HP,Atk,Def,SpA,SpD,Spe order.
pub(all) struct HbdCandidate {
  evs : FixedArray[Int]
  hp : Int
  def_ : Int
  spd : Int
  score : Double
} derive(Show)

///|
/// Result of `optimize_hbd` / `optimize_hbd_topn`.
/// `warning` is set when a snap constraint had to be relaxed as fallback.
pub(all) struct HbdResult {
  candidates : Array[HbdCandidate]
  warning : String?
} derive(Show)

///|
/// Bulk index objective: f = H · B · D / (s·B + p·D).
pub fn score_hbd(
  h : Int,
  b : Int,
  d : Int,
  weights : HbdWeights,
) -> Double {
  let denom = (weights.spec * b + weights.phys * d).to_double()
  if denom <= 0.0 {
    return 0.0
  }
  (h * b * d).to_double() / denom
}

///|
/// Smallest HP value strictly greater than `current_hp` satisfying the snap rule.
/// Capped at `current_hp + 32` to guarantee termination; returns the cap if no match.
fn next_snap_hp(current_hp : Int, snap : @model.HpSnap) -> Int {
  let mut next = current_hp + 1
  let limit = current_hp + 33
  while next < limit {
    if @model.matches_snap(next, snap) {
      return next
    }
    next = next + 1
  }
  limit
}

///|
/// Deterministic comparator for HBD candidates:
/// 1) score desc, 2) lower EV usage first, 3) less skewed first (lower max),
/// 4) lex: EV_H desc, EV_B desc, EV_D desc.
fn compare_hbd_candidates(a : HbdCandidate, b : HbdCandidate) -> Int {
  if a.score > b.score {
    return -1
  }
  if a.score < b.score {
    return 1
  }
  let sum_a = a.evs[0] + a.evs[2] + a.evs[4]
  let sum_b = b.evs[0] + b.evs[2] + b.evs[4]
  if sum_a != sum_b {
    return sum_a - sum_b
  }
  let max_a = {
    let m1 = if a.evs[0] > a.evs[2] { a.evs[0] } else { a.evs[2] }
    if m1 > a.evs[4] { m1 } else { a.evs[4] }
  }
  let max_b = {
    let m1 = if b.evs[0] > b.evs[2] { b.evs[0] } else { b.evs[2] }
    if m1 > b.evs[4] { m1 } else { b.evs[4] }
  }
  if max_a != max_b {
    return max_a - max_b
  }
  if a.evs[0] != b.evs[0] {
    return b.evs[0] - a.evs[0]
  }
  if a.evs[2] != b.evs[2] {
    return b.evs[2] - a.evs[2]
  }
  b.evs[4] - a.evs[4]
}

// ──────────────────────────────────────────────
// Greedy HBD optimization (StatModel-parameterized)
// ──────────────────────────────────────────────

///|
/// Greedy gradient optimizer (lacolaco-style).
/// For each step, the H/B/D slot with the highest contribution-per-point-cost
/// is incremented by the minimum points needed to raise its actual value by 1
/// (or to the next snap-valid HP).
pub fn optimize_hbd_impl(
  model : StatModel,
  pokemon : @model.Pokemon,
  fixed_points : FixedArray[Int],
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : HbdWeights,
) -> HbdResult {
  let h_fixed = fixed_points[0] >= 0
  let b_fixed = fixed_points[2] >= 0
  let d_fixed = fixed_points[4] >= 0
  let (nb_num, nb_den) = @model.nature_mult_int(nature, Def)
  let (nd_num, nd_den) = @model.nature_mult_int(nature, SpD)
  let max_per = model.max_per_stat()
  let budget = model.hbd_budget()
  let step_cap = model.step_cap()
  let points : FixedArray[Int] = FixedArray::make(6, 0)
  for i = 0; i < 6; i = i + 1 {
    points[i] = if fixed_points[i] >= 0 { fixed_points[i] } else { 0 }
  }
  // Snap pre-adjustment — guarantee greedy loop starts from a feasible state.
  if not(h_fixed) && snap != @model.HpSnap::NoSnap {
    let h0 = model.calc_hp(pokemon.hp, points[0])
    if not(@model.matches_snap(h0, snap)) {
      let target = next_snap_hp(h0 - 1, snap)
      let needed = model.point_for_hp(pokemon.hp, target)
      let mut fixed_used = 0
      for i = 0; i < 6; i = i + 1 {
        fixed_used = fixed_used + points[i]
      }
      let remaining = budget - fixed_used
      if needed <= max_per && needed - points[0] <= remaining {
        points[0] = needed
      }
    }
  }
  let p = weights.phys
  let s = weights.spec
  for step_i = 0; step_i < step_cap; step_i = step_i + 1 {
    ignore(step_i)
    let mut used = 0
    for i = 0; i < 6; i = i + 1 {
      used = used + points[i]
    }
    let free = budget - used
    if free <= 0 {
      break
    }
    let cur_h = model.calc_hp(pokemon.hp, points[0])
    let cur_b = model.calc_other(2, pokemon.def_, points[2], nb_num, nb_den)
    let cur_d = model.calc_other(4, pokemon.spd, points[4], nd_num, nd_den)
    let denom = (s * cur_b + p * cur_d).to_double()
    let denom2 = denom * denom
    let raw_dh = if denom > 0.0 {
      (cur_b * cur_d).to_double() / denom
    } else {
      0.0
    }
    let raw_db = if denom2 > 0.0 {
      (cur_h * p * cur_d * cur_d).to_double() / denom2
    } else {
      0.0
    }
    let raw_dd = if denom2 > 0.0 {
      (cur_h * s * cur_b * cur_b).to_double() / denom2
    } else {
      0.0
    }
    let target_h = if snap != @model.HpSnap::NoSnap {
      next_snap_hp(cur_h, snap)
    } else {
      cur_h + 1
    }
    let next_h_pt = model.point_for_hp(pokemon.hp, target_h)
    let next_b_pt = model.point_for_other(
      2, pokemon.def_, cur_b + 1, nb_num, nb_den,
    )
    let next_d_pt = model.point_for_other(
      4, pokemon.spd, cur_d + 1, nd_num, nd_den,
    )
    let valid_h = not(h_fixed) &&
      next_h_pt > points[0] &&
      next_h_pt <= max_per &&
      next_h_pt - points[0] <= free
    let valid_b = not(b_fixed) &&
      next_b_pt > points[2] &&
      next_b_pt <= max_per &&
      next_b_pt - points[2] <= free
    let valid_d = not(d_fixed) &&
      next_d_pt > points[4] &&
      next_d_pt <= max_per &&
      next_d_pt - points[4] <= free
    let unit_h = if valid_h {
      raw_dh / (next_h_pt - points[0]).to_double()
    } else {
      0.0
    }
    let unit_b = if valid_b {
      raw_db / (next_b_pt - points[2]).to_double()
    } else {
      0.0
    }
    let unit_d = if valid_d {
      raw_dd / (next_d_pt - points[4]).to_double()
    } else {
      0.0
    }
    if unit_h <= 0.0 && unit_b <= 0.0 && unit_d <= 0.0 {
      break
    }
    // Pick the largest contribution; ties favor H > B > D for determinism.
    if unit_h >= unit_b && unit_h >= unit_d && unit_h > 0.0 {
      points[0] = next_h_pt
    } else if unit_b >= unit_d && unit_b > 0.0 {
      points[2] = next_b_pt
    } else {
      points[4] = next_d_pt
    }
  }
  let final_h = model.calc_hp(pokemon.hp, points[0])
  let final_b = model.calc_other(2, pokemon.def_, points[2], nb_num, nb_den)
  let final_d = model.calc_other(4, pokemon.spd, points[4], nd_num, nd_den)
  let warning = if snap != @model.HpSnap::NoSnap &&
    not(@model.matches_snap(final_h, snap)) {
    Some("hp-snap unreachable; constraint ignored")
  } else {
    None
  }
  let cand = {
    evs: points,
    hp: final_h,
    def_: final_b,
    spd: final_d,
    score: score_hbd(final_h, final_b, final_d, weights),
  }
  { candidates: [cand], warning }
}

///|
/// Brute-force enumeration for top-N ranked candidates.
pub fn optimize_hbd_topn_impl(
  model : StatModel,
  pokemon : @model.Pokemon,
  fixed_points : FixedArray[Int],
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : HbdWeights,
  n : Int,
) -> HbdResult {
  let (nb_num, nb_den) = @model.nature_mult_int(nature, Def)
  let (nd_num, nd_den) = @model.nature_mult_int(nature, SpD)
  let step = model.step()
  let max_per = model.max_per_stat()
  let budget = model.hbd_budget()
  let h_fixed = fixed_points[0] >= 0
  let b_fixed = fixed_points[2] >= 0
  let d_fixed = fixed_points[4] >= 0
  let fixed_a = if fixed_points[1] >= 0 { fixed_points[1] } else { 0 }
  let fixed_c = if fixed_points[3] >= 0 { fixed_points[3] } else { 0 }
  let fixed_s = if fixed_points[5] >= 0 { fixed_points[5] } else { 0 }
  let fixed_non_hbd = fixed_a + fixed_c + fixed_s
  let mut candidates : Array[HbdCandidate] = []
  let h_start = if h_fixed { fixed_points[0] } else { 0 }
  let h_end = if h_fixed { fixed_points[0] } else { max_per }
  let b_start = if b_fixed { fixed_points[2] } else { 0 }
  let b_end = if b_fixed { fixed_points[2] } else { max_per }
  let d_start = if d_fixed { fixed_points[4] } else { 0 }
  let d_end = if d_fixed { fixed_points[4] } else { max_per }
  let mut eh = h_start
  while eh <= h_end {
    let mut eb = b_start
    while eb <= b_end {
      let mut ed = d_start
      while ed <= d_end {
        if eh + eb + ed + fixed_non_hbd <= budget {
          let h_val = model.calc_hp(pokemon.hp, eh)
          if @model.matches_snap(h_val, snap) {
            let b_val = model.calc_other(2, pokemon.def_, eb, nb_num, nb_den)
            let d_val = model.calc_other(4, pokemon.spd, ed, nd_num, nd_den)
            let sc = score_hbd(h_val, b_val, d_val, weights)
            let row : FixedArray[Int] = FixedArray::make(6, 0)
            row[0] = eh
            row[1] = fixed_a
            row[2] = eb
            row[3] = fixed_c
            row[4] = ed
            row[5] = fixed_s
            candidates.push({
              evs: row,
              hp: h_val,
              def_: b_val,
              spd: d_val,
              score: sc,
            })
          }
        }
        if d_fixed {
          break
        }
        ed = ed + step
      }
      if b_fixed {
        break
      }
      eb = eb + step
    }
    if h_fixed {
      break
    }
    eh = eh + step
  }
  // Fallback: if no candidate (e.g. snap unreachable), retry with NoSnap and mark warning.
  let warning = if candidates.length() == 0 && snap != @model.HpSnap::NoSnap {
    let relaxed = optimize_hbd_topn_impl(
      model, pokemon, fixed_points, nature, @model.HpSnap::NoSnap, weights, n,
    )
    candidates = relaxed.candidates
    Some("hp-snap unreachable; constraint ignored")
  } else {
    None
  }
  candidates.sort_by(compare_hbd_candidates)
  let take = if n < candidates.length() { n } else { candidates.length() }
  let out : Array[HbdCandidate] = []
  for i = 0; i < take; i = i + 1 {
    out.push(candidates[i])
  }
  { candidates: out, warning }
}

// ──────────────────────────────────────────────
// Public wrappers
// ──────────────────────────────────────────────

///|
pub fn optimize_hbd(
  pokemon : @model.Pokemon,
  fixed_evs : FixedArray[Int],
  ivs : FixedArray[Int],
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : HbdWeights,
) -> HbdResult {
  optimize_hbd_impl(
    Standard(ivs~), pokemon, fixed_evs, nature, snap, weights,
  )
}

///|
pub fn optimize_hbd_topn(
  pokemon : @model.Pokemon,
  fixed_evs : FixedArray[Int],
  ivs : FixedArray[Int],
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : HbdWeights,
  n : Int,
) -> HbdResult {
  optimize_hbd_topn_impl(
    Standard(ivs~), pokemon, fixed_evs, nature, snap, weights, n,
  )
}

///|
pub fn optimize_hbd_champions(
  pokemon : @model.Pokemon,
  fixed_sps : FixedArray[Int],
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : HbdWeights,
) -> HbdResult {
  optimize_hbd_impl(Champions, pokemon, fixed_sps, nature, snap, weights)
}

///|
pub fn optimize_hbd_topn_champions(
  pokemon : @model.Pokemon,
  fixed_sps : FixedArray[Int],
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : HbdWeights,
  n : Int,
) -> HbdResult {
  optimize_hbd_topn_impl(Champions, pokemon, fixed_sps, nature, snap, weights, n)
}
