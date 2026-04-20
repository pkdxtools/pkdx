///|
/// Current schema version. Bump on breaking changes to the entries layout
/// or meta columns; mismatch causes `open_or_init` to wipe the entries
/// table.
pub const SCHEMA_VERSION : Int = 1

///|
const META_KEY_SCHEMA : String = "schema_version"

///|
const META_KEY_PKDX_VERSION : String = "pkdx_version"

///|
const META_KEY_MIGRATION : String = "migration_head"

///|
/// On-disk SQLite-backed damage cache.
///
/// Entries and meta live in the same database file so a single transaction
/// can update both, keeping them consistent even across crashes.
pub(all) struct DamageDiskCache {
  db : @db.Db
  path : String
}

///|
/// Create the cache tables if they don't already exist. Idempotent.
fn init_schema(cache_db : @db.Db) -> Result[Unit, String] {
  match
    @db.exec(
      cache_db,
      "CREATE TABLE IF NOT EXISTS damage_cache_entries (" +
      "key TEXT PRIMARY KEY, value_json TEXT NOT NULL)",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  @db.exec(
    cache_db,
    "CREATE TABLE IF NOT EXISTS damage_cache_meta (" +
    "k TEXT PRIMARY KEY, v TEXT NOT NULL)",
  )
}

///|
/// Read a single meta row, returning `None` when the key is absent.
fn read_meta(cache_db : @db.Db, k : String) -> Result[String?, String] {
  match
    @db.query_binds(
      cache_db,
      "SELECT v FROM damage_cache_meta WHERE k = ?",
      [@db.BindText(k)],
    ) {
    Err(e) => Err(e)
    Ok(rows) =>
      if rows.length() == 0 {
        Ok(None)
      } else {
        match rows[0][0] {
          Some(s) => Ok(Some(s))
          None => Ok(None)
        }
      }
  }
}

///|
/// Upsert a single meta row.
fn write_meta(
  cache_db : @db.Db,
  k : String,
  v : String,
) -> Result[Unit, String] {
  @db.exec_binds(
    cache_db,
    "INSERT INTO damage_cache_meta (k, v) VALUES (?, ?) " +
    "ON CONFLICT(k) DO UPDATE SET v = excluded.v",
    [@db.BindText(k), @db.BindText(v)],
  )
}

///|
/// Compare stored meta against current values; wipe entries and rewrite
/// meta if any are missing or mismatched.
fn validate_and_sync_meta(
  cache_db : @db.Db,
  current_version : String,
  current_head : String,
) -> Result[Unit, String] {
  let schema_v = match read_meta(cache_db, META_KEY_SCHEMA) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let pkdx_v = match read_meta(cache_db, META_KEY_PKDX_VERSION) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let migration_h = match read_meta(cache_db, META_KEY_MIGRATION) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let expected_schema = SCHEMA_VERSION.to_string()
  let mismatch = match (schema_v, pkdx_v, migration_h) {
    (Some(s), Some(p), Some(m)) =>
      s != expected_schema || p != current_version || m != current_head
    _ => true
  }
  if mismatch {
    match @db.exec(cache_db, "DELETE FROM damage_cache_entries") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match write_meta(cache_db, META_KEY_SCHEMA, expected_schema) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match write_meta(cache_db, META_KEY_PKDX_VERSION, current_version) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match write_meta(cache_db, META_KEY_MIGRATION, current_head) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
/// One-shot open attempt without corruption recovery. `open_or_init`
/// wraps this with a fallback that unlinks and retries.
fn try_open_and_init(
  path : String,
  current_version : String,
  current_head : String,
) -> Result[DamageDiskCache, String] {
  match @db.open_rwc(path) {
    Err(e) => Err(e)
    Ok(cache_db) =>
      match init_schema(cache_db) {
        Err(e) => {
          @db.close(cache_db)
          Err(e)
        }
        Ok(_) =>
          match validate_and_sync_meta(cache_db, current_version, current_head) {
            Err(e) => {
              @db.close(cache_db)
              Err(e)
            }
            Ok(_) => Ok({ db: cache_db, path, })
          }
      }
  }
}

///|
/// Error strings from the @db layer embed the raw SQLite rc as
/// `(rc=N)`. These two codes are the only ones that unambiguously mean
/// "the file on disk is not a usable SQLite database" — SQLITE_CORRUPT
/// (11) on a malformed image and SQLITE_NOTADB (26) on a non-SQLite
/// file. Transient failures (SQLITE_BUSY=5, SQLITE_IOERR=10,
/// SQLITE_PERM=3, SQLITE_CANTOPEN=14, …) must NOT trigger recovery
/// because a passing blip would otherwise wipe a healthy cache used
/// by normal `pkdx damage` / `pkdx select` flows.
fn looks_like_corruption(err : String) -> Bool {
  err.contains("(rc=11)") || err.contains("(rc=26)")
}

///|
/// Open (creating when missing) the SQLite-backed damage cache at `path`.
///
/// Only a definitive corruption signal (SQLITE_CORRUPT / SQLITE_NOTADB)
/// triggers the destructive unlink-then-retry recovery path; every
/// other failure — transient IO, busy, permission, schema init SQL
/// errors — is surfaced to the caller with the cache file untouched.
pub fn open_or_init(
  path : String,
  current_pkdx_version : String,
  current_migration_head : String,
) -> Result[DamageDiskCache, String] {
  match try_open_and_init(path, current_pkdx_version, current_migration_head) {
    Ok(cache) => Ok(cache)
    Err(first_err) =>
      if looks_like_corruption(first_err) {
        match @db.unlink_file(path) {
          Err(u) => Err("open failed: " + first_err + "; unlink failed: " + u)
          Ok(_) =>
            try_open_and_init(
              path, current_pkdx_version, current_migration_head,
            )
        }
      } else {
        Err(first_err)
      }
  }
}

///|
/// Look up an entry. Returns `None` when absent or on query error (the
/// caller falls back to the miss path, so soft-failing is acceptable).
pub fn get(cache : DamageDiskCache, key : String) -> String? {
  match
    @db.query_binds(
      cache.db,
      "SELECT value_json FROM damage_cache_entries WHERE key = ?",
      [@db.BindText(key)],
    ) {
    Err(_) => None
    Ok(rows) =>
      if rows.length() == 0 {
        None
      } else {
        rows[0][0]
      }
  }
}

///|
/// Insert or replace an entry.
pub fn put(
  cache : DamageDiskCache,
  key : String,
  value_json : String,
) -> Result[Unit, String] {
  @db.exec_binds(
    cache.db,
    "INSERT INTO damage_cache_entries (key, value_json) VALUES (?, ?) " +
    "ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json",
    [@db.BindText(key), @db.BindText(value_json)],
  )
}

///|
/// Remove all cached entries (meta untouched). Used by
/// `pkdx cache-clear damage`.
pub fn clear_all(cache : DamageDiskCache) -> Result[Unit, String] {
  @db.exec(cache.db, "DELETE FROM damage_cache_entries")
}

///|
/// Release the underlying DB handle.
pub fn close(cache : DamageDiskCache) -> Unit {
  @db.close(cache.db)
}

///|
/// Update the cache's meta rows to match the current pkdx version and
/// migration head without touching entries. Called at the tail of
/// `pkdx migrate` so subsequent `pkdx damage` invocations don't wipe
/// their cache.
pub fn sync_meta_after_migrate(
  path : String,
  pkdx_version : String,
  migration_head : String,
) -> Result[Unit, String] {
  match @db.open_rwc(path) {
    Err(e) => Err(e)
    Ok(cache_db) => {
      let r_schema_init = init_schema(cache_db)
      match r_schema_init {
        Err(e) => {
          @db.close(cache_db)
          return Err(e)
        }
        Ok(_) => ()
      }
      let expected_schema = SCHEMA_VERSION.to_string()
      let r1 = write_meta(cache_db, META_KEY_SCHEMA, expected_schema)
      let r2 = write_meta(cache_db, META_KEY_PKDX_VERSION, pkdx_version)
      let r3 = write_meta(cache_db, META_KEY_MIGRATION, migration_head)
      @db.close(cache_db)
      match (r1, r2, r3) {
        (Ok(_), Ok(_), Ok(_)) => Ok(())
        (Err(e), _, _) => Err(e)
        (_, Err(e), _) => Err(e)
        (_, _, Err(e)) => Err(e)
      }
    }
  }
}
