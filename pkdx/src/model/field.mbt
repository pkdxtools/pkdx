///|
/// Battle field (terrain) conditions.
pub(all) enum Field {
  None
  Electric
  Grassy
  Psychic
  Misty
} derive(Show, Eq)

///|
/// Convert Japanese field name to Field enum.
pub fn field_from_jp(name : String) -> Field {
  match name {
    "エレキ" => Electric
    "グラス" => Grassy
    "サイコ" => Psychic
    "ミスト" => Misty
    _ => None
  }
}

///|
/// Check if field is active.
pub fn Field::is_active(self : Field) -> Bool {
  match self {
    None => false
    _ => true
  }
}
