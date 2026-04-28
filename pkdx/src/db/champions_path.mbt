///|
/// Path resolution and connection helpers for `pokedex/champions.db` —
/// the Champions-only sister DB introduced by issue #95. Champions data
/// is split off from `pokedex.db` so it can grow Champions-specific
/// tables (`champions_learnset`, future `items` from #94) without
/// polluting the upstream-owned schema.
///
/// `open_champions_rw` opens champions.db in RW mode and immediately
/// `ATTACH`es pokedex.db as the alias `pokedex`, so cross-DB JOINs
/// (`champions_learnset cl JOIN pokedex.local_waza_language wl`) work
/// inline in SQL. Callers must hold the returned `Db` exclusively for
/// the lifetime of any prepared statements that reference the
/// `pokedex.*` schema; closing the handle detaches automatically.

///|
const ENV_CHAMPIONS_DB : String = "CHAMPIONS_DB"

///|
const DEFAULT_CHAMPIONS_DB_RELPATH : String = "/pokedex/champions.db"

///|
/// Resolve the path to `champions.db` for a given repo root. The
/// `CHAMPIONS_DB` environment variable wins when set (so tests / dev
/// installs can point at a fixture or alternate location); otherwise
/// the path is `<repo_root>/pokedex/champions.db`.
pub fn resolve_champions_db_path(repo_root : String) -> String {
  match @sys.get_env_var(ENV_CHAMPIONS_DB) {
    Some(p) => p
    None => repo_root + DEFAULT_CHAMPIONS_DB_RELPATH
  }
}

///|
/// Resolve `champions.db` from a known `pokedex.db` location.
///
/// Precedence:
///   1. `CHAMPIONS_DB` env var (used verbatim).
///   2. If `pokedex_path` ends with `pokedex.db`, swap that suffix for
///      `champions.db` so a sibling file is selected.
///   3. Otherwise treat `pokedex_path` as a real file path and place
///      `champions.db` next to it (parent directory + `/champions.db`).
///
/// This is the single source of truth for `pokedex.db` → `champions.db`
/// pairing — `open_for`, `pkdx context`, `pkdx migrate`, and `with_db`
/// all route through it so a custom `POKEDEX_DB` (or `CHAMPIONS_DB`)
/// can never produce divergent attach targets.
pub fn resolve_champions_db_path_from(pokedex_path : String) -> String {
  match @sys.get_env_var(ENV_CHAMPIONS_DB) {
    Some(p) => return p
    None => ()
  }
  let suffix = "pokedex.db"
  let suffix_len = suffix.length()
  let len = pokedex_path.length()
  if len >= suffix_len {
    let mut tail_match = true
    for i = 0; i < suffix_len; i = i + 1 {
      if pokedex_path.unsafe_get(len - suffix_len + i) !=
        suffix.unsafe_get(i) {
        tail_match = false
      }
    }
    if tail_match {
      return pokedex_path[0:len - suffix_len].to_string() + "champions.db"
    }
  }
  // Custom POKEDEX_DB path that doesn't end in `pokedex.db`. Place the
  // sibling `champions.db` in the same parent directory rather than
  // appending to the file name (which would produce `<file>.champions.db`).
  let mut last_sep = -1
  for i = 0; i < len; i = i + 1 {
    let c = pokedex_path.unsafe_get(i).to_int()
    if c == 0x2F || c == 0x5C {
      last_sep = i
    }
  }
  if last_sep < 0 {
    "champions.db"
  } else {
    pokedex_path[0:last_sep + 1].to_string() + "champions.db"
  }
}

///|
/// `ATTACH DATABASE '<pokedex_path>' AS pokedex` on an open champions.db
/// handle so cross-DB references (`pokedex.local_waza_language`,
/// `pokedex.local_pokedex_type`, …) resolve in subsequent queries.
///
/// The reverse direction (`attach_champions`) is what the production
/// query layer uses: pokedex.db stays as the main connection and
/// `champions_learnset` is reached via the `champions.` prefix. This
/// function is kept for tests and for future tooling that prefers the
/// other orientation.
pub fn attach_pokedex(db : Db, pokedex_path : String) -> Result[Unit, String] {
  let escaped = escape_sqlite_string(pokedex_path)
  exec(db, "ATTACH DATABASE '" + escaped + "' AS pokedex")
}

