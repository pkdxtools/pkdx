pub(all) struct Move {
  pub name : String
  pub type_ : String
  pub category : String
  pub power : Int
  pub accuracy : Int
  pub pp : Int
  pub learn_method : String
} derive(Show, Eq)
