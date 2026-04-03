/// 4096-base rounding (五捨五超入).
pub fn round5(value : Int, mult_4096 : Int) -> Int {
  (value * mult_4096 + 2047) / 4096
}

/// Lv50 stat calculation.
/// IV31, 252EV, nature boost by default.
pub fn calc_stat(
  base : Int,
  is_hp~ : Bool = false,
  nature_boost~ : Bool = true,
  custom~ : Int = 0
) -> Int {
  if custom > 0 {
    return custom
  }
  if is_hp {
    return base + 107
  }
  let stat = base + 52
  if nature_boost {
    stat * 11 / 10
  } else {
    stat
  }
}
