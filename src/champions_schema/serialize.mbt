///|
/// `types.mbt` のエンティティ型を中間 JSON 形式 (`pkdx_patch/00X_*/data.json`)
/// にシリアライズする。`validate.mbt` の parse の逆方向。アダプター層が
/// 生成した PokemonEntry / MoveEntry / LearnsetEntry / ItemEntry の配列を
/// `pkdx db init` がここで JSON 文字列に直し、ファイルに書き出す。
///
/// パース→シリアライズのラウンドトリップでフィールドが保たれる前提を
/// `schema_test.mbt` で担保する。

///|
fn pokemon_to_json(e : PokemonEntry) -> Json {
  {
    "id": Json(e.id),
    "no": Json(e.no),
    "globalNo": Json(e.globalNo),
    "form": Json(e.form),
    "name_jpn": Json(e.name_jpn),
    "pokedex": Json(e.pokedex),
    "type1": Json(e.type1),
    "type2": Json(e.type2),
    "hp": Json(e.hp),
    "attack": Json(e.attack),
    "defense": Json(e.defense),
    "special_attack": Json(e.special_attack),
    "special_defense": Json(e.special_defense),
    "speed": Json(e.speed),
    "ability1": Json(e.ability1),
    "ability2": Json(e.ability2),
    "dream_ability": Json(e.dream_ability),
  }
}

///|
fn move_to_json(e : MoveEntry) -> Json {
  {
    "waza": Json(e.waza),
    "type": Json(e.type_),
    "category": Json(e.category),
    "pp": Json(e.pp),
    "power": Json(e.power),
    "accuracy": Json(e.accuracy),
    "direct": Json(e.direct),
    "target": Json(e.target),
  }
}

///|
fn learnset_to_json(e : LearnsetEntry) -> Json {
  {
    "id": Json(e.id),
    "conditions": Json(e.conditions),
    "waza": Json(e.waza),
  }
}

///|
fn item_to_json(e : ItemEntry) -> Json {
  {
    "name_ja": Json(e.name_ja),
    "name_en": Json(e.name_en),
    "category": Json(e.category),
    "flavor": Json(e.flavor),
  }
}

///|
pub fn serialize_pokemon_entries(entries : Array[PokemonEntry]) -> Json {
  Json(entries.map(pokemon_to_json))
}

///|
pub fn serialize_move_entries(entries : Array[MoveEntry]) -> Json {
  Json(entries.map(move_to_json))
}

///|
pub fn serialize_learnset_entries(entries : Array[LearnsetEntry]) -> Json {
  Json(entries.map(learnset_to_json))
}

///|
pub fn serialize_item_entries(entries : Array[ItemEntry]) -> Json {
  Json(entries.map(item_to_json))
}
