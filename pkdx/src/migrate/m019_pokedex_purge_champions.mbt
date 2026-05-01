///|
/// pokedex.db に積まれていた Champions 由来データを完全に取り除く cleanup。
/// 旧 m002〜m005 が `local_pokedex*` / `local_waza*` / `local_pokedex_waza` /
/// `champions_learnset` に書き込んでいた行と、それを保持していたテーブル
/// (champions_learnset 単独テーブル) を削除する。
///
/// 既存ユーザーの pokedex.db には旧データが残っている可能性があるので
/// 1 回だけ走らせて掃除する。新規ユーザーは何もない pokedex.db に対して
/// 削除するだけなので空振りで完了する。冪等。
///
/// pokedex / pokedex_name には触らない: これらは upstream submodule
/// (towakey/pokedex) の正規データを保持するテーブルで、Champions 由来
/// データの混入があった場合でも次の upstream sync で上書きされる想定。
pub fn run_019(db : @db.Db, _repo_root : String) -> Result[String, String] {
  let local_tables = [
    "local_pokedex", "local_pokedex_status", "local_pokedex_type", "local_pokedex_ability",
  ]
  for i = 0; i < local_tables.length(); i = i + 1 {
    match @db.exec_binds(
        db,
        "DELETE FROM " + local_tables[i] + " WHERE version = ?",
        [@db.BindText("champions")],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  let waza_tables = ["local_waza", "local_waza_language", "local_pokedex_waza"]
  for i = 0; i < waza_tables.length(); i = i + 1 {
    match @db.exec_binds(
        db,
        "DELETE FROM " + waza_tables[i] + " WHERE version = ?",
        [@db.BindText("Champions")],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  // champions_learnset は旧 m005 が pokedex.db 内に作っていた専用テーブル。
  // 新スキーマでは champions.db.learnset に置き換えるので不要。
  match @db.exec(db, "DROP TABLE IF EXISTS champions_learnset") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok("Purged Champions-derived rows from pokedex.db")
}
