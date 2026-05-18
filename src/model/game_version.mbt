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
/// defaulting. The `is_champions()` helper exists purely as a
/// convenience for non-critical predicates (e.g. UI label toggles,
/// status echoes) and intentionally collapses every non-`Champions`
/// variant into `false` — do not use it where future variants would
/// need their own branch.
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
/// Convenience predicate that intentionally collapses every
/// non-`Champions` variant into `false`. Reserved for non-critical
/// branches (UI labels, status echoes, doc-comments). For schema /
/// stat-system / validation forks — anywhere a future variant would
/// need its own arm — call sites MUST `match` on the enum directly so
/// the compiler audits the branch.
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
