///|
/// Get weather damage modifier (4096 base) for move type.
pub fn get_weather_damage_mod(
  weather : @model.Weather,
  move_type : String,
) -> Int {
  match (weather, move_type) {
    (Sun, "ほのお") => 6144 // 1.5x
    (Sun, "みず") => 2048 // 0.5x
    (Rain, "みず") => 6144
    (Rain, "ほのお") => 2048
    _ => 0
  }
}

///|
/// Apply weather stat modifier to defense stat.
pub fn apply_weather_def_mod(
  weather : @model.Weather,
  def_types : (String, String),
  is_physical : Bool,
  def_stat : Int,
) -> Int {
  let (dt1, dt2) = def_types
  let has_rock = dt1 == "いわ" || dt2 == "いわ"
  let has_ice = dt1 == "こおり" || dt2 == "こおり"
  match weather {
    Sand =>
      if has_rock && !is_physical {
        // Rock SpD boost 1.5x
        def_stat * 3 / 2
      } else {
        def_stat
      }
    Snow =>
      if has_ice && is_physical {
        // Ice Def boost 1.5x
        def_stat * 3 / 2
      } else {
        def_stat
      }
    _ => def_stat
  }
}

// Field damage modifier moved to `field.mbt` (Stage F-1) with Gen 9 spec —
// grounded check + Grassy じしん/マグニチュード/じならし 0.5x debuff arm.
