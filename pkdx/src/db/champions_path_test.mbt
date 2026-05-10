///|
/// Tests for db/champions_path.mbt (issue #95).
/// Step 0 (Red Phase): fails until resolve_champions_db_path,
/// open_champions_rw, attach_pokedex, and validate_champions_schema are
/// implemented.

///|
fn find_champions_db() -> String? {
  match @sys.get_env_var("CHAMPIONS_DB") {
    Some(p) => return Some(p)
    None => ()
  }
  let candidates = [
    "pokedex/champions.db",
    "../pokedex/champions.db",
    "../../pokedex/champions.db",
    "../../../pokedex/champions.db",
    "../../../../pokedex/champions.db",
  ]
  for i = 0; i < candidates.length(); i = i + 1 {
    let path = candidates[i]
    match open(path) {
      Ok(db) => {
        close(db)
        return Some(path)
      }
      Err(_) => continue
    }
  }
  None
}

///|
test "resolve_champions_db_path falls back to repo_root/pokedex/champions.db" {
  let p = resolve_champions_db_path("/tmp/fakeroot")
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
  inspect(ok, content="true")
}

///|
test "resolve_champions_db_path_from swaps pokedex.db -> champions.db sibling" {
  // env override must be cleared so we exercise the swap path.
  let prev = @sys.get_env_var("CHAMPIONS_DB")
  @sys.unset_env_var("CHAMPIONS_DB")
  let p = resolve_champions_db_path_from("/srv/data/pokedex.db")
  inspect(p, content="/srv/data/champions.db")
  match prev {
    Some(v) => @sys.set_env_var("CHAMPIONS_DB", v)
    None => ()
  }
}

///|
test "resolve_champions_db_path_from puts champions.db next to a custom POKEDEX_DB filename" {
  let prev = @sys.get_env_var("CHAMPIONS_DB")
  @sys.unset_env_var("CHAMPIONS_DB")
  // Custom POKEDEX_DB that doesn't end in `pokedex.db` must yield a
  // SIBLING `champions.db`, not `<file>.champions.db`.
  let p = resolve_champions_db_path_from("/srv/data/custom.db")
  inspect(p, content="/srv/data/champions.db")
  match prev {
    Some(v) => @sys.set_env_var("CHAMPIONS_DB", v)
    None => ()
  }
}

///|
test "resolve_champions_db_path_from honors CHAMPIONS_DB env override" {
  let prev = @sys.get_env_var("CHAMPIONS_DB")
  @sys.set_env_var("CHAMPIONS_DB", "/elsewhere/override.db")
  let p = resolve_champions_db_path_from("/srv/data/pokedex.db")
  inspect(p, content="/elsewhere/override.db")
  match prev {
    Some(v) => @sys.set_env_var("CHAMPIONS_DB", v)
    None => @sys.unset_env_var("CHAMPIONS_DB")
  }
}

///|
test "open_champions_rw + validate_champions_schema succeed after setup" {
  // Smoke-test path: requires both pokedex.db and champions.db to exist on
  // disk (i.e. ./setup.sh has run with the new platform refactor). Skip
  // when either is missing.
  let pokedex_path = match @sys.get_env_var("POKEDEX_DB") {
    Some(p) => p
    None => "pokedex/pokedex.db"
  }
  let champions_path = match find_champions_db() {
    Some(p) => p
    None => return
  }
  if not(file_exists(pokedex_path)) {
    return
  }
  match open_champions_rw(champions_path, pokedex_path) {
    Err(_) => fail("open_champions_rw failed despite both DB paths existing")
    Ok(db) =>
      match validate_champions_schema(db) {
        Err(e) => {
          close(db)
          fail("validate_champions_schema: " + e)
        }
        Ok(_) => close(db)
      }
  }
}

///|
test "attach_pokedex makes pokedex.* tables visible inside a champions.db handle" {
  // Same skip-when-not-set-up policy as above.
  let pokedex_path = match @sys.get_env_var("POKEDEX_DB") {
    Some(p) => p
    None => "pokedex/pokedex.db"
  }
  let champions_path = match find_champions_db() {
    Some(p) => p
    None => return
  }
  if not(file_exists(pokedex_path)) {
    return
  }
  match open_champions_rw(champions_path, pokedex_path) {
    Err(_) => return
    Ok(db) => {
      // Attached schema must expose pokedex.local_waza_language for cross-db
      // JOINs used by query_learners / query_moves.
      match query_binds(
          db, "SELECT count(*) FROM pokedex.local_waza_language LIMIT 1", [],
        ) {
        Err(e) => {
          close(db)
          fail("attach failed: " + e)
        }
        Ok(_) => close(db)
      }
    }
  }
}
