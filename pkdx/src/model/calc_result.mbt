pub(all) struct DamageCalcResult {
  damages : FixedArray[Int]
  percents : FixedArray[Double]
  min_damage : Int
  max_damage : Int
  min_percent : Double
  max_percent : Double
  ko_text : String
  defender_hp : Int
  is_immune : Bool
} derive(Show)
