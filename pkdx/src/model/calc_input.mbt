///|
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
  // None = 攻撃stat特化相当 (+10% on offensive stat, legacy default).
  // Some(n) = n の性格補正に従う (物理技なら Atk、特殊技なら SpA、ボディプレスなら Def に対する
  // up/down を引く)。
  atk_nature : Nature?
  // None = 無補正 (legacy default)。Some(n) = n に従う。
  def_nature : Nature?
  atk_stat_override : Int
  def_stat_override : Int
  def_hp_override : Int
  atk_rank : Int
  def_rank : Int
  fainted_count : Int
  is_double : Bool
  stat_system : StatSystem
} derive(Show)
