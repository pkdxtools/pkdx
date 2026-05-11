///|
/// 中間 JSON (`pkdx_patch/00X_*/data.json`) のレコード型を pkdx 側で宣言。
/// アダプター層の出力 / migration の入力 / テストフィクスチャがすべて
/// この型に対して書かれることで、champout 側の生フォーマット変動から
/// 内部実装を切り離す。
///
/// id 体系は champout 由来の 7 桁 (`<globalNo:4><form:3>`) を採用。
/// pokedex.db 側の歴史的複合キー (`<globalNo>_<8桁>_<form_byte>_000_0`) と
/// は互換性なし — champions.db は pokedex.db から完全分離して運用する。
/// region / mega_evolution / gigantamax の細分カラムも持たず、これらは
/// すべて `form` 1 カラムの表示名 (例: `"メガガルーラ"`, `"アローラ"`) に統合する。

///|
/// Champions ポケモンエントリ。`002_champions_pokemon/data.json` の各要素。
/// `name_jpn` は表示用の日本語名 (例: "リザードン", "メガリザードンX") で、
/// 通常フォームでは base name、Mega/別フォームでは `form` 文字列が入る。
pub(all) struct PokemonEntry {
  id : String
  no : String
  globalNo : String
  form : String
  name_jpn : String
  pokedex : String
  type1 : String
  type2 : String
  hp : Int
  attack : Int
  defense : Int
  special_attack : Int
  special_defense : Int
  speed : Int
  ability1 : String
  ability2 : String
  dream_ability : String
} derive(Show, Eq)

///|
/// Champions 技エントリ。`010_champions_moves/data.json` の各要素。
/// pp / power / accuracy が String なのは `"-"` (該当なし) を含むため。
/// `direct` は接触フラグ (1 = 接触 / 0 = 非接触)。`target` は range enum
/// (champout 由来の整数文字列):
///   0  単体 / 1-2  味方単体 / 4  自分以外全体 / 5  相手全体 / 6  味方全体
///   7  自分 / 8  全員 / 9  ランダム相手 / 10 フィールド全体
///   11 敵側設置 / 12 味方側設置 / 13 カウンター系 / 14 隣接味方
/// `direct` / `target` ともに champout `masterdata/waza.json` の同名
/// フィールドをそのまま転記する。
pub(all) struct MoveEntry {
  waza : String
  type_ : String
  category : String
  pp : String
  power : String
  accuracy : String
  direct : String
  target : String
} derive(Show, Eq)

///|
/// Champions 技習得エントリ。`004_champions_learnset/data.json` の各要素。
/// `id` は `PokemonEntry.id` と同じ体系で参照される。conditions は
/// 取得経路の自由文字列 ("基本" / "Lv1" / "わざマシン" 等)。
pub(all) struct LearnsetEntry {
  id : String
  conditions : String
  waza : String
} derive(Show, Eq)

///|
/// Champions アイテムエントリ。`013_items/data.json` の各要素。
/// effect 系 (item_effect) は damage 計算ロジックと結合しているため
/// 中間 JSON では持たず、別途 migration が手書き seed する。
pub(all) struct ItemEntry {
  name_ja : String
  name_en : String
  category : String
  flavor : String
} derive(Show, Eq)
