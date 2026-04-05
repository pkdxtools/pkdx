/// Coverage analysis result.
pub(all) struct CoverageResult {
  covered : Array[PokemonType]
  not_covered : Array[PokemonType]
  coverage_rate : Double
} derive(Show)

/// Calculate offensive coverage for a set of attack types.
/// Returns which defending types are hit for at least neutral (>=1x) damage.
pub fn calc_coverage(attack_types : Array[PokemonType]) -> CoverageResult {
  let covered : Array[PokemonType] = []
  let not_covered : Array[PokemonType] = []
  for i = 0; i < all_types.length(); i = i + 1 {
    let def_type = all_types[i]
    let mut best_eff = 0.0
    for j = 0; j < attack_types.length(); j = j + 1 {
      let eff = get_effectiveness(attack_types[j], def_type)
      if eff > best_eff {
        best_eff = eff
      }
    }
    if best_eff >= 1.0 {
      covered.push(def_type)
    } else {
      not_covered.push(def_type)
    }
  }
  let rate = covered.length().to_double() / 18.0
  { covered, not_covered, coverage_rate: rate }
}

/// Calculate super-effective coverage (>=2x).
pub fn calc_super_effective_coverage(
  attack_types : Array[PokemonType]
) -> CoverageResult {
  let covered : Array[PokemonType] = []
  let not_covered : Array[PokemonType] = []
  for i = 0; i < all_types.length(); i = i + 1 {
    let def_type = all_types[i]
    let mut best_eff = 0.0
    for j = 0; j < attack_types.length(); j = j + 1 {
      let eff = get_effectiveness(attack_types[j], def_type)
      if eff > best_eff {
        best_eff = eff
      }
    }
    if best_eff >= 2.0 {
      covered.push(def_type)
    } else {
      not_covered.push(def_type)
    }
  }
  let rate = covered.length().to_double() / 18.0
  { covered, not_covered, coverage_rate: rate }
}
