///|
/// 旧 SSoT 由来 learnset に紛れていた取得不可能技の正規化を担っていた
/// migration。新 SSoT (champout) はゲーム内データそのものなので没収技混入が
/// 発生せず、正規化は不要になった。本 migration は履歴維持のための no-op。
pub fn run_005(_db : @db.Db, _repo_root : String) -> Result[String, String] {
  Ok("noop: champout-derived learnset needs no rogue-move normalization")
}
