///|
/// Discriminates the data set / stat system / DB schema that downstream
/// code branches on. `Champions` is the M-series champions.db schema with
/// the SP stat system; `Other(name)` covers every legacy pokedex.db
/// regulation that flows through as a raw version string (`scarlet_violet`
/// etc.) into DB queries.
///
/// Existing string-based call sites use `to_db_string()` to recover the
/// underlying name when handing it to the DB layer.
///
/// **Branch-site convention**: any site whose semantics differ between
/// variants (DB schema selection, stat-system algorithm, business
/// validation, etc.) MUST `match` on `GameVersion` directly so that a new
/// variant fails to compile at every such site rather than silently
/// defaulting.
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
pub fn GameVersion::to_stat_system(self : GameVersion) -> StatSystem {
  match self {
    Champions => StatSystem::Champions
    Other(_) => StatSystem::Standard
  }
}
