///|
/// champions.db に新スキーマ (`champions_schema.champions_ddl()`) を適用する。
/// 後続の m015〜m018 が依存する pokemon / pokemon_name / move / move_name /
/// learnset / items / item_effect テーブルをここで作る。冪等。
pub fn run_008(db : @db.Db, _repo_root : String) -> Result[String, String] {
  match @champions_schema.apply_ddl(db) {
    Err(e) => Err(e)
    Ok(_) => Ok("Applied champions.db schema (10 statements)")
  }
}
