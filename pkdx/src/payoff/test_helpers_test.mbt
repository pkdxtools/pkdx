///|
/// Shared fixtures for payoff tests. Built on the same idiom as
/// `damage/test_helpers_test.mbt` but specialised for `Combatant`.
fn mk_pokemon(
  name : String,
  type1 : String,
  type2 : String,
  hp : Int,
  atk : Int,
  def_ : Int,
  spa : Int,
  spd : Int,
  spe : Int,
) -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: name,
    name_en: name,
    type1,
    type2,
    hp,
    atk,
    def_,
    spa,
    spd,
    spe,
    bst: hp + atk + def_ + spa + spd + spe,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 0.0,
  }
}

///|
fn mk_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
  priority~ : Int = 0,
  stat_effects~ : Array[(Int, Int)] = [],
  status_effect~ : (@model.StatusKind, Int)? = None,
  accuracy~ : Int = 100,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
    accuracy,
    pp: 10,
    learn_method: "",
    priority,
    stat_effects,
    status_effect,
  }
}

///|
fn mk_combatant(
  pokemon : @model.Pokemon,
  moves : Array[@model.Move],
  ability~ : String = "",
  item~ : String = "",
  tera_type~ : String = "",
  mega_form~ : @model.MegaForm? = None,
) -> Combatant {
  {
    pokemon,
    moves,
    ability,
    item,
    tera_type,
    stat_system: @model.Standard,
    mega_form,
  }
}
