/// Move damage category.
pub enum MoveCategory {
  Physical
  Special
  Status
} derive(Show, Eq)

/// Convert Japanese category name to MoveCategory enum.
pub fn category_from_jp(name : String) -> MoveCategory {
  match name {
    "物理" => Physical
    "特殊" => Special
    _ => Status
  }
}

/// Convert MoveCategory to Japanese name.
pub fn category_to_jp(cat : MoveCategory) -> String {
  match cat {
    Physical => "物理"
    Special => "特殊"
    Status => "変化"
  }
}
