/// Battle weather conditions.
pub enum Weather {
  None
  Sun
  Rain
  Sand
  Snow
} derive(Show, Eq)

/// Convert Japanese weather name to Weather enum.
pub fn weather_from_jp(name : String) -> Weather {
  match name {
    "はれ" => Sun
    "あめ" => Rain
    "すなあらし" => Sand
    "ゆき" => Snow
    _ => None
  }
}

/// Check if weather is active.
pub fn Weather::is_active(self : Weather) -> Bool {
  match self {
    None => false
    _ => true
  }
}
