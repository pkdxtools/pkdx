///|
/// Tests for db/champions_path.mbt (issue #95).
/// Step 0 (Red Phase): fails until resolve_champions_db_path,
/// open_champions_rw, attach_pokedex, and validate_champions_schema are
/// implemented.

///|
fn find_champions_db() -> String? {
  match @env.get_env_var("CHAMPIONS_DB") {
    Some(p) => return Some(p)
    None => ()
  }
  let candidates = [
    "pokedex/champions.db", "../pokedex/champions.db", "../../pokedex/champions.db",
    "../../../pokedex/champions.db", "../../../../pokedex/champions.db",
  ]
  for i = 0; i < candidates.length(); i = i + 1 {
    let path = candidates[i]
    match @db.open(path) {
      Ok(db) => {
        @db.close(db)
        return Some(path)
      }
      Err(_) => continue
    }
  }
  None
}

///|
test "resolve_champions_db_path falls back to repo_root/pokedex/champions.db" {
  let p = @db.resolve_champions_db_path("/tmp/fakeroot")
  // Default tail must end in pokedex/champions.db (env var override is
  // tested separately; a non-existent root just exercises the formatting).
  let suffix = "/pokedex/champions.db"
  let len = p.length()
  let slen = suffix.length()
  let mut ok = len >= slen
  if ok {
    for i = 0; i < slen; i = i + 1 {
      if p.unsafe_get(len - slen + i) != suffix.unsafe_get(i) {
        ok = false
      }
    }
  }
  assert_true(ok)
}

///|
test "resolve_champions_db_path_from swaps pokedex.db -> champions.db sibling" {
  // env override must be cleared so we exercise the swap path.
  let prev = @env.get_env_var("CHAMPIONS_DB")
  @env.unset_env_var("CHAMPIONS_DB")
  let p = @db.resolve_champions_db_path_from("/srv/data/pokedex.db")
  @debug.debug_inspect(
    p,
    content=(
      #|"/srv/data/champions.db"
    ),
  )
  match prev {
    Some(v) => @env.set_env_var("CHAMPIONS_DB", v)
    None => ()
  }
}

///|
test "resolve_champions_db_path_from puts champions.db next to a custom POKEDEX_DB filename" {
  let prev = @env.get_env_var("CHAMPIONS_DB")
  @env.unset_env_var("CHAMPIONS_DB")
  // Custom POKEDEX_DB that doesn't end in `pokedex.db` must yield a
  // SIBLING `champions.db`, not `<file>.champions.db`.
  let p = @db.resolve_champions_db_path_from("/srv/data/custom.db")
  @debug.debug_inspect(
    p,
    content=(
      #|"/srv/data/champions.db"
    ),
  )
  match prev {
    Some(v) => @env.set_env_var("CHAMPIONS_DB", v)
    None => ()
  }
}

///|
test "resolve_champions_db_path_from honors CHAMPIONS_DB env override" {
  let prev = @env.get_env_var("CHAMPIONS_DB")
  @env.set_env_var("CHAMPIONS_DB", "/elsewhere/override.db")
  let p = @db.resolve_champions_db_path_from("/srv/data/pokedex.db")
  @debug.debug_inspect(
    p,
    content=(
      #|"/elsewhere/override.db"
    ),
  )
  match prev {
    Some(v) => @env.set_env_var("CHAMPIONS_DB", v)
    None => @env.unset_env_var("CHAMPIONS_DB")
  }
}

///|
test "open_champions_rw + validate_champions_schema succeed after setup" {
  // Smoke-test path: requires both pokedex.db and champions.db to exist on
  // disk (i.e. ./setup.sh has run with the new platform refactor). Skip
  // when either is missing.
  let pokedex_path = match @env.get_env_var("POKEDEX_DB") {
    Some(p) => p
    None => "pokedex/pokedex.db"
  }
  let champions_path = match find_champions_db() {
    Some(p) => p
    None => return
  }
  if !@db.file_exists(pokedex_path) {
    return
  }
  match @db.open_champions_rw(champions_path, pokedex_path) {
    Err(_) => fail("open_champions_rw failed despite both DB paths existing")
    Ok(db) =>
      match @db.validate_champions_schema(db) {
        Err(e) => {
          @db.close(db)
          fail("validate_champions_schema: " + e)
        }
        Ok(_) => @db.close(db)
      }
  }
}

///|
test "attach_pokedex makes pokedex.* tables visible inside a champions.db handle" {
  // Same skip-when-not-set-up policy as above.
  let pokedex_path = match @env.get_env_var("POKEDEX_DB") {
    Some(p) => p
    None => "pokedex/pokedex.db"
  }
  let champions_path = match find_champions_db() {
    Some(p) => p
    None => return
  }
  if !@db.file_exists(pokedex_path) {
    return
  }
  match @db.open_champions_rw(champions_path, pokedex_path) {
    Err(_) => return
    Ok(db) =>
      // Attached schema must expose pokedex.local_waza_language for cross-db
      // JOINs used by query_learners / query_moves.
      match
        @db.query_binds(
          db,
          "SELECT count(*) FROM pokedex.local_waza_language LIMIT 1",
          [],
        ) {
        Err(e) => {
          @db.close(db)
          fail("attach failed: " + e)
        }
        Ok(_) => @db.close(db)
      }
  }
}
