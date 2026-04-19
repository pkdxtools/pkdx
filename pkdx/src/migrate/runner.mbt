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
  skipped : Int
  total : Int
}

///|
/// Main entry point for `pkdx migrate`. Opens the DB in RW mode, creates
/// the bookkeeping table if missing, then iterates `migrations()` in
/// declaration order. Each pending migration runs inside a transaction;
/// success records its name in `pkdx_migrations`, failure rolls back and
/// propagates the error. When `resync` is true, all bookkeeping rows are
/// cleared first so every migration re-applies — used to propagate data.json
/// edits to installs that already applied the owning migration.
pub fn run(
  db_path : String,
  repo_root : String,
  resync~ : Bool = false,
) -> Result[Report, String] {
  if not(@db.file_exists(db_path)) {
    return Err(db_path + " not found. Run ./setup.sh first.")
  }
  let db = match @db.open_rw(db_path) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let result = run_with_db(db, repo_root, resync)
  @db.close(db)
  result
}

///|
fn run_with_db(
  db : @db.Db,
  repo_root : String,
  resync : Bool,
) -> Result[Report, String] {
  let create_sql = "CREATE TABLE IF NOT EXISTS pkdx_migrations (name TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))"
  match @db.exec(db, create_sql) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if resync {
    // 各 migration は冪等に実装されている:
    //   - 001 / 007: UPDATE のみ / read-only 検証
    //   - 002 / 003 / 004 / 005: 先頭で自身が書き込む Champions / 自己所有
    //     テーブルを DELETE してから再投入し、UNIQUE 制約が無い表でも
    //     重複を生まないようにしている
    //   - 006 / 008 / 010: move_meta (name_ja PRIMARY KEY) に対する
    //     INSERT OR REPLACE / UPDATE-first upsert
    // この前提で bookkeeping を空にして全件再適用しても DB は data.json
    // の現在状態に収束する。新しい migration を追加する際はこの不変条件
    // (プレーン INSERT で table を育てない) を壊さないこと。
    match @db.exec(db, "DELETE FROM pkdx_migrations") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    @db.println_progress("  Resync: cleared bookkeeping, re-applying all")
  }
  let all = migrations()
  let mut applied = 0
  let mut skipped = 0
  for i = 0; i < all.length(); i = i + 1 {
    let m = all[i]
    match is_applied(db, m.name) {
      Err(e) => return Err(e)
      Ok(true) => skipped = skipped + 1
      Ok(false) => {
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
    }
  }
  Ok({ applied, skipped, total: all.length() })
}

///|
fn is_applied(db : @db.Db, name : String) -> Result[Bool, String] {
  match @db.query_binds(
      db,
      "SELECT 1 FROM pkdx_migrations WHERE name = ?",
      [@db.BindText(name)],
    ) {
    Err(e) => Err(e)
    Ok(rows) => Ok(rows.length() > 0)
  }
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
      match @db.exec_binds(
          db,
          "INSERT INTO pkdx_migrations (name) VALUES (?)",
          [@db.BindText(m.name)],
        ) {
        Err(e) => {
          let _ = @db.exec(db, "ROLLBACK")
          Err(e)
        }
        Ok(_) =>
          match @db.exec(db, "COMMIT") {
            Err(e) => Err(e)
            Ok(_) => Ok(summary)
          }
      }
  }
}
