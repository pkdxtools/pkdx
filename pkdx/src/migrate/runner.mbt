///|
/// A single migration step. Receives an open RW connection and the repo
/// root (so it can read `data.json` or `pokedex/pokedex/LegendsZA/...`
/// alongside the source tree). Returns a summary line on success — the
/// runner prints it indented, matching the original apply.rb formatting.
pub type MigrationFn = (@db.Db, String) -> Result[String, String]

///|
pub(all) struct Migration {
  name : String
  run : MigrationFn
}

///|
pub(all) struct Report {
  applied : Int
  total : Int
}

///|
/// Main entry point for `pkdx migrate`. Opens the DB in RW mode and runs
/// every registered migration in declaration order, each inside its own
/// transaction. Failure rolls back and propagates the error.
///
/// pokedex.db / champions.db のいずれもユーザーランタイムが書き込む
/// データを持たない (damage cache は別ファイル `box/cache/damage_cache.sqlite`)。
/// つまり migrate は常に「seed の再適用」であり、bookkeeping は不要。
/// すべての migration は冪等 (DELETE → 再投入 / INSERT OR REPLACE /
/// existence-check INSERT / ALTER TABLE は ensure_column) なので何度
/// 流しても DB は data.json の現在状態へ収束する。
pub fn run(db_path : String, repo_root : String) -> Result[Report, String] {
  run_for(db_path, repo_root, migrations=migrations())
}

///|
/// Run a specific subset of migrations against `db_path`. Used by the
/// 2-stage migrate flow: pokedex.db only sees `migrations_pokedex()` and
/// champions.db only sees `migrations_champions()`, so migrations don't
/// trip on tables that don't belong to the DB they're applied to.
pub fn run_for(
  db_path : String,
  repo_root : String,
  migrations~ : Array[Migration],
) -> Result[Report, String] {
  if not(@db.file_exists(db_path)) {
    return Err(db_path + " not found. Run ./setup.sh first.")
  }
  let db = match @db.open_rw(db_path) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let result = run_with_db(db, repo_root, migrations)
  @db.close(db)
  result
}

///|
fn run_with_db(
  db : @db.Db,
  repo_root : String,
  all : Array[Migration],
) -> Result[Report, String] {
  let mut applied = 0
  for i = 0; i < all.length(); i = i + 1 {
    let m = all[i]
    @db.println_progress("  Applying " + m.name + "...")
    match apply_one(db, m, repo_root) {
      Err(e) => return Err("FAILED " + m.name + ": " + e)
      Ok(summary) => {
        if summary.length() > 0 {
          @db.println_progress("    " + summary)
        }
        applied = applied + 1
      }
    }
  }
  Ok({ applied, total: all.length() })
}

///|
fn apply_one(
  db : @db.Db,
  m : Migration,
  repo_root : String,
) -> Result[String, String] {
  match @db.exec(db, "BEGIN") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match (m.run)(db, repo_root) {
    Err(e) => {
      let _ = @db.exec(db, "ROLLBACK")
      Err(e)
    }
    Ok(summary) =>
      match @db.exec(db, "COMMIT") {
        Err(e) => Err(e)
        Ok(_) => Ok(summary)
      }
  }
}
