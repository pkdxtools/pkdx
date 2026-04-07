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
/// A Double result is used because candidate ranking needs fractional resolution.
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
/// Greedy gradient optimizer (lacolaco-style).
/// For each step, the stat with the highest contribution-per-unit-EV is incremented
/// by the minimum EV needed to raise its actual value by 1 (or to the next snap-valid HP).
pub fn optimize_hbd(
  pokemon : @model.Pokemon,
  fixed_evs : FixedArray[Int],
  ivs : FixedArray[Int],
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : HbdWeights,
) -> HbdResult {
  let h_fixed = fixed_evs[0] >= 0
  let b_fixed = fixed_evs[2] >= 0
  let d_fixed = fixed_evs[4] >= 0
  let (nb_num, nb_den) = @model.nature_mult_int(nature, Def)
  let (nd_num, nd_den) = @model.nature_mult_int(nature, SpD)
  let iv_h = ivs[0]
  let iv_b = ivs[2]
  let iv_d = ivs[4]
  let evs : FixedArray[Int] = FixedArray::make(6, 0)
  for i = 0; i < 6; i = i + 1 {
    evs[i] = if fixed_evs[i] >= 0 { fixed_evs[i] } else { 0 }
  }
  // Snap pre-adjustment: if HP must satisfy a snap condition and the initial HP doesn't,
  // advance evs[0] to the minimum EV that places HP on a valid snap value. This guarantees
  // the greedy loop starts from a feasible state.
  if not(h_fixed) && snap != @model.HpSnap::NoSnap {
    let h0 = calc_hp_full(pokemon.hp, iv_h, evs[0])
    if not(@model.matches_snap(h0, snap)) {
      let target = next_snap_hp(h0 - 1, snap)
      let needed = ev_for_hp(pokemon.hp, iv_h, target)
      if needed <= 252 {
        evs[0] = needed
      }
    }
  }
  let p = weights.phys
  let s = weights.spec
  // Greedy loop — at most a few hundred iterations.
  for step = 0; step < 600; step = step + 1 {
    let mut used = 0
    for i = 0; i < 6; i = i + 1 {
      used = used + evs[i]
    }
    let free_ev = 508 - used
    if free_ev <= 0 {
      break
    }
    let cur_h = calc_hp_full(pokemon.hp, iv_h, evs[0])
    let cur_b = calc_other_full(pokemon.def_, iv_b, evs[2], nb_num, nb_den)
    let cur_d = calc_other_full(pokemon.spd, iv_d, evs[4], nd_num, nd_den)
    let denom = (s * cur_b + p * cur_d).to_double()
    let denom2 = denom * denom
    // Raw partial derivatives (continuous objective).
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
    // Target next actual value. For H under snap, jump to the next snap-valid HP.
    let target_h = if snap != @model.HpSnap::NoSnap {
      next_snap_hp(cur_h, snap)
    } else {
      cur_h + 1
    }
    let next_h_ev = ev_for_hp(pokemon.hp, iv_h, target_h)
    let next_b_ev = ev_for_non_hp(pokemon.def_, iv_b, cur_b + 1, nb_num, nb_den)
    let next_d_ev = ev_for_non_hp(pokemon.spd, iv_d, cur_d + 1, nd_num, nd_den)
    // Admissibility: non-fixed, strictly increases, within free budget, ≤252.
    let valid_h = not(h_fixed) &&
      next_h_ev > evs[0] &&
      next_h_ev <= 252 &&
      next_h_ev - evs[0] <= free_ev
    let valid_b = not(b_fixed) &&
      next_b_ev > evs[2] &&
      next_b_ev <= 252 &&
      next_b_ev - evs[2] <= free_ev
    let valid_d = not(d_fixed) &&
      next_d_ev > evs[4] &&
      next_d_ev <= 252 &&
      next_d_ev - evs[4] <= free_ev
    // Unit-normalized contribution: raw_dx / (EV cost).
    let unit_h = if valid_h {
      raw_dh / (next_h_ev - evs[0]).to_double()
    } else {
      0.0
    }
    let unit_b = if valid_b {
      raw_db / (next_b_ev - evs[2]).to_double()
    } else {
      0.0
    }
    let unit_d = if valid_d {
      raw_dd / (next_d_ev - evs[4]).to_double()
    } else {
      0.0
    }
    if unit_h <= 0.0 && unit_b <= 0.0 && unit_d <= 0.0 {
      break
    }
    // Pick the largest contribution; ties favor H > B > D for determinism.
    if unit_h >= unit_b && unit_h >= unit_d && unit_h > 0.0 {
      evs[0] = next_h_ev
    } else if unit_b >= unit_d && unit_b > 0.0 {
      evs[2] = next_b_ev
    } else {
      evs[4] = next_d_ev
    }
  }
  let final_h = calc_hp_full(pokemon.hp, iv_h, evs[0])
  let final_b = calc_other_full(pokemon.def_, iv_b, evs[2], nb_num, nb_den)
  let final_d = calc_other_full(pokemon.spd, iv_d, evs[4], nd_num, nd_den)
  let warning = if snap != @model.HpSnap::NoSnap &&
    not(@model.matches_snap(final_h, snap)) {
    Some("hp-snap unreachable; constraint ignored")
  } else {
    None
  }
  let cand = {
    evs,
    hp: final_h,
    def_: final_b,
    spd: final_d,
    score: score_hbd(final_h, final_b, final_d, weights),
  }
  { candidates: [cand], warning }
}

