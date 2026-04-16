///|
/// Shared damage-calculation helpers used by the payoff layer
/// (`switching_game`, `team_monte_carlo`, `monte_carlo`). Hosts the 16-roll
/// mean-damage reduction and the canonical `DamageCalcInput` builder.

///|
/// Mean damage over the 16-roll table. Zero for immune matchups.
fn avg_damage(r : @model.DamageCalcResult) -> Double {
  if r.is_immune {
    return 0.0
  }
  let mut s = 0
  for i in 0..<16 {
    s += r.damages[i]
  }
  s.to_double() / 16.0
}

///|
/// Build a `DamageCalcInput` with the combatants' abilities/items/tera, the
/// given attacker/defender ranks, and no weather/field. Used as the canonical
/// reference input for payoff computation.
fn build_input_with_ranks(
  atk : Combatant,
  dfn : Combatant,
  mv : @model.Move,
  atk_rank : Int,
  def_rank : Int,
) -> @model.DamageCalcInput {
  {
    attacker: atk.pokemon,
    defender: dfn.pokemon,
    move_: mv,
    atk_ability: atk.ability,
    def_ability: dfn.ability,
    atk_item: atk.item,
    def_item: dfn.item,
    weather: @model.Weather::None,
    field: @model.Field::None,
    tera_type: atk.tera_type,
    critical: false,
    atk_stat_override: 0,
    def_stat_override: 0,
    def_hp_override: 0,
    atk_rank,
    def_rank,
    fainted_count: 0,
    is_double: false,
    stat_system: atk.stat_system,
  }
}
