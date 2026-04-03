/// Get weather damage modifier (4096 base) for move type.
pub fn get_weather_damage_mod(weather : String, move_type : String) -> Int {
  match (weather, move_type) {
    ("はれ", "ほのお") => 6144 // 1.5x
    ("はれ", "みず") => 2048 // 0.5x
    ("あめ", "みず") => 6144
    ("あめ", "ほのお") => 2048
    _ => 0
  }
}

/// Apply weather stat modifier to defense stat.
pub fn apply_weather_def_mod(
  weather : String,
  def_types : (String, String),
  is_physical : Bool,
  def_stat : Int
) -> Int {
  let (dt1, dt2) = def_types
  let has_rock = dt1 == "いわ" || dt2 == "いわ"
  let has_ice = dt1 == "こおり" || dt2 == "こおり"
  match weather {
    "すなあらし" =>
      if has_rock && not(is_physical) {
        // Rock SpD boost 1.5x
        def_stat * 3 / 2
      } else {
        def_stat
      }
    "ゆき" =>
      if has_ice && is_physical {
        // Ice Def boost 1.5x
        def_stat * 3 / 2
      } else {
        def_stat
      }
    _ => def_stat
  }
}

/// Get field damage modifier (4096 base) for move type.
pub fn get_field_damage_mod(field : String, move_type : String) -> Int {
  match (field, move_type) {
    ("エレキ", "でんき") => 5325 // 1.3x
    ("グラス", "くさ") => 5325
    ("サイコ", "エスパー") => 5325
    ("ミスト", "ドラゴン") => 2048 // 0.5x
    _ => 0
  }
}
