///|
/// Multi-hit resolution strategy for `pkdx damage`.
///
/// - `Auto`: look up the move in the hardcoded multi-hit table. Fixed N-hit
///   moves use N; 2-5 random moves use the center value 3 (skill-link presence
///   is decided by attacker ability at call site).
/// - `Fixed(n)`: force exactly n hits (`--multi-hit 5` for worst-case analysis).
/// - `Expected`: payoff-layer approximation only. `pkdx damage` aborts on this
///   variant; the payoff module uses it internally to scale single-hit damage
///   by `19/6` when propagating through the switching game.
pub(all) enum MultiHit {
  Auto
  Fixed(Int)
  Expected
} derive(Show, Eq)

///|
/// CLI parser. Accepts "auto" / "expected" / "<int>". Integer out of 1..=5 is
/// clamped; unparseable strings fall back to Auto.
pub fn multi_hit_from_str(s : String) -> MultiHit {
  match s {
    "" | "auto" => Auto
    "expected" => Expected
    _ => {
      // Minimal inline integer parse so model stays free of strconv dependency.
      let len = s.length()
      if len == 0 {
        Auto
      } else {
        let mut ok = true
        let mut n = 0
        for i = 0; i < len; i = i + 1 {
          let c = s.unsafe_get(i).to_int()
          if c < 0x30 || c > 0x39 {
            ok = false
            break
          }
          n = n * 10 + (c - 0x30)
        }
        if not(ok) {
          Auto
        } else if n < 1 {
          Fixed(1)
        } else if n > 5 {
          Fixed(5)
        } else {
          Fixed(n)
        }
      }
    }
  }
}
