///|
/// Champions 技習得データの投入は champions.db 側の m017 で行うように
/// 切り替えた。本 migration は履歴維持のための no-op。
pub fn run_004(_db : @db.Db, _repo_root : String) -> Result[String, String] {
  Ok("noop: superseded by m017_champions_learnset (champions.db)")
}
