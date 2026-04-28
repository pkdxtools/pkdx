///|
/// `items` / `item_effect` schema for champions.db (issue #94).
///
/// MVP scope (this migration):
///   - schema for items + item_effect
///   - seed 3 representative items, one per major effect_kind:
///     · こだわりハチマキ (stat_mod): physical Atk × 3/2
///     · いのちのたま   (final_mod): final damage × 5324/4096
///     · オッカのみ     (resist_berry): pre-damage × 2048/4096 vs ほのお
///
/// The full ~20-item parity with `damage/items.mbt` is a follow-up:
/// the schema is designed so additional rows can land without further
/// migration code. Apply order on `item_effect.apply_order` mirrors the
/// damage pipeline order:
///   0 = resist_berry / pre-damage modifiers
///   1 = power_mod (type plates, たつじんのおび-like power scalers)
///   2 = stat_mod (こだわり / きせき / チョッキ)
///   3 = final_mod (いのちのたま, ちからのハチマキ, etc.)
///
/// `item_effect.is_physical`: 1 = physical only, 0 = special only,
/// NULL = both. `super_effective_only`: 1 = effect gates on
/// super-effective hit (resist berries except ホズ; たつじんのおび).
pub fn run_013(db : @db.Db, _repo_root : String) -> Result[String, String] {
  match @db.exec(
      db,
      "CREATE TABLE IF NOT EXISTS items (" +
      "name_ja TEXT PRIMARY KEY, " +
      "name_en TEXT NOT NULL DEFAULT '', " +
      "category TEXT NOT NULL, " +
      "flavor TEXT NOT NULL DEFAULT '')",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // Composite uniqueness on (item_name, effect_kind, type_filter,
  // pokemon_filter, apply_order) is enforced by the migration's
  // DELETE-then-INSERT idempotence rather than a SQLite PRIMARY KEY —
  // PRIMARY KEY syntax cannot reference functions like COALESCE, and
  // NULL columns can't participate cleanly. Tracked: deferred to add
  // an explicit unique index in a follow-up that normalises NULLs to
  // empty strings up front.
  match @db.exec(
      db,
      "CREATE TABLE IF NOT EXISTS item_effect (" +
      "item_name TEXT NOT NULL, " +
      "effect_kind TEXT NOT NULL, " +
      "apply_order INTEGER NOT NULL, " +
      "num INTEGER, " +
      "den INTEGER, " +
      "type_filter TEXT, " +
      "pokemon_filter TEXT, " +
      "is_physical INTEGER, " +
      "super_effective_only INTEGER)",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // Idempotent reseed: clear the rows this migration owns so --resync
  // converges on the latest seed values.
  let owned : Array[String] = [
    "こだわりハチマキ", "いのちのたま", "オッカのみ", "きあいのタスキ", "フィラのみ",
  ]
  for i = 0; i < owned.length(); i = i + 1 {
    let name = owned[i]
    match @db.exec_binds(
        db, "DELETE FROM item_effect WHERE item_name = ?", [@db.BindText(name)],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match @db.exec_binds(
        db, "DELETE FROM items WHERE name_ja = ?", [@db.BindText(name)],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  // items rows
  let items_seed : Array[(String, String, String)] = [
    ("こだわりハチマキ", "Choice Band", "choice"),
    ("いのちのたま", "Life Orb", "misc"),
    ("オッカのみ", "Occa Berry", "berry"),
    ("きあいのタスキ", "Focus Sash", "consume"),
    ("フィラのみ", "Figy Berry", "berry"),
  ]
  for i = 0; i < items_seed.length(); i = i + 1 {
    let (ja, en, cat) = items_seed[i]
    match @db.exec_binds(
        db,
        "INSERT INTO items (name_ja, name_en, category, flavor) VALUES (?, ?, ?, '')",
        [@db.BindText(ja), @db.BindText(en), @db.BindText(cat)],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  // item_effect rows
  // こだわりハチマキ → stat_mod x3/2 on physical Atk
  match @db.exec_binds(
      db,
      "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES (?, 'stat_mod', 2, 3, 2, NULL, NULL, 1, 0)",
      [@db.BindText("こだわりハチマキ")],
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // いのちのたま → final_mod 5324/4096 on any move
  match @db.exec_binds(
      db,
      "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES (?, 'final_mod', 3, 5324, 4096, NULL, NULL, NULL, 0)",
      [@db.BindText("いのちのたま")],
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // オッカのみ → resist_berry 2048/4096 vs ほのお (super_effective only)
  match @db.exec_binds(
      db,
      "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES (?, 'resist_berry', 0, 2048, 4096, ?, NULL, NULL, 1)",
      [@db.BindText("オッカのみ"), @db.BindText("ほのお")],
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // きあいのタスキ → consume_on_hit (apply_order 4: post-damage)
  // num/den unused for this kind — post-damage HP=1 is hard-coded.
  match @db.exec_binds(
      db,
      "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES (?, 'consume_on_hit', 4, 0, 0, NULL, NULL, NULL, 0)",
      [@db.BindText("きあいのタスキ")],
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // フィラのみ → hp_threshold (apply_order 4: post-damage). num/den encode
  // the HP threshold (post-damage HP <= max * num/den triggers heal). Heal
  // fraction is hard-coded to max/3 in the engine — stays uniform across
  // the four フィラ-class berries (ウタン / イア / マゴ / バンジ).
  match @db.exec_binds(
      db,
      "INSERT INTO item_effect (item_name, effect_kind, apply_order, num, den, type_filter, pokemon_filter, is_physical, super_effective_only) VALUES (?, 'hp_threshold', 4, 1, 2, NULL, NULL, NULL, 0)",
      [@db.BindText("フィラのみ")],
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(
    "Seeded " +
    items_seed.length().to_string() +
    " items / item_effect rows in champions.db",
  )
}
