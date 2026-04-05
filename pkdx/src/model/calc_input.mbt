pub(all) struct DamageCalcInput {
  attacker : Pokemon
  defender : Pokemon
  move_ : Move
  atk_ability : String
  def_ability : String
  atk_item : String
  def_item : String
  weather : Weather
  field : Field
  tera_type : String
  critical : Bool
  atk_stat_override : Int
  def_stat_override : Int
  def_hp_override : Int
} derive(Show)
