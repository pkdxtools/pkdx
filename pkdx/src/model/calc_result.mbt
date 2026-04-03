pub(all) struct DamageCalcResult {
  pub damages : FixedArray[Int]
  pub percents : FixedArray[Double]
  pub min_damage : Int
  pub max_damage : Int
  pub min_percent : Double
  pub max_percent : Double
  pub ko_text : String
  pub defender_hp : Int
  pub is_immune : Bool
} derive(Show)
