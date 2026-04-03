/// Convert user-facing version string to the Mixed Case format used by waza tables.
pub fn to_waza_version(version : String) -> String {
  match version {
    "scarlet_violet" => "Scarlet_Violet"
    "legendsza" => "LegendsZA"
    "sword_shield" => "sword_shield"
    _ => version
  }
}

/// Normalize globalNo to zero-padded 4-digit format (e.g. "445" -> "0445").
pub fn normalize_global_no(input : String) -> String {
  let len = input.length()
  if len >= 4 {
    return input
  }
  let mut result = ""
  for i = 0; i < 4 - len; i = i + 1 {
    result = result + "0"
  }
  result + input
}
