pub(all) struct Pokemon {
  pub global_no : String
  pub name_ja : String
  pub name_en : String
  pub type1 : String
  pub type2 : String
  pub hp : Int
  pub atk : Int
  pub def_ : Int
  pub spa : Int
  pub spd : Int
  pub spe : Int
  pub bst : Int
  pub ability1 : String
  pub ability2 : String
  pub dream_ability : String
} derive(Show, Eq)
