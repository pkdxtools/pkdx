///|
/// 中間 JSON (`pkdx_patch/00X_*/data.json`) を `types.mbt` のエンティティ
/// 型へパースする。各 `parse_*_entries` は配列トップレベルの JSON を受け取り、
/// 必須フィールド欠落・型不一致をエラーとして報告する。アダプター側で生成
/// した中間 JSON が読み戻せることをラウンドトリップテストで担保する。
///
/// 文字列フィールドは欠落時に `""` を許容する (歴史的な空値表現と整合)。
/// 整数フィールドの欠落は明示エラーにし、`int_field` のデフォルト値で
/// 黙って 0 を入れない (種族値 0 のポケモンは存在しないので、欠落は
/// データバグとして検出させる)。

///|
fn obj_str(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn obj_int_required(
  obj : Map[String, Json],
  key : String,
  ctx : String,
) -> Result[Int, String] {
  match obj.get(key) {
    Some(Number(n, ..)) => Ok(n.to_int())
    Some(_) => Err(ctx + ": field '" + key + "' has non-numeric value")
    None => Err(ctx + ": missing required integer field '" + key + "'")
  }
}

///|
fn obj_str_required(
  obj : Map[String, Json],
  key : String,
  ctx : String,
) -> Result[String, String] {
  match obj.get(key) {
    Some(String(s)) => Ok(s)
    Some(_) => Err(ctx + ": field '" + key + "' has non-string value")
    None => Err(ctx + ": missing required string field '" + key + "'")
  }
}

///|
fn expect_array(json : Json) -> Result[Array[Json], String] {
  match json {
    Array(a) => Ok(a)
    _ => Err("expected top-level JSON array")
  }
}

///|
fn expect_object(
  json : Json,
  ctx : String,
) -> Result[Map[String, Json], String] {
  match json {
    Object(m) => Ok(m)
    _ => Err(ctx + ": expected JSON object")
  }
}

///|
/// `002_champions_pokemon/data.json` をパース。
pub fn parse_pokemon_entries(
  json : Json,
) -> Result[Array[PokemonEntry], String] {
  let arr = match expect_array(json) {
    Err(e) => return Err(e)
    Ok(a) => a
  }
  let out : Array[PokemonEntry] = []
  for i = 0; i < arr.length(); i = i + 1 {
    let ctx = "pokemon[" + i.to_string() + "]"
    let m = match expect_object(arr[i], ctx) {
      Err(e) => return Err(e)
      Ok(o) => o
    }
    let id = match obj_str_required(m, "id", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let no = match obj_str_required(m, "no", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let global_no = match obj_str_required(m, "globalNo", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let pokedex = match obj_str_required(m, "pokedex", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let name_jpn = match obj_str_required(m, "name_jpn", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let type1 = match obj_str_required(m, "type1", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let hp = match obj_int_required(m, "hp", ctx) {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let atk = match obj_int_required(m, "attack", ctx) {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let dfn = match obj_int_required(m, "defense", ctx) {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let spa = match obj_int_required(m, "special_attack", ctx) {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let spd = match obj_int_required(m, "special_defense", ctx) {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let spe = match obj_int_required(m, "speed", ctx) {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    out.push({
      id,
      no,
      globalNo: global_no,
      form: obj_str(m, "form"),
      name_jpn,
      pokedex,
      type1,
      type2: obj_str(m, "type2"),
      hp,
      attack: atk,
      defense: dfn,
      special_attack: spa,
      special_defense: spd,
      speed: spe,
      ability1: obj_str(m, "ability1"),
      ability2: obj_str(m, "ability2"),
      dream_ability: obj_str(m, "dream_ability"),
    })
  }
  Ok(out)
}

///|
/// `003_champions_moves/data.json` をパース。
pub fn parse_move_entries(json : Json) -> Result[Array[MoveEntry], String] {
  let arr = match expect_array(json) {
    Err(e) => return Err(e)
    Ok(a) => a
  }
  let out : Array[MoveEntry] = []
  for i = 0; i < arr.length(); i = i + 1 {
    let ctx = "move[" + i.to_string() + "]"
    let m = match expect_object(arr[i], ctx) {
      Err(e) => return Err(e)
      Ok(o) => o
    }
    let waza = match obj_str_required(m, "waza", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let ty = match obj_str_required(m, "type", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let category = match obj_str_required(m, "category", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let pp = match obj_str_required(m, "pp", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let power = match obj_str_required(m, "power", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let accuracy = match obj_str_required(m, "accuracy", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    // direct / target は champout 由来の追加フィールド。後方互換のため
    // 欠落時は "0" にフォールバック (旧フォーマットの中間 JSON で読み戻し
    // を壊さない)。
    let direct = obj_str_with_default(m, "direct", "0")
    let target = obj_str_with_default(m, "target", "0")
    out.push({
      waza,
      type_: ty,
      category,
      pp,
      power,
      accuracy,
      direct,
      target,
    })
  }
  Ok(out)
}

///|
fn obj_str_with_default(
  obj : Map[String, Json],
  key : String,
  default : String,
) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    _ => default
  }
}

///|
/// `004_champions_learnset/data.json` をパース。
pub fn parse_learnset_entries(
  json : Json,
) -> Result[Array[LearnsetEntry], String] {
  let arr = match expect_array(json) {
    Err(e) => return Err(e)
    Ok(a) => a
  }
  let out : Array[LearnsetEntry] = []
  for i = 0; i < arr.length(); i = i + 1 {
    let ctx = "learnset[" + i.to_string() + "]"
    let m = match expect_object(arr[i], ctx) {
      Err(e) => return Err(e)
      Ok(o) => o
    }
    let id = match obj_str_required(m, "id", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let conditions = match obj_str_required(m, "conditions", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let waza = match obj_str_required(m, "waza", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    out.push({ id, conditions, waza })
  }
  Ok(out)
}

///|
/// `013_items/data.json` をパース。
pub fn parse_item_entries(json : Json) -> Result[Array[ItemEntry], String] {
  let arr = match expect_array(json) {
    Err(e) => return Err(e)
    Ok(a) => a
  }
  let out : Array[ItemEntry] = []
  for i = 0; i < arr.length(); i = i + 1 {
    let ctx = "item[" + i.to_string() + "]"
    let m = match expect_object(arr[i], ctx) {
      Err(e) => return Err(e)
      Ok(o) => o
    }
    let name_ja = match obj_str_required(m, "name_ja", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let category = match obj_str_required(m, "category", ctx) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    out.push({
      name_ja,
      name_en: obj_str(m, "name_en"),
      category,
      flavor: obj_str(m, "flavor"),
    })
  }
  Ok(out)
}
