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
    "id": e.id.to_json(),
    "no": e.no.to_json(),
    "globalNo": e.globalNo.to_json(),
    "form": e.form.to_json(),
    "name_jpn": e.name_jpn.to_json(),
    "pokedex": e.pokedex.to_json(),
    "type1": e.type1.to_json(),
    "type2": e.type2.to_json(),
    "hp": e.hp.to_json(),
    "attack": e.attack.to_json(),
    "defense": e.defense.to_json(),
    "special_attack": e.special_attack.to_json(),
    "special_defense": e.special_defense.to_json(),
    "speed": e.speed.to_json(),
    "ability1": e.ability1.to_json(),
    "ability2": e.ability2.to_json(),
    "dream_ability": e.dream_ability.to_json(),
  }
}

///|
fn move_to_json(e : MoveEntry) -> Json {
  {
    "waza": e.waza.to_json(),
    "type": e.type_.to_json(),
    "category": e.category.to_json(),
    "pp": e.pp.to_json(),
    "power": e.power.to_json(),
    "accuracy": e.accuracy.to_json(),
    "direct": e.direct.to_json(),
    "target": e.target.to_json(),
  }
}

///|
fn learnset_to_json(e : LearnsetEntry) -> Json {
  {
    "id": e.id.to_json(),
    "conditions": e.conditions.to_json(),
    "waza": e.waza.to_json(),
  }
}

///|
fn item_to_json(e : ItemEntry) -> Json {
  {
    "name_ja": e.name_ja.to_json(),
    "name_en": e.name_en.to_json(),
    "category": e.category.to_json(),
    "flavor": e.flavor.to_json(),
  }
}

///|
pub fn serialize_pokemon_entries(entries : Array[PokemonEntry]) -> Json {
  let arr : Array[Json] = []
  for i = 0; i < entries.length(); i = i + 1 {
    arr.push(pokemon_to_json(entries[i]))
  }
  arr.to_json()
}

///|
pub fn serialize_move_entries(entries : Array[MoveEntry]) -> Json {
  let arr : Array[Json] = []
  for i = 0; i < entries.length(); i = i + 1 {
    arr.push(move_to_json(entries[i]))
  }
  arr.to_json()
}

///|
pub fn serialize_learnset_entries(entries : Array[LearnsetEntry]) -> Json {
  let arr : Array[Json] = []
  for i = 0; i < entries.length(); i = i + 1 {
    arr.push(learnset_to_json(entries[i]))
  }
  arr.to_json()
}

///|
pub fn serialize_item_entries(entries : Array[ItemEntry]) -> Json {
  let arr : Array[Json] = []
  for i = 0; i < entries.length(); i = i + 1 {
    arr.push(item_to_json(entries[i]))
  }
  arr.to_json()
}
