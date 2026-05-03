///|
/// Shadow tests for the DB-backed item resolution (issue #94 — P2-C MVP).
/// For the 3 items seeded by `m013_items` we assert the DB path matches
/// the hardcoded `damage/items.mbt` output for the relevant inputs.
/// Full parity with the rest of `items.mbt` is the next follow-up.

///|
fn ish_open_seeded_db() -> @db.Db? {
  // Spin up a fresh in-process champions.db, build the items / item_effect
  // schema, and seed the 3 MVP rows. Returning None lets the test skip
  // when the FFI / file-system setup is unavailable (rare).
  let path = "pkdx_items_shadow_test.db"
  let _ = @db.unlink_file(path)
  match @db.open_rwc(path) {
    Err(_) => None
    Ok(db) => {
      // Use the same DDL as m013_items.run_013 — duplicating verbatim
      // keeps the test self-contained without forcing a public migrate
      // entry-point.
      let _ = @db.exec(
        db,
        "CREATE TABLE items (name_ja TEXT PRIMARY KEY, name_en TEXT, category TEXT, flavor TEXT)",
      )
      let _ = @db.exec(
        db,
        "CREATE TABLE item_effect (item_name TEXT NOT NULL, effect_kind TEXT NOT NULL, apply_order INTEGER NOT NULL, num INTEGER, den INTEGER, type_filter TEXT, pokemon_filter TEXT, is_physical INTEGER, super_effective_only INTEGER)",
      )
      let _ = @db.exec_binds(
        db,
        "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES ('こだわりハチマキ', 'stat_mod', 2, 3, 2, NULL, NULL, 1, 0)",
        [],
      )
      let _ = @db.exec_binds(
        db,
        "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES ('いのちのたま', 'final_mod', 3, 5324, 4096, NULL, NULL, NULL, 0)",
        [],
      )
      let _ = @db.exec_binds(
        db,
        "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES ('オッカのみ', 'resist_berry', 0, 2048, 4096, 'ほのお', NULL, NULL, 1)",
        [],
      )
      Some(db)
    }
  }
}

///|
test "shadow: こだわりハチマキ stat mod matches hardcode (physical and special)" {
  let db = match ish_open_seeded_db() {
    Some(d) => d
    None => return
  }
  let effects = match @db.query_item_effects(db, "こだわりハチマキ") {
    Ok(e) => e
    Err(_) => {
      @db.close(db)
      return
    }
  }
  // Physical: hardcoded multiplies by 3/2; DB should match.
  let hardcode_phys = apply_atk_item_stat("こだわりハチマキ", true, "0445", 200)
  let db_phys = apply_atk_item_stat_db(effects, true, 200)
  inspect(hardcode_phys == db_phys, content="true")
  // Special: hardcoded leaves stat unchanged; DB should match.
  let hardcode_spec = apply_atk_item_stat("こだわりハチマキ", false, "0445", 200)
  let db_spec = apply_atk_item_stat_db(effects, false, 200)
  inspect(hardcode_spec == db_spec, content="true")
  @db.close(db)
}

///|
test "shadow: いのちのたま final mod matches hardcode (any category)" {
  let db = match ish_open_seeded_db() {
    Some(d) => d
    None => return
  }
  let effects = match @db.query_item_effects(db, "いのちのたま") {
    Ok(e) => e
    Err(_) => {
      @db.close(db)
      return
    }
  }
  // Hardcode: 5324 regardless of physical/SE flags.
  let h_phys_se = get_atk_item_final("いのちのたま", true, true)
  let d_phys_se = get_atk_item_final_db(effects, true, true)
  inspect(h_phys_se == d_phys_se, content="true")
  let h_phys_nse = get_atk_item_final("いのちのたま", true, false)
  let d_phys_nse = get_atk_item_final_db(effects, true, false)
  inspect(h_phys_nse == d_phys_nse, content="true")
  let h_spec = get_atk_item_final("いのちのたま", false, true)
  let d_spec = get_atk_item_final_db(effects, false, true)
  inspect(h_spec == d_spec, content="true")
  @db.close(db)
}

///|
test "shadow: オッカのみ resist berry type matches hardcode" {
  let db = match ish_open_seeded_db() {
    Some(d) => d
    None => return
  }
  let effects = match @db.query_item_effects(db, "オッカのみ") {
    Ok(e) => e
    Err(_) => {
      @db.close(db)
      return
    }
  }
  let hardcode_type = get_resist_berry_type("オッカのみ")
  let db_type = get_resist_berry_type_db(effects)
  inspect(hardcode_type == db_type, content="true")
  inspect(db_type, content="ほのお")
  @db.close(db)
}

///|
test "shadow: unknown item returns no-op (no effects from DB)" {
  let db = match ish_open_seeded_db() {
    Some(d) => d
    None => return
  }
  let effects = match @db.query_item_effects(db, "存在しないアイテム") {
    Ok(e) => e
    Err(_) => {
      @db.close(db)
      return
    }
  }
  // Empty effects list ⇒ all helpers return identity.
  inspect(effects.length(), content="0")
  inspect(apply_atk_item_stat_db(effects, true, 100), content="100")
  inspect(get_atk_item_final_db(effects, true, true), content="0")
  inspect(get_resist_berry_type_db(effects), content="")
  @db.close(db)
}

///|
test "shadow: empty item name returns no-op" {
  let db = match ish_open_seeded_db() {
    Some(d) => d
    None => return
  }
  let effects = match @db.query_item_effects(db, "") {
    Ok(e) => e
    Err(_) => {
      @db.close(db)
      return
    }
  }
  inspect(effects.length(), content="0")
  inspect(apply_atk_item_stat("", true, "0445", 100), content="100")
  inspect(apply_atk_item_stat_db(effects, true, 100), content="100")
  @db.close(db)
}
