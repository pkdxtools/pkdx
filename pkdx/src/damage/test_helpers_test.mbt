///|
fn mk_pokemon(
  name : String,
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
    type1: "",
    type2: "",
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
fn mk_pokemon_typed(
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
fn default_ivs() -> FixedArray[Int] {
  [31, 31, 31, 31, 31, 31]
}

///|
fn neutral_nature() -> @model.Nature {
  { name_ja: "まじめ", name_en: "Serious", up: None, down: None }
}

///|
fn mk_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
    accuracy: 100,
    pp: 10,
    learn_method: "",
    priority: 0,
    stat_effects: [],
    status_effect: None,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
  }
}

///|
fn mk_damage_input(
  attacker : @model.Pokemon,
  defender : @model.Pokemon,
  move_ : @model.Move,
  atk_rank? : Int = 0,
  def_rank? : Int = 0,
  critical? : Bool = false,
  atk_stat_override? : Int = 0,
  def_stat_override? : Int = 0,
  def_hp_override? : Int = 0,
  atk_nature? : @model.Nature? = None,
  def_nature? : @model.Nature? = None,
  atk_ability? : String = "",
  def_ability? : String = "",
  atk_item? : String = "",
  def_item? : String = "",
  weather? : @model.Weather = @model.Weather::None,
  field? : @model.Field = @model.Field::None,
  tera_type? : String = "",
  fainted_count? : Int = 0,
  is_double? : Bool = false,
  stat_system? : @model.StatSystem = @model.Standard,
) -> @model.DamageCalcInput {
  {
    attacker,
    defender,
    move_,
    atk_ability,
    def_ability,
    atk_item,
    def_item,
    weather,
    field,
    tera_type,
    critical,
    atk_nature,
    def_nature,
    atk_stat_override,
    def_stat_override,
    def_hp_override,
    atk_rank,
    def_rank,
    fainted_count,
    is_double,
    stat_system,
  }
}
