///|
pub(all) enum StatSystem {
  Standard
  Champions
} derive(Debug, Eq)

///|
pub extend StatSystem with Debug::{to_repr}

///|
pub extend StatSystem with Eq::{not_equal, equal}
