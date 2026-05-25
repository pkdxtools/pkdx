///|
/// Gen 9 field (terrain) damage modifier (4096-base — same encoding as
/// `get_weather_damage_mod` so the engine pipeline applies both with
/// `round5(dmg, mod)`).
///
/// Boost arm (attacker grounded, 1.3x):
///   - Electric field + でんき技      → 5325  (1.3 × 4096 ≈ 5324.8 → 5325)
///   - Grassy   field + くさ技        → 5325
///   - Psychic  field + エスパー技    → 5325
///
/// Debuff arm (defender grounded, 0.5x):
///   - Grassy field + じしん/マグニチュード/じならし → 2048 (0.5 × 4096)
///   - Misty  field + ドラゴン技                     → 2048
///
/// 1.3x rationale: Gen 8+ baseline. Earlier generations applied 1.5x; pkdx
/// is Gen 9. Constants kept in the same numerator-of-4096 form as
/// `get_weather_damage_mod` (e.g. `6144 = 1.5 × 4096`, `2048 = 0.5 × 4096`)
/// so the engine's `round5(dmg, mod)` step is bit-identical between the
/// weather and field passes.
///
/// Returns 0 when no modifier applies. Caller (engine.mbt) checks `> 0`
/// before invoking `round5`, matching the weather pattern.
pub fn get_field_damage_mod(
  field : @model.Field,
  move_name : String,
  move_type : String,
  attacker_grounded : Bool,
  defender_grounded : Bool,
) -> Int {
  match field {
    @model.Field::None => 0
    @model.Field::Electric =>
      if attacker_grounded && move_type == "でんき" {
        5325
      } else {
        0
      }
    @model.Field::Grassy => {
      // Two arms: grass boost (attacker grounded) vs earthquake-family
      // weakening (defender grounded). The arms are mutually exclusive
      // because a move's type can't be both くさ and じめん.
      if attacker_grounded && move_type == "くさ" {
        return 5325
      }
      if defender_grounded && is_grassy_weakened_move(move_name) {
        return 2048
      }
      0
    }
    @model.Field::Misty =>
      if defender_grounded && move_type == "ドラゴン" {
        2048
      } else {
        0
      }
    @model.Field::Psychic =>
      if attacker_grounded && move_type == "エスパー" {
        5325
      } else {
        0
      }
  }
}

///|
/// じめん技のうち Grassy field で 0.5x を受ける Gen 9 spec ground moves。
/// あなをほる / じわれ / 10まんばりき などは対象外 (公式仕様)。
fn is_grassy_weakened_move(move_name : String) -> Bool {
  move_name == "じしん" || move_name == "マグニチュード" || move_name == "じならし"
}

///|
/// Gen 9 minimal grounded check. Primitive-arg shape so `@damage` doesn't
/// need to import `@payoff.Combatant` (would introduce a cycle —
/// `payoff` already imports `damage`).
///
/// NOT grounded iff any of:
///   - `ability == "ふゆう"`
///   - `type1 == "ひこう"` or `type2 == "ひこう"`
///   - `item == "ふうせん"`
///
/// 別 PR で扱う out-of-scope: テラスタル / うちおとす / グランディング技 /
/// ゆうばく / アイアンボール (item) / でんじふゆう / おうじゃのしるし 等。
pub fn is_grounded(
  type1~ : String,
  type2~ : String,
  ability~ : String,
  item~ : String,
) -> Bool {
  if ability == "ふゆう" {
    return false
  }
  if type1 == "ひこう" || type2 == "ひこう" {
    return false
  }
  if item == "ふうせん" {
    return false
  }
  true
}
