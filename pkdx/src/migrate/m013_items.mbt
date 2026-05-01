///|
/// Champions アイテムデータの投入は champions.db 側の m018 で行うように
/// 切り替えた。本 migration は履歴維持のための no-op。
/// item_effect の seed 行 (オッカのみ / きあいのタスキ 等) は m018 で
/// Champions 在庫と整合的に再シードされる。
pub fn run_013(_db : @db.Db, _repo_root : String) -> Result[String, String] {
  Ok("noop: superseded by m018_champions_items (champions.db)")
}