///|
/// Brute-force enumeration for top-N ranked candidates.
/// Explores all (evH, evB, evD) multiples of 4 satisfying the 508 budget and snap constraint,
/// then sorts by score with deterministic tiebreakers.
pub fn optimize_hbd_topn(
  pokemon : @model.Pokemon,
  fixed_evs : FixedArray[Int],
  ivs : FixedArray[Int],
  nature : @model.Nature,
  snap : @model.HpSnap,
  weights : HbdWeights,
  n : Int,
) -> HbdResult {
  let (nb_num, nb_den) = @model.nature_mult_int(nature, Def)
  let (nd_num, nd_den) = @model.nature_mult_int(nature, SpD)
  let iv_h = ivs[0]
  let iv_b = ivs[2]
  let iv_d = ivs[4]
  let h_fixed = fixed_evs[0] >= 0
  let b_fixed = fixed_evs[2] >= 0
  let d_fixed = fixed_evs[4] >= 0
  let fixed_a = if fixed_evs[1] >= 0 { fixed_evs[1] } else { 0 }
  let fixed_c = if fixed_evs[3] >= 0 { fixed_evs[3] } else { 0 }
  let fixed_s = if fixed_evs[5] >= 0 { fixed_evs[5] } else { 0 }
  let fixed_non_hbd = fixed_a + fixed_c + fixed_s
  let mut candidates : Array[HbdCandidate] = []
  let h_start = if h_fixed { fixed_evs[0] } else { 0 }
  let h_end = if h_fixed { fixed_evs[0] } else { 252 }
  let b_start = if b_fixed { fixed_evs[2] } else { 0 }
  let b_end = if b_fixed { fixed_evs[2] } else { 252 }
  let d_start = if d_fixed { fixed_evs[4] } else { 0 }
  let d_end = if d_fixed { fixed_evs[4] } else { 252 }
  let mut eh = h_start
  while eh <= h_end {
    let mut eb = b_start
    while eb <= b_end {
      let mut ed = d_start
      while ed <= d_end {
        if eh + eb + ed + fixed_non_hbd <= 508 {
          let h_val = calc_hp_full(pokemon.hp, iv_h, eh)
          if @model.matches_snap(h_val, snap) {
            let b_val = calc_other_full(pokemon.def_, iv_b, eb, nb_num, nb_den)
            let d_val = calc_other_full(pokemon.spd, iv_d, ed, nd_num, nd_den)
            let sc = score_hbd(h_val, b_val, d_val, weights)
            let ev_row : FixedArray[Int] = FixedArray::make(6, 0)
            ev_row[0] = eh
            ev_row[1] = fixed_a
            ev_row[2] = eb
            ev_row[3] = fixed_c
            ev_row[4] = ed
            ev_row[5] = fixed_s
            candidates.push({
              evs: ev_row,
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
        ed = ed + 4
      }
      if b_fixed {
        break
      }
      eb = eb + 4
    }
    if h_fixed {
      break
    }
    eh = eh + 4
  }
  // Fallback: if no candidate (e.g. snap unreachable), retry with NoSnap and mark warning.
  let warning = if candidates.length() == 0 && snap != @model.HpSnap::NoSnap {
    let relaxed = optimize_hbd_topn(
      pokemon, fixed_evs, ivs, nature, @model.HpSnap::NoSnap, weights, n,
    )
    candidates = relaxed.candidates
    Some("hp-snap unreachable; constraint ignored")
  } else {
    None
  }
  candidates.sort_by(fn(a, b) {
    // 1) score desc
    if a.score > b.score {
      -1
    } else if a.score < b.score {
      1
    } else {
      let sum_a = a.evs[0] + a.evs[2] + a.evs[4]
      let sum_b = b.evs[0] + b.evs[2] + b.evs[4]
      // 2) lower EV usage first
      if sum_a != sum_b {
        sum_a - sum_b
      } else {
        // 3) less skewed first (lower max)
        let max_a = {
          let m1 = if a.evs[0] > a.evs[2] { a.evs[0] } else { a.evs[2] }
          if m1 > a.evs[4] { m1 } else { a.evs[4] }
        }
        let max_b = {
          let m1 = if b.evs[0] > b.evs[2] { b.evs[0] } else { b.evs[2] }
          if m1 > b.evs[4] { m1 } else { b.evs[4] }
        }
        if max_a != max_b {
          max_a - max_b
        } else if a.evs[0] != b.evs[0] {
          // 4) lex: EV_H desc
          b.evs[0] - a.evs[0]
        } else if a.evs[2] != b.evs[2] {
          b.evs[2] - a.evs[2]
        } else {
          b.evs[4] - a.evs[4]
        }
      }
    }
  })
  let take = if n < candidates.length() { n } else { candidates.length() }
  let out : Array[HbdCandidate] = []
  for i = 0; i < take; i = i + 1 {
    out.push(candidates[i])
  }
  { candidates: out, warning }
}
