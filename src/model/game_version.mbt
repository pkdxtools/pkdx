///|
/// Discriminates the data set / stat system / DB schema that downstream
/// code branches on. `Champions` is the M-series champions.db schema with
/// the SP stat system; `Other(name)` covers every legacy pokedex.db
/// regulation that flows through as a raw version string (`scarlet_violet`
/// etc.) into DB queries.
///
/// Existing string-based call sites use `to_db_string()` to recover the
/// underlying name when handing it to the DB layer. Control-flow sites
/// pattern-match (or use `is_champions()`) so adding a new variant fails
/// to compile at every branch site rather than silently defaulting.
pub(all) enum GameVersion {
  Champions
  Other(String)
} derive(Eq)

///|
pub fn GameVersion::parse(s : String) -> GameVersion {
  if s == "champions" {
    Champions
  } else {
    Other(s)
  }
}

///|
pub fn GameVersion::to_db_string(self : GameVersion) -> String {
  match self {
    Champions => "champions"
    Other(s) => s
  }
}

///|
pub fn GameVersion::is_champions(self : GameVersion) -> Bool {
  match self {
    Champions => true
    Other(_) => false
  }
}

///|
pub fn GameVersion::to_stat_system(self : GameVersion) -> StatSystem {
  match self {
    Champions => StatSystem::Champions
    Other(_) => StatSystem::Standard
  }
}
