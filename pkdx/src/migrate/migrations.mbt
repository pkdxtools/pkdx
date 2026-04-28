///|
/// Migrations that target `pokedex.db`. Today this is every existing
/// migration: even the Champions-flavoured ones (002, 003, 004, 005)
/// flow data into shared upstream tables (`pokedex` / `pokedex_name` /
/// `local_pokedex_waza` / `local_waza`) and then derive
/// `champions_learnset` from those rows. Splitting them out would
/// require either a cross-DB read in m005 or an upstream cleanup that's
/// out of scope here.
///
/// The split exists so future Champions-only tables (#94 items) can be
/// targeted at champions.db without touching pokedex.db at all.
pub fn migrations_pokedex() -> Array[Migration] {
  [
    { name: "001_mega_legendsza", run: run_001 },
    { name: "002_champions_pokemon", run: run_002 },
    { name: "003_champions_moves", run: run_003 },
    { name: "004_champions_learnset", run: run_004 },
    { name: "005_champions_learnset_normalize", run: run_005 },
    { name: "006_move_meta", run: run_006 },
    { name: "007_mega_forms", run: run_007 },
    { name: "008_move_meta_ailment", run: run_008 },
    { name: "010_move_meta_posthit", run: run_010 },
    { name: "011_form_name_aliases", run: run_011 },
    { name: "012_gender_symbol_aliases", run: run_012 },
  ]
}

///|
/// Migrations that target `champions.db`. P2-C (#94) ships
/// `013_items` here — the items / item_effect schema. Future
/// Champions-only tables append below.
pub fn migrations_champions() -> Array[Migration] {
  [{ name: "013_items", run: run_013 }]
}

///|
/// Combined migration list for legacy callers / tests that need a single
/// stream. The order matches the historical 001 → 013 chronology so
/// already-patched installs see the same sequence and `pkdx_migrations`
/// bookkeeping rows remain compatible.
///
/// New code should prefer `migrations_pokedex()` / `migrations_champions()`
/// directly so each DB only sees the migrations that target it.
pub fn migrations() -> Array[Migration] {
  let pdx = migrations_pokedex()
  let cmp = migrations_champions()
  // Concatenate then sort by name. The split lists each grow in
  // chronological order so a simple stable sort by `name` reconstructs
  // the original 001 → 013 sequence used by legacy bookkeeping.
  let combined : Array[Migration] = []
  for i = 0; i < pdx.length(); i = i + 1 {
    combined.push(pdx[i])
  }
  for i = 0; i < cmp.length(); i = i + 1 {
    combined.push(cmp[i])
  }
  // Insertion sort: stable, plenty fast for ≤ 20 items.
  for i = 1; i < combined.length(); i = i + 1 {
    let cur = combined[i]
    let mut j = i
    while j > 0 && string_lt(cur.name, combined[j - 1].name) {
      combined[j] = combined[j - 1]
      j = j - 1
    }
    combined[j] = cur
  }
  combined
}

///|
/// Lexicographic less-than for two strings. MoonBit's `<` on String does
/// not always behave lexicographically across Unicode boundaries, so we
/// compare explicitly per code unit. Migration names are ASCII so this
/// is straightforward.
fn string_lt(a : String, b : String) -> Bool {
  let la = a.length()
  let lb = b.length()
  let mut i = 0
  while i < la && i < lb {
    let ca = a.unsafe_get(i)
    let cb = b.unsafe_get(i)
    if ca < cb {
      return true
    }
    if ca > cb {
      return false
    }
    i = i + 1
  }
  la < lb
}

///|
/// The tail migration name across all DBs. Kept for backward compat with
/// existing damage cache fingerprint code; new code should call the
/// per-DB variants below so cache invalidation triggers when either
/// side advances.
pub fn latest_migration_name() -> String {
  let all = migrations()
  if all.length() == 0 {
    ""
  } else {
    all[all.length() - 1].name
  }
}

///|
/// The tail migration name on `pokedex.db`.
pub fn latest_migration_name_pokedex() -> String {
  let pdx = migrations_pokedex()
  if pdx.length() == 0 {
    ""
  } else {
    pdx[pdx.length() - 1].name
  }
}

///|
/// The tail migration name on `champions.db`.
pub fn latest_migration_name_champions() -> String {
  let cmp = migrations_champions()
  if cmp.length() == 0 {
    ""
  } else {
    cmp[cmp.length() - 1].name
  }
}

///|
/// Combined fingerprint used by the L2 damage cache to invalidate
/// entries when *either* DB advances. Format is
/// `<pokedex_latest>:<champions_latest>` — string equality on this
/// blob is enough for the existing `validate_and_sync_meta` flow, no
/// schema change in `damage_cache_meta` required. Empty
/// `champions_latest` (P1-B baseline, before #94 ships) still produces
/// a stable string, so opening a cache against an installation that
/// has only run pokedex migrations works without a forced wipe.
pub fn combined_migration_fingerprint() -> String {
  latest_migration_name_pokedex() + ":" + latest_migration_name_champions()
}
