///|
/// Champions 技データの投入は champions.db 側の m016 で行うように
/// 切り替えた。本 migration は履歴維持のための no-op。
pub fn run_003(_db : @db.Db, _repo_root : String) -> Result[String, String] {
  Ok("noop: superseded by m016_champions_moves (champions.db)")
}
