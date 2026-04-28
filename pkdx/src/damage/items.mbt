///|
/// Apply attacker item stat modifier.
pub fn apply_atk_item_stat(
  item : String,
  is_physical : Bool,
  global_no : String,
  atk_stat : Int,
) -> Int {
  match item {
    "こだわりハチマキ" =>
      if is_physical {
        atk_stat * 3 / 2
      } else {
        atk_stat
      }
    "こだわりメガネ" =>
      if !is_physical {
        atk_stat * 3 / 2
      } else {
        atk_stat
      }
    "ふといホネ" =>
      if is_physical && (global_no == "0104" || global_no == "0105") {
        atk_stat * 2
      } else {
        atk_stat
      }
    "でんきだま" =>
      if global_no == "0025" {
        atk_stat * 2
      } else {
        atk_stat
      }
    _ => atk_stat
  }
}

///|
/// Apply defender item stat modifier.
pub fn apply_def_item_stat(
  item : String,
  is_physical : Bool,
  def_stat : Int,
) -> Int {
  match item {
    "しんかのきせき" => def_stat * 3 / 2
    "とつげきチョッキ" =>
      if !is_physical {
        def_stat * 3 / 2
      } else {
        def_stat
      }
    _ => def_stat
  }
}

///|
/// Get type boost from item. Returns multiplied power if item matches move type.
pub fn apply_type_boost_item(
  item : String,
  move_type : String,
  power : Int,
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

///|
/// Get attacker item final modifier (4096 base).
pub fn get_atk_item_final(
  item : String,
  is_physical : Bool,
  is_super_effective : Bool,
) -> Int {
  match item {
    "いのちのたま" => 5324
    "たつじんのおび" => if is_super_effective { 4915 } else { 0 }
    "ちからのハチマキ" => if is_physical { 4505 } else { 0 }
    "ものしりメガネ" => if !is_physical { 4505 } else { 0 }
    _ => 0
  }
}

///|
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

///|
/// Contact-induced status procs from a held item — defender side.
/// Returns one or more `(StatusKind, chance%)` entries the item inflicts
/// on the attacker when struck by a contact move; empty array for
/// non-procking items. Mirrors `contact_proc_ability`'s shape so the
/// payoff layer's fanout treats abilities and items uniformly.
///
/// とびだすハバネロ / とびだすなかみ are 100% triggers per Showdown
/// spec, so the chance node always produces a single Burn / Paralyze
/// outcome with probability 1.0.
pub fn contact_proc_item(
  name : String,
) -> Array[(@model.StatusKind, Int)] {
  match name {
    "とびだすハバネロ" => [(@model.BurnKind, 100)]
    "とびだすなかみ" => [(@model.ParalyzeKind, 100)]
    _ => []
  }
}

///|
/// `move_type` super-effective against (`def_type1`, `def_type2`)? Used by
/// the payoff layer to gate resist berry triggers (#97 / P5). Empty
/// `def_type2` means single-typed defender. Returns `false` if a type name
/// fails to resolve in the chart (immune-or-unknown is conservative).
pub fn is_super_effective(
  move_type : String,
  def_type1 : String,
  def_type2 : String,
) -> Bool {
  let atk = match @types.type_from_jp(move_type) {
    Some(t) => t
    None => return false
  }
  let d1 = match @types.type_from_jp(def_type1) {
    Some(t) => t
    None => return false
  }
  let e1 = @types.get_effectiveness_x4(atk, d1)
  let e2 = if def_type2.length() > 0 {
    match @types.type_from_jp(def_type2) {
      Some(t) => @types.get_effectiveness_x4(atk, t)
      None => 4
    }
  } else {
    4
  }
  e1 * e2 > 16
}
