///|
/// `champions.db` のテーブル定義を pkdx 側で宣言する SSoT。
/// アダプター層・migration・クエリ層がここの宣言にだけ依存し、
/// 入力ソース (champout) のスキーマ変動は `champout_adapter/` 内に封じ込める。
///
/// 設計原則:
///   - id 体系は champout 由来の 7 桁 (`<globalNo:4><form:3>`)。pokedex.db
///     との互換性は持たない (champions.db は完全分離)
///   - `form` 1 カラムに表示名 (例: `"メガガルーラ"`, `"アローラ"`) を統合し、
///     region / mega_evolution / gigantamax の歴史的細分カラムは廃止
///   - 種族値・タイプ・特性は `pokemon` 1 テーブルに集約
///   - 多言語名は `pokemon_name` / `move_name` にぶら下げる (現状 jpn のみ
///     登録、後で eng 拡張可能)
///   - `items` / `item_effect` は #94 の m013 スキーマを継承する。effect 側
///     はダメージ計算ロジックと結合しており champout 由来データだけでは
///     生成できないので、別 migration の責務として分離する

///|
/// champions.db に必要な CREATE TABLE / CREATE INDEX を列挙する。
/// すべて IF NOT EXISTS で記述してあるので、適用順は外部に対する保証では
/// なく単なる読みやすさ。`pkdx migrate` が champions.db を open or create
/// した直後に流す想定。
pub fn champions_ddl() -> Array[String] {
  [
    "CREATE TABLE IF NOT EXISTS pokemon (" +
    "id TEXT PRIMARY KEY, " +
    "no TEXT NOT NULL, " +
    "global_no TEXT NOT NULL, " +
    "form TEXT NOT NULL DEFAULT '', " +
    "pokedex TEXT NOT NULL, " +
    "type1 TEXT NOT NULL, " +
    "type2 TEXT NOT NULL DEFAULT '', " +
    "hp INTEGER NOT NULL, " +
    "attack INTEGER NOT NULL, " +
    "defense INTEGER NOT NULL, " +
    "special_attack INTEGER NOT NULL, " +
    "special_defense INTEGER NOT NULL, " +
    "speed INTEGER NOT NULL, " +
    "ability1 TEXT NOT NULL DEFAULT '', " +
    "ability2 TEXT NOT NULL DEFAULT '', " +
    "dream_ability TEXT NOT NULL DEFAULT ''" +
    ")",
    "CREATE INDEX IF NOT EXISTS idx_pokemon_global_no ON pokemon(global_no)",
    // PK が (id, language, name) なのは alias を持たせるため。一つの id /
    // language に対して複数の表示名 (例: M base 行に "イダイトウ" と
    // "イダイトウ（オス）" の 2 行) を許す構造。query は `WHERE name = ?`
    // で照合し、forms[] 列挙時は per-id で合成 alias を優先する SELECT
    // (query_champions_forms) で 1 行に絞る。
    "CREATE TABLE IF NOT EXISTS pokemon_name (" +
    "id TEXT NOT NULL, " +
    "language TEXT NOT NULL, " +
    "name TEXT NOT NULL, " +
    "PRIMARY KEY (id, language, name)" +
    ")",
    "CREATE INDEX IF NOT EXISTS idx_pokemon_name_name ON pokemon_name(name)",
    // direct / target は champout 由来。direct=1 が接触、target は range
    // enum (詳細は champions_schema/types.mbt の MoveEntry コメント参照)。
    "CREATE TABLE IF NOT EXISTS move (" +
    "waza TEXT PRIMARY KEY, " +
    "type TEXT NOT NULL, " +
    "category TEXT NOT NULL, " +
    "pp TEXT NOT NULL, " +
    "power TEXT NOT NULL, " +
    "accuracy TEXT NOT NULL, " +
    "direct INTEGER NOT NULL DEFAULT 0, " +
    "target INTEGER NOT NULL DEFAULT 0" +
    ")",
    "CREATE TABLE IF NOT EXISTS move_name (" +
    "waza TEXT NOT NULL, " +
    "language TEXT NOT NULL, " +
    "name TEXT NOT NULL, " +
    "description TEXT, " +
    "PRIMARY KEY (waza, language)" +
    ")",
    "CREATE TABLE IF NOT EXISTS learnset (" +
    "id TEXT NOT NULL, " +
    "waza TEXT NOT NULL, " +
    "conditions TEXT NOT NULL DEFAULT '', " +
    "PRIMARY KEY (id, waza)" +
    ")",
    "CREATE INDEX IF NOT EXISTS idx_learnset_waza ON learnset(waza)",
    "CREATE TABLE IF NOT EXISTS items (" +
    "name_ja TEXT PRIMARY KEY, " +
    "name_en TEXT NOT NULL DEFAULT '', " +
    "category TEXT NOT NULL, " +
    "flavor TEXT NOT NULL DEFAULT ''" +
    ")",
    "CREATE TABLE IF NOT EXISTS item_effect (" +
    "item_name TEXT NOT NULL, " +
    "effect_kind TEXT NOT NULL, " +
    "apply_order INTEGER NOT NULL, " +
    "num INTEGER, " +
    "den INTEGER, " +
    "type_filter TEXT, " +
    "pokemon_filter TEXT, " +
    "is_physical INTEGER, " +
    "super_effective_only INTEGER" +
    ")",
  ]
}

///|
/// `champions_ddl()` を順に流す。`pkdx migrate` の champions.db 初期化
/// ステップから呼ぶ想定。SQLite は CREATE TABLE IF NOT EXISTS が冪等なので、
/// 何度走らせても安全。
pub fn apply_ddl(db : @db.Db) -> Result[Unit, String] {
  let stmts = champions_ddl()
  for i = 0; i < stmts.length(); i = i + 1 {
    match @db.exec(db, stmts[i]) {
      Err(e) => return Err("DDL failed at stmt " + i.to_string() + ": " + e)
      Ok(_) => ()
    }
  }
  Ok(())
}
