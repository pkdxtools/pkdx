///|
/// Migrations that target `pokedex.db`.
///
/// Champions マスターデータ (002〜005) と m013_items はかつて pokedex.db に
/// 書き込んでいたが、champout を SSoT に切り替えた段階で champions.db 側の
/// 新 migration (m014〜m018) に役割を譲り、ここでは履歴維持のため no-op
/// として残してある。pokedex.db に残った旧データは m019 が一括で掃除する。
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
    { name: "013_items", run: run_013 },
    { name: "019_pokedex_purge_champions", run: run_019 },
  ]
}

///|
/// Migrations that target `champions.db`. m014 が DDL を流し、m015〜m018 が
/// pkdx_patch 配下の中間 JSON (champout adapter 出力) を投入する。
pub fn migrations_champions() -> Array[Migration] {
  [
    { name: "014_champions_init_schema", run: run_014 },
    { name: "015_champions_pokemon", run: run_015 },
    { name: "016_champions_moves", run: run_016 },
    { name: "017_champions_learnset", run: run_017 },
    { name: "018_champions_items", run: run_018 },
  ]
}

///|
/// Combined migration list for legacy callers / tests that need a single
/// stream. The order matches the historical chronology so already-patched
/// installs see the same sequence and `pkdx_migrations` bookkeeping rows
/// remain compatible.
///
/// New code should prefer `migrations_pokedex()` / `migrations_champions()`
/// directly so each DB only sees the migrations that target it.
pub fn migrations() -> Array[Migration] {
  let pdx = migrations_pokedex()
  let cmp = migrations_champions()
  let combined : Array[Migration] = []
  for i = 0; i < pdx.length(); i = i + 1 {
    combined.push(pdx[i])
  }
  for i = 0; i < cmp.length(); i = i + 1 {
    combined.push(cmp[i])
  }
  // Insertion sort: stable, plenty fast for ≤ 30 items.
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
/// schema change in `damage_cache_meta` required.
pub fn combined_migration_fingerprint() -> String {
  latest_migration_name_pokedex() + ":" + latest_migration_name_champions()
}
