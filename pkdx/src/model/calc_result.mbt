///|
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
  // rev2: ばけのかわ初撃ブロック時に true。damages は全 0、呼び出し側で HP 1/8
  // の状態遷移を扱う。
  disguise_blocked : Bool
  // rev2: 連続技・おやこあいの実ヒット数。Single=1, Fixed(n)=n, ParentalBond=2。
  hits_dealt : Int
} derive(Show)
