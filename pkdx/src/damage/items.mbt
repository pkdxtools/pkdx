/// Apply attacker item stat modifier.
pub fn apply_atk_item_stat(
  item : String,
  is_physical : Bool,
  global_no : String,
  atk_stat : Int
) -> Int {
  match item {
    "こだわりハチマキ" => if is_physical { atk_stat * 3 / 2 } else { atk_stat }
    "こだわりメガネ" => if not(is_physical) { atk_stat * 3 / 2 } else { atk_stat }
    "ふといホネ" =>
      if is_physical && (global_no == "0104" || global_no == "0105") {
        atk_stat * 2
      } else {
        atk_stat
      }
    "でんきだま" =>
      if global_no == "0025" { atk_stat * 2 } else { atk_stat }
    _ => atk_stat
  }
}

/// Apply defender item stat modifier.
pub fn apply_def_item_stat(
  item : String,
  is_physical : Bool,
  def_stat : Int
) -> Int {
  match item {
    "しんかのきせき" => def_stat * 3 / 2
    "とつげきチョッキ" =>
      if not(is_physical) { def_stat * 3 / 2 } else { def_stat }
    _ => def_stat
  }
}

/// Get type boost from item. Returns multiplied power if item matches move type.
pub fn apply_type_boost_item(
  item : String,
  move_type : String,
  power : Int
) -> Int {
  let boost_type = match item {
    "もえさかるプレート" | "もくたん" => "ほのお"
    "しずくプレート" | "しんぴのしずく" => "みず"
    "みどりのプレート" | "きせきのタネ" => "くさ"
    "じしゃく" => "でんき"
    "つららのプレート" | "とけないこおり" => "こおり"
    "こぶしのプレート" | "くろおび" => "かくとう"
    "もうどくプレート" | "どくバリ" => "どく"
    "だいちのプレート" | "やわらかいすな" => "じめん"
    "あおぞらプレート" | "するどいくちばし" => "ひこう"
    "ふしぎのプレート" | "まがったスプーン" => "エスパー"
    "たまむしプレート" | "ぎんのこな" => "むし"
    "がんせきプレート" | "かたいいし" => "いわ"
    "もののけプレート" | "のろいのおふだ" => "ゴースト"
    "りゅうのプレート" | "りゅうのキバ" => "ドラゴン"
    "こわもてプレート" | "くろいメガネ" => "あく"
    "こうてつプレート" | "メタルコート" => "はがね"
    "せいれいプレート" => "フェアリー"
    "シルクのスカーフ" => "ノーマル"
    _ => ""
  }
  if boost_type.length() > 0 && boost_type == move_type {
    power * 12 / 10
  } else {
    power
  }
}

/// Get attacker item final modifier (4096 base).
pub fn get_atk_item_final(
  item : String,
  is_physical : Bool,
  is_super_effective : Bool
) -> Int {
  match item {
    "いのちのたま" => 5324
    "たつじんのおび" => if is_super_effective { 4915 } else { 0 }
    "ちからのハチマキ" => if is_physical { 4505 } else { 0 }
    "ものしりメガネ" => if not(is_physical) { 4505 } else { 0 }
    _ => 0
  }
}

/// Get resist berry type. Returns empty string if not a resist berry.
pub fn get_resist_berry_type(item : String) -> String {
  match item {
    "オッカのみ" => "ほのお"
    "イトケのみ" => "みず"
    "リンドのみ" => "くさ"
    "ヤチェのみ" => "こおり"
    "ヨプのみ" => "かくとう"
    "ビアーのみ" => "どく"
    "シュカのみ" => "じめん"
    "バコウのみ" => "ひこう"
    "ウタンのみ" => "エスパー"
    "タンガのみ" => "むし"
    "ヨロギのみ" => "いわ"
    "カシブのみ" => "ゴースト"
    "ハバンのみ" => "ドラゴン"
    "ナモのみ" => "あく"
    "リリバのみ" => "はがね"
    "ロゼルのみ" => "フェアリー"
    "ホズのみ" => "ノーマル"
    _ => ""
  }
}
