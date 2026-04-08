///|
pub(all) struct Pokemon {
  global_no : String
  name_ja : String
  name_en : String
  type1 : String
  type2 : String
  hp : Int
  atk : Int
  def_ : Int
  spa : Int
  spd : Int
  spe : Int
  bst : Int
  ability1 : String
  ability2 : String
  dream_ability : String
  // 体重 (kg)。けたぐり/くさむすび/ヘビーボンバー/ヒートスタンプの威力計算に使用。
  // DBに値が無い場合は 0.0。
  weight : Double
} derive(Show, Eq)