///|
/// `ATTACH DATABASE '<champions_path>' AS champions` on an open
/// pokedex.db handle. Production queries (`query_learners_champions`,
/// `query_moves_champions`) reference `champions.champions_learnset`
/// after this call so the SQL doesn't need to know which DB owns the
/// shared `local_pokedex_*` / `local_waza*` tables.
pub fn attach_champions(
  db : Db,
  champions_path : String,
) -> Result[Unit, String] {
  let escaped = escape_sqlite_string(champions_path)
  exec(db, "ATTACH DATABASE '" + escaped + "' AS champions")
}

///|
/// Escape single quotes for embedding inside a SQLite string literal.
/// Used by `attach_pokedex`; the bind-parameter API doesn't apply to
/// `ATTACH DATABASE` (the path is part of the SQL grammar, not a value).
fn escape_sqlite_string(s : String) -> String {
  let mut out = ""
  for i = 0; i < s.length(); i = i + 1 {
    let c = s.unsafe_get(i)
    if c == 0x27 {
      // single quote → doubled
      out = out + "''"
    } else {
      out = out + s.substring(start=i, end=i + 1)
    }
  }
  out
}

///|
/// Open champions.db (read-write, must already exist) and attach
/// pokedex.db. Used by query callers that read from
/// `champions_learnset` and join shared tables.
pub fn open_champions_rw(
  champions_path : String,
  pokedex_path : String,
) -> Result[Db, String] {
  match open_rw(champions_path) {
    Err(e) => Err(e)
    Ok(db) =>
      match attach_pokedex(db, pokedex_path) {
        Err(e) => {
          close(db)
          Err(e)
        }
        Ok(_) => Ok(db)
      }
  }
}

///|
/// Open champions.db with create-if-missing semantics (read-write).
/// Used by `pkdx migrate` to bootstrap a fresh installation.
/// `attach_pokedex` is *not* called here; callers that need cross-DB
/// joins after creation can attach explicitly.
pub fn open_champions_rwc(champions_path : String) -> Result[Db, String] {
  open_rwc(champions_path)
}

///|
/// `open_for(pokedex_path, version)` — version-aware DB open. For
/// `version == "champions"` opens pokedex.db (read-only) and attaches
/// champions.db as `champions` so cross-DB JOINs resolve. Other
/// versions get pokedex.db alone. Used by `pkdx context` and other CLI
/// readers that need a single Db handle without owning the routing.
pub fn open_for(
  pokedex_path : String,
  version : String,
) -> Result[Db, String] {
  match open(pokedex_path) {
    Err(e) => Err(e)
    Ok(db) =>
      if version == "champions" {
        let champions_path = resolve_champions_db_path_from(pokedex_path)
        if not(file_exists(champions_path)) {
          // Tolerate missing champions.db — caller (cmd_context) treats
          // an attach failure / missing tables as "0 items". Returns
          // pokedex-only handle so existing queries still work.
          Ok(db)
        } else {
          match attach_champions(db, champions_path) {
            Err(e) => {
              close(db)
              Err(e)
            }
            Ok(_) => Ok(db)
          }
        }
      } else {
        Ok(db)
      }
  }
}

///|
/// Validate that champions.db has the tables it's supposed to host. For
/// P1-B the answer is "no required tables yet" — `champions_learnset`
/// stays in pokedex.db, and Phase 2 (#94) is what introduces the first
/// real occupants (`items`, `item_effect`). The function still exists
/// so callers can point it at a champions.db handle and get a uniform
/// `Result[Unit, String]` regardless of which migrations have shipped;
/// once required tables are added the list below grows.
pub fn validate_champions_schema(db : Db) -> Result[Unit, String] {
  // The `db` parameter is reserved for future schema checks; today it is
  // unused because the required-tables list is empty.
  let _ = db
  let required : Array[String] = []
  let missing : Array[String] = []
  for i = 0; i < required.length(); i = i + 1 {
    if not(table_exists(db, required[i])) {
      missing.push(required[i])
    }
  }
  if missing.length() > 0 {
    let mut msg = "champions.db missing required tables: "
    for i = 0; i < missing.length(); i = i + 1 {
      if i > 0 {
        msg = msg + ", "
      }
      msg = msg + missing[i]
    }
    Err(msg)
  } else {
    Ok(())
  }
}
