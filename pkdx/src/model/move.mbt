pub(all) struct Move {
  name : String
  type_ : String
  category : MoveCategory
  power : Int
  accuracy : Int
  pp : Int
  learn_method : String
} derive(Show, Eq)
