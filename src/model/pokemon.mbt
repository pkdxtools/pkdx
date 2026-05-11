///|
pub(all) struct Pokemon {
  global_no : String
  name_ja : String
  name_en : String
  type1 : String
  type2 : String
  hp : Int
  atk : Int
  def_ : Int
  spa : Int
  spd : Int
  spe : Int
  bst : Int
  ability1 : String
  ability2 : String
  dream_ability : String
  // 体重 (kg)。けたぐり/くさむすび/ヘビーボンバー/ヒートスタンプの威力計算に使用。
  // DBに値が無い場合は 0.0。
  weight : Double
  // 原種 (base form) を引いた時に、同 globalNo で該当 version に存在する
  // フォーム別ポケモンの一意名一覧 (jpn)。フォーム直引き時および形態無しは
  // 空配列。SKILL が「原種→forms[]→特化名で再query」の発見フローで使う。
  // JSON 出力時は空配列ならキーごと省略される (pokemon_to_json 参照)。
  forms : Array[String]
} derive(Show, Eq)

///|
/// メガ進化後の差分を保持する。HP は進化で変化しないため含めない
/// (最大HP/残HP整合性を壊さない)。type2 は空文字列なら単タイプ扱い。
pub(all) struct MegaForm {
  atk : Int
  def_ : Int
  spa : Int
  spd : Int
  spe : Int
  type1 : String
  type2 : String
  ability : String
  name_ja : String
} derive(Show, Eq)
