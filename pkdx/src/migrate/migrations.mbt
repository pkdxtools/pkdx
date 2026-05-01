///|
/// Migrations that target `pokedex.db`.
///
/// 過去に Champions マスターデータを pokedex.db に書いていた移行と、その
/// purge を担っていた cleanup migration はすべて削除済み。Champions の
/// マスターデータは champions.db 側で完結する。upstream pokedex.db には
/// Champions メガ行が残っているが、クエリ層は `version='champions'` のとき
/// champions.db を読むため無害。気になる場合は `rm pokedex/pokedex.db &&
/// ./setup.sh` で fresh な upstream に戻せる。
pub fn migrations_pokedex() -> Array[Migration] {
  [
    { name: "001_mega_legendsza", run: run_001 },
    { name: "002_move_meta", run: run_002 },
    { name: "003_mega_forms", run: run_003 },
    { name: "004_move_meta_ailment", run: run_004 },
    { name: "005_move_meta_posthit", run: run_005 },
    { name: "006_form_name_aliases", run: run_006 },
    { name: "007_gender_symbol_aliases", run: run_007 },
  ]
}

///|
/// Migrations that target `champions.db`. m008 が DDL を流し、m009〜m012 が
/// pkdx_patch 配下の中間 JSON (champout adapter 出力) を投入し、m013 が
/// form / gender 合成 alias を pokemon_name に投入する。
pub fn migrations_champions() -> Array[Migration] {
  [
    { name: "008_champions_init_schema", run: run_008 },
    { name: "009_champions_pokemon", run: run_009 },
    { name: "010_champions_moves", run: run_010 },
    { name: "011_champions_learnset", run: run_011 },
    { name: "012_champions_items", run: run_012 },
    { name: "013_champions_form_aliases", run: run_013 },
  ]
}

///|
/// Combined migration list (pokedex first, champions next) for callers
/// that need a single stream — typically tests. Each DB has its own
/// dedicated entry point (`migrations_pokedex` / `migrations_champions`)
/// because mixing them on one connection would pull tables that don't
/// belong there.
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
  combined
}
