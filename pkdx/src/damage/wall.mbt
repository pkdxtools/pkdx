///|
/// Reflect / Light Screen / Aurora Veil helpers.
///
/// `wall_applies` answers "does this wall affect the current move given its
/// physicality?" The engine additionally checks `critical`, `screen_pierce`
/// (move-side bypass) and `is_wall_bypass_ability` (attacker-side bypass)
/// before multiplying, so this helper stays focused on the wall-kind / move-
/// kind pairing.
///
/// In the 16-roll loop the multiplier itself is 2048/4096 (= 0.5) in singles
/// and 2732/4096 (≈ 0.667) in doubles. `round5` is the shared integer
/// rounding helper used by every other final modifier in `engine.mbt`, so
/// inserting wall into the chain preserves Showdown-style rounding order.

///|
pub fn wall_applies(wall : @model.Wall, is_physical : Bool) -> Bool {
  match wall {
    @model.Wall::NoWall => false
    @model.Wall::Reflect => is_physical
    @model.Wall::LightScreen => not(is_physical)
    @model.Wall::AuroraVeil => true
  }
}

///|
/// Abilities that let the attacker ignore the defender's walls.
/// Move-side bypass (かわらわり, サイコファング等) is encoded separately via
/// the `screen_pierce` input flag because it's not an ability.
pub fn is_wall_bypass_ability(ability : String) -> Bool {
  ability == "かたやぶり" ||
  ability == "すりぬけ" ||
  ability == "ターボブレイズ" ||
  ability == "テラボルテージ"
}
