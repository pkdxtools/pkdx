///|
/// Ordered list of migrations. Names mirror the old pkdx_patch directory
/// names so `pkdx_migrations` rows survive the Ruby→MoonBit port and
/// already-patched installs skip cleanly without re-applying.
pub fn migrations() -> Array[Migration] {
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
  ]
}
