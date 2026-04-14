///|
/// Damage → payoff matrix conversion.
///
/// For each ordered pair (i, j), `winrate(i, j)` ∈ [0, 1] is computed under a
/// `PayoffModel`, and the payoff is `A[i, j] = 2·winrate(i, j) − 1` ∈ [-1, 1].
/// This rescaling makes `A[i, j] + A[j, i] = 0` whenever `winrate(i, j) +
/// winrate(j, i) = 1`, which holds for both `Best1v1` and `NashResponses`
/// under simultaneous-move semantics.

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
/// reference input for payoff computation — existing call-sites should use
/// `build_input` (ranks=0) unless they specifically need rank-aware damage
/// (`SwitchingGame`'s rank-tracked state).
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

///|
/// Rank-less build_input. Equivalent to `build_input_with_ranks(..., 0, 0)`.
fn build_input(
  atk : Combatant,
  dfn : Combatant,
  mv : @model.Move,
) -> @model.DamageCalcInput {
  build_input_with_ranks(atk, dfn, mv, 0, 0)
}

///|
/// Turns `atk` needs to KO `dfn` using `mv`. `+∞` if immune or zero damage.
fn turns_to_ko(
  atk : Combatant,
  dfn : Combatant,
  mv : @model.Move,
) -> Double {
  let r = @damage.calc_damage(build_input(atk, dfn, mv))
  let avg = avg_damage(r)
  if avg <= 0.0 {
    return @double.infinity
  }
  r.defender_hp.to_double() / avg
}

///|
/// Minimum turns across `atk`'s moves. `+∞` if all moves are immune.
fn best_turns(atk : Combatant, dfn : Combatant) -> Double {
  let mut best = @double.infinity
  for mv in atk.moves {
    let t = turns_to_ko(atk, dfn, mv)
    if t < best {
      best = t
    }
  }
  best
}

///|
/// Speed comparison: +1 if `a` outspeeds `b`, −1 if slower, 0 on tie.
fn speed_sign(a : Combatant, b : Combatant) -> Int {
  if a.pokemon.spe > b.pokemon.spe {
    1
  } else if a.pokemon.spe < b.pokemon.spe {
    -1
  } else {
    0
  }
}

///|
/// `Best1v1` winrate in [0, 1] for `a` vs `b`. Each side picks the move that
/// minimises its KO turn count; ties are broken by speed, with full ties
/// (same turns, same speed) resolving to 0.5.
pub fn best1v1_winrate(a : Combatant, b : Combatant) -> Double {
  let ta = best_turns(a, b)
  let tb = best_turns(b, a)
  if ta < tb {
    1.0
  } else if ta > tb {
    0.0
  } else if ta.is_inf() {
    // Both sides deal zero damage — neither can win; call it a draw.
    0.5
  } else {
    let s = speed_sign(a, b)
    if s > 0 {
      1.0
    } else if s < 0 {
      0.0
    } else {
      0.5
    }
  }
}

///|
/// `NashResponses` winrate in [0, 1] for `a` vs `b`. Builds the inner
/// `|a.moves| × |b.moves|` matrix of per-move outcomes (same ±1 / 0 encoding
/// as `Best1v1`) and returns the Nash value rescaled to [0, 1].
pub fn nash_responses_winrate(a : Combatant, b : Combatant) -> Double {
  let ra = a.moves.length()
  let rb = b.moves.length()
  if ra == 0 || rb == 0 {
    return 0.5
  }
  let spd = speed_sign(a, b)
  let data = Array::make(ra, ([] : Array[Double]))
  for i in 0..<ra {
    let row = Array::make(rb, 0.0)
    for j in 0..<rb {
      let ta = turns_to_ko(a, b, a.moves[i])
      let tb = turns_to_ko(b, a, b.moves[j])
      row[j] = if ta < tb {
        1.0
      } else if ta > tb {
        -1.0
      } else if ta.is_inf() {
        0.0
      } else if spd > 0 {
        1.0
      } else if spd < 0 {
        -1.0
      } else {
        0.0
      }
    }
    data[i] = row
  }
  let m = match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => return 0.5
  }
  let v = try @nash.solve_zero_sum(m) catch {
    _ => return 0.5
  }
  match v {
    Optimal(value~, ..) => (value + 1.0) / 2.0
    _ => 0.5
  }
}

///|
/// Winrate for `a` vs `b` under the given model, in [0, 1].
pub fn winrate(a : Combatant, b : Combatant, model : PayoffModel) -> Double {
  match model {
    Best1v1 => best1v1_winrate(a, b)
    NashResponses => nash_responses_winrate(a, b)
    MonteCarloSim(trials, seed) => monte_carlo_winrate(a, b, trials, seed)
  }
}

///|
/// Build the zero-sum payoff matrix `A[i, j] = 2·winrate(i, j) − 1` from a
/// list of combatants under the given `PayoffModel`.
///
/// For `MonteCarloSim` the matrix is built with **upper-triangle estimation
/// and antisymmetric completion** (`A[j, i] = -A[i, j]`, `A[i, i] = 0`) to
/// preserve zero-sum property under finite-sample noise. Deterministic models
/// (`Best1v1`, `NashResponses`) keep the independent per-cell computation.
pub fn from_combatants(
  combatants : Array[Combatant],
  model : PayoffModel,
) -> @nash.FiniteMatrix raise PayoffError {
  let n = combatants.length()
  if n == 0 {
    raise EmptyCombatants
  }
  for c in combatants {
    if c.moves.length() == 0 {
      raise EmptyMoves(c.pokemon.name_ja)
    }
  }
  let data = Array::make(n, ([] : Array[Double]))
  for i in 0..<n {
    data[i] = Array::make(n, 0.0)
  }
  match model {
    MonteCarloSim(_, _) =>
      for i in 0..<n {
        for j in (i + 1)..<n {
          let wr = winrate(combatants[i], combatants[j], model)
          let payoff = 2.0 * wr - 1.0
          data[i][j] = payoff
          data[j][i] = -payoff
        }
      }
    _ =>
      for i in 0..<n {
        for j in 0..<n {
          let wr = winrate(combatants[i], combatants[j], model)
          data[i][j] = 2.0 * wr - 1.0
        }
      }
  }
  match @nash.FiniteMatrix::new(data) {
    Ok(m) => m
    Err(_) => raise EmptyCombatants
  }
}
