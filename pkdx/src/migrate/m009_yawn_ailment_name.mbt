///|
/// あくびは仕様上「遅延ねむり」で DrowsyKind に対応させるため、008 が
/// "ねむり" として入れていた ailment_ja を "あくび" に上書きする。
pub fn run_009(db : @db.Db, _repo_root : String) -> Result[String, String] {
  match @db.exec_binds(
      db,
      "UPDATE move_meta SET ailment_ja = 'あくび' WHERE name_ja = 'あくび'",
      [],
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok("yawn ailment_ja normalized to 'あくび'")
}
