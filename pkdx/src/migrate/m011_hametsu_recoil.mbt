///|
/// はめつのひかり (Light of Ruin, 1/2 recoil) が 010 の data.json 初版に
/// 含まれていなかったため、既存ユーザーの move_meta に recoil_num/den を
/// upsert する。未登録なら最低限のカラムで insert。既存なら recoil のみ更新。
pub fn run_011(db : @db.Db, _repo_root : String) -> Result[String, String] {
  let rows = match @db.query_binds(
      db,
      "SELECT 1 FROM move_meta WHERE name_ja = ? LIMIT 1",
      [@db.BindText("はめつのひかり")],
    ) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  if rows.length() > 0 {
    match @db.exec_binds(
        db,
        "UPDATE move_meta SET recoil_num = ?, recoil_den = ? WHERE name_ja = ?",
        [@db.BindInt(1), @db.BindInt(2), @db.BindText("はめつのひかり")],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    Ok("はめつのひかり recoil updated (1/2)")
  } else {
    match @db.exec_binds(
        db,
        "INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance, recoil_num, recoil_den, self_ko, recharge) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText("はめつのひかり"),
          @db.BindInt(0),
          @db.BindText("[]"),
          @db.BindText(""),
          @db.BindInt(100),
          @db.BindInt(1),
          @db.BindInt(2),
          @db.BindInt(0),
          @db.BindInt(0),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    Ok("はめつのひかり inserted with recoil 1/2")
  }
}
