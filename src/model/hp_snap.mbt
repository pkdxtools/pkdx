///|
/// HP value constraint derived from item / residual-damage interactions.
/// These are effect-based names; mapping to actual held items is the user's responsibility.
pub(all) enum HpSnap {
  NoSnap
  Leftovers
  Residual
  Sitrus
  LifeOrb
} derive(Show, Eq)

///|
/// Check whether an HP actual value satisfies a snap constraint.
pub fn matches_snap(hp : Int, snap : HpSnap) -> Bool {
  match snap {
    NoSnap => true
    Leftovers => hp % 16 == 1
    Residual => hp % 16 == 15
    Sitrus => hp % 2 == 0
    LifeOrb => hp % 10 == 0
  }
}

///|
/// Parse a CLI `--hp-snap` flag value.
pub fn hp_snap_from_str(s : String) -> HpSnap? {
  match s {
    "none" => Some(NoSnap)
    "leftovers" => Some(Leftovers)
    "residual" => Some(Residual)
    "sitrus" => Some(Sitrus)
    "lifeorb" => Some(LifeOrb)
    _ => None
  }
}
