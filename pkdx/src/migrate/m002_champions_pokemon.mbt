///|
/// Champions ポケモンデータの投入は champions.db 側の m015 で行うように
/// 切り替えた。本 migration は履歴 (pkdx_migrations) を維持するための
/// no-op として残す。pokedex.db 側に積まれていた `local_pokedex*`
/// (`version='champions'`) 行は m019 の purge migration がまとめて削除する。
pub fn run_002(_db : @db.Db, _repo_root : String) -> Result[String, String] {
  Ok("noop: superseded by m015_champions_pokemon (champions.db)")
}
