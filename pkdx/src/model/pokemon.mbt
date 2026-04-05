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
} derive(Show, Eq)
