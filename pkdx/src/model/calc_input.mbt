pub(all) struct DamageCalcInput {
  pub attacker : Pokemon
  pub defender : Pokemon
  pub move_ : Move
  pub atk_ability : String
  pub def_ability : String
  pub atk_item : String
  pub def_item : String
  pub weather : String
  pub field : String
  pub tera_type : String
  pub critical : Bool
  pub atk_stat_override : Int
  pub def_stat_override : Int
  pub def_hp_override : Int
} derive(Show)
