/// Pokemon type enumeration (Gen6+ 18 types).
pub enum PokemonType {
  Normal
  Fire
  Water
  Electric
  Grass
  Ice
  Fighting
  Poison
  Ground
  Flying
  Psychic
  Bug
  Rock
  Ghost
  Dragon
  Dark
  Steel
  Fairy
} derive(Show, Eq)

/// All 18 types in order.
pub let all_types : Array[PokemonType] = [
  Normal, Fire, Water, Electric, Grass, Ice, Fighting, Poison, Ground, Flying,
  Psychic, Bug, Rock, Ghost, Dragon, Dark, Steel, Fairy,
]

/// Convert Japanese type name to PokemonType.
pub fn type_from_jp(name : String) -> PokemonType? {
  match name {
    "ノーマル" => Some(Normal)
    "ほのお" => Some(Fire)
    "みず" => Some(Water)
    "でんき" => Some(Electric)
    "くさ" => Some(Grass)
    "こおり" => Some(Ice)
    "かくとう" => Some(Fighting)
    "どく" => Some(Poison)
    "じめん" => Some(Ground)
    "ひこう" => Some(Flying)
    "エスパー" => Some(Psychic)
    "むし" => Some(Bug)
    "いわ" => Some(Rock)
    "ゴースト" => Some(Ghost)
    "ドラゴン" => Some(Dragon)
    "あく" => Some(Dark)
    "はがね" => Some(Steel)
    "フェアリー" => Some(Fairy)
    _ => None
  }
}

/// Convert PokemonType to Japanese name.
pub fn type_to_jp(t : PokemonType) -> String {
  match t {
    Normal => "ノーマル"
    Fire => "ほのお"
    Water => "みず"
    Electric => "でんき"
    Grass => "くさ"
    Ice => "こおり"
    Fighting => "かくとう"
    Poison => "どく"
    Ground => "じめん"
    Flying => "ひこう"
    Psychic => "エスパー"
    Bug => "むし"
    Rock => "いわ"
    Ghost => "ゴースト"
    Dragon => "ドラゴン"
    Dark => "あく"
    Steel => "はがね"
    Fairy => "フェアリー"
  }
}

fn type_ordinal(t : PokemonType) -> Int {
  match t {
    Normal => 0
    Fire => 1
    Water => 2
    Electric => 3
    Grass => 4
    Ice => 5
    Fighting => 6
    Poison => 7
    Ground => 8
    Flying => 9
    Psychic => 10
    Bug => 11
    Rock => 12
    Ghost => 13
    Dragon => 14
    Dark => 15
    Steel => 16
    Fairy => 17
  }
}

/// Gen6+ 18x18 type effectiveness chart.
/// Values: 0=immune, 2=half(0.5x), 4=neutral(1x), 8=super(2x)
let type_chart : FixedArray[Int] = [
  // ノーマル attacking
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 2, 0, 4, 4, 2, 4,
  // ほのお attacking
  4, 2, 2, 4, 8, 8, 4, 4, 4, 4, 4, 8, 2, 4, 2, 4, 8, 4,
  // みず attacking
  4, 8, 2, 4, 2, 4, 4, 4, 8, 4, 4, 4, 8, 4, 2, 4, 4, 4,
  // でんき attacking
  4, 4, 8, 2, 2, 4, 4, 4, 0, 8, 4, 4, 4, 4, 2, 4, 4, 4,
  // くさ attacking
  4, 2, 8, 4, 2, 4, 4, 2, 8, 2, 4, 2, 8, 4, 2, 4, 2, 4,
  // こおり attacking
  4, 2, 2, 4, 8, 2, 4, 4, 8, 8, 4, 4, 4, 4, 8, 4, 2, 4,
  // かくとう attacking
  8, 4, 4, 4, 4, 8, 4, 2, 4, 2, 2, 2, 8, 0, 4, 8, 8, 2,
  // どく attacking
  4, 4, 4, 4, 8, 4, 4, 2, 2, 4, 4, 4, 2, 2, 4, 4, 0, 8,
  // じめん attacking
  4, 8, 4, 8, 2, 4, 4, 8, 4, 0, 4, 2, 8, 4, 4, 4, 8, 4,
  // ひこう attacking
  4, 4, 4, 2, 8, 4, 8, 4, 4, 4, 4, 8, 2, 4, 4, 4, 2, 4,
  // エスパー attacking
  4, 4, 4, 4, 4, 4, 8, 8, 4, 4, 2, 4, 4, 4, 4, 0, 2, 4,
  // むし attacking
  4, 2, 4, 4, 8, 4, 2, 2, 4, 2, 8, 4, 4, 2, 4, 8, 2, 2,
  // いわ attacking
  4, 8, 4, 4, 4, 8, 2, 4, 2, 8, 4, 8, 4, 4, 4, 4, 2, 4,
  // ゴースト attacking
  0, 4, 4, 4, 4, 4, 4, 4, 4, 4, 8, 4, 4, 8, 4, 2, 4, 4,
  // ドラゴン attacking
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 8, 4, 2, 0,
  // あく attacking
  4, 4, 4, 4, 4, 4, 2, 4, 4, 4, 8, 4, 4, 8, 4, 2, 4, 2,
  // はがね attacking
  4, 2, 2, 2, 4, 8, 4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 2, 8,
  // フェアリー attacking
  4, 2, 4, 4, 4, 4, 8, 2, 4, 4, 4, 4, 4, 4, 8, 8, 2, 4,
]

/// Get type effectiveness as x4 integer (0=immune, 2=0.5x, 4=1x, 8=2x).
pub fn get_effectiveness_x4(atk : PokemonType, def : PokemonType) -> Int {
  type_chart[type_ordinal(atk) * 18 + type_ordinal(def)]
}

/// Get type effectiveness as Double.
pub fn get_effectiveness(atk : PokemonType, def : PokemonType) -> Double {
  get_effectiveness_x4(atk, def).to_double() / 4.0
}

/// Get combined effectiveness against a dual-typed defender.
pub fn get_dual_effectiveness(
  atk : PokemonType,
  def1 : PokemonType,
  def2 : PokemonType?
) -> Double {
  let eff1 = get_effectiveness(atk, def1)
  match def2 {
    Some(d2) => eff1 * get_effectiveness(atk, d2)
    None => eff1
  }
}
