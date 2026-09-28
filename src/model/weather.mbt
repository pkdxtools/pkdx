///|
/// Battle weather conditions.
pub(all) enum Weather {
  None
  Sun
  Rain
  Sand
  Snow
} derive(Debug, Eq, Hash)

///|
pub extend Weather with Debug::{to_repr}

///|
pub extend Weather with Eq::{not_equal, equal}

///|
pub extend Weather with Hash::{hash, hash_combine}

///|
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

///|
/// Check if weather is active.
pub fn Weather::is_active(self : Weather) -> Bool {
  match self {
    None => false
    _ => true
  }
}
