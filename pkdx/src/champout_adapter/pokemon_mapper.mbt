///|
/// champout の `masterdata/personal.json` を `champions_schema.PokemonEntry`
/// 配列へ変換する。
///
/// 入力 (champout) の主要フィールド:
///   - `id`     : 7 桁文字列 (no:4 + fo:3) — そのまま PokemonEntry.id とする
///   - `no`     : 内部番号文字列 ("3" 等) — 4 桁ゼロ埋めして globalNo / no に
///   - `fo`     : フォーム番号文字列 ("0" / "1" / ...)
///   - `ms_form_lbl` : `ZKN_FORM_<no>_<fo>` ラベル — zkn_form_syn で表示名へ
///   - `type1` / `type2` : 連続インデックス (0-17) — typename.json で名前へ
///   - `toku0` / `toku1` / `toku2` : 特性 1-based ID — tokusei.json で名前へ
///   - `hp` / `atk` / `def` / `spatk` / `spdef` / `agi` : 種族値文字列
///   - `is_valid` : "1" のものだけを採用 (Champions ゲーム内で使用可能)
///
/// 出力後処理:
///   - type2 が type1 と一致するときは "" に正規化 (単タイプ表現の慣例)
///   - ability2 が ability1 と一致するときは "" に正規化

///|
/// 4 桁ゼロ埋め (`3 -> "0003"`)。globalNo / no の出力統一に使う。
fn pad4(n : Int) -> String {
  if n >= 1000 {
    n.to_string()
  } else if n >= 100 {
    "0" + n.to_string()
  } else if n >= 10 {
    "00" + n.to_string()
  } else if n >= 0 {
    "000" + n.to_string()
  } else {
    "0000"
  }
}

///|
/// `personal.json` の root (Array) を受け取り PokemonEntry 配列を生成する。
/// `is_valid != "1"` の行はスキップ。必須フィールド (id / no / fo /
/// type1 / hp / atk / def / spatk / spdef / agi) が欠落 or 非文字列の
/// 行はエラーを返す (champout の生データバグを早期検出するため)。
pub fn map_pokemon_entries(
  bundle : LabelBundle,
  personal_json : Json,
) -> Result[Array[@champions_schema.PokemonEntry], String] {
  let arr = match personal_json {
    Array(a) => a
    _ => return Err("personal.json: expected top-level array")
  }
  let out : Array[@champions_schema.PokemonEntry] = []
  for i = 0; i < arr.length(); i = i + 1 {
    let m = match arr[i] {
      Object(o) => o
      _ => return Err("personal[" + i.to_string() + "]: not an object")
    }
    // is_valid != "1" は Champions 出場対象外なのでスキップ
    let is_valid = match m.get("is_valid") {
      Some(String(s)) => s == "1"
      _ => false
    }
    if not(is_valid) {
      continue
    }
    let ctx = "personal[" + i.to_string() + "]"
    let id = match m.get("id") {
      Some(String(s)) => s
      _ => return Err(ctx + ": missing 'id'")
    }
    let no_raw = match m.get("no") {
      Some(String(s)) => s
      _ => return Err(ctx + ": missing 'no'")
    }
    let no_int = to_int_or_zero(no_raw)
    let global_no = pad4(no_int)
    let no = global_no
    // form 表示名: ms_form_lbl から zkn_form_syn を引く。
    //
    // fo='0' は base form として扱い form='' へ正規化する。champout 側は
    // 「複数フォームがある globalNo」の form 0 にも識別ラベル
    // (例: ZKN_FORM_479_000 → "ロトムのすがた") を付けてくるが、pkdx の
    // discoverability (原種引き → forms[] 列挙) は form='' を base として
    // 仮定するので、ここで揃える。
    let fo = match m.get("fo") {
      Some(String(s)) => s
      _ => "0"
    }
    let form_lbl = match m.get("ms_form_lbl") {
      Some(String(s)) => s
      _ => ""
    }
    let form_label = match bundle.zkn_form.get(form_lbl) {
      Some(s) => s
      None => ""
    }
    let form = if fo == "0" { "" } else { form_label }
    // 表示名: base form は species 名 (ロトム)、別フォームは form 文字列
    // (ヒートロトム / メガリザードンＸ) をそのまま使う。
    let base_name = resolve_monsname(bundle, no_raw)
    let name_jpn = if form.length() == 0 { base_name } else { form }
    // タイプ
    let type1_raw = match m.get("type1") {
      Some(String(s)) => s
      _ => return Err(ctx + ": missing 'type1'")
    }
    let type2_raw = match m.get("type2") {
      Some(String(s)) => s
      _ => ""
    }
    let type1 = resolve_type(bundle, type1_raw)
    let type2_resolved = resolve_type(bundle, type2_raw)
    // 単タイプ正規化
    let type2 = if type2_resolved == type1 { "" } else { type2_resolved }
    // 特性
    let toku0 = match m.get("toku0") {
      Some(String(s)) => s
      _ => "0"
    }
    let toku1 = match m.get("toku1") {
      Some(String(s)) => s
      _ => "0"
    }
    let toku2 = match m.get("toku2") {
      Some(String(s)) => s
      _ => "0"
    }
    let ability1 = resolve_ability(bundle, toku0)
    let ability2_raw = resolve_ability(bundle, toku1)
    // ability1 と一致するときは空文字に
    let ability2 = if ability2_raw == ability1 { "" } else { ability2_raw }
    let dream_ability_raw = resolve_ability(bundle, toku2)
    // dream が ability1 / ability2 と一致するときは空文字 (DB 重複回避)
    let dream_ability = if dream_ability_raw == ability1 ||
      dream_ability_raw == ability2 {
      ""
    } else {
      dream_ability_raw
    }
    // 種族値
    let hp = obj_int_field(m, "hp", ctx)
    let atk = obj_int_field(m, "atk", ctx)
    let dfn = obj_int_field(m, "def", ctx)
    let spa = obj_int_field(m, "spatk", ctx)
    let spd = obj_int_field(m, "spdef", ctx)
    let spe = obj_int_field(m, "agi", ctx)
    let hp_v = match hp {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let atk_v = match atk {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let dfn_v = match dfn {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let spa_v = match spa {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let spd_v = match spd {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    let spe_v = match spe {
      Err(e) => return Err(e)
      Ok(n) => n
    }
    out.push({
      id,
      no,
      globalNo: global_no,
      form,
      name_jpn,
      pokedex: "Champions",
      type1,
      type2,
      hp: hp_v,
      attack: atk_v,
      defense: dfn_v,
      special_attack: spa_v,
      special_defense: spd_v,
      speed: spe_v,
      ability1,
      ability2,
      dream_ability,
    })
  }
  Ok(out)
}

///|
/// champout の数値フィールドは文字列で表されているので、`Some(String("80"))`
/// → 80 のように 2 段階で変換する必要がある。
fn obj_int_field(
  obj : Map[String, Json],
  key : String,
  ctx : String,
) -> Result[Int, String] {
  match obj.get(key) {
    Some(String(s)) =>
      try Ok(@strconv.parse_int(s)) catch {
        _ => Err(ctx + ": field '" + key + "' is not an integer string: " + s)
      }
    Some(_) => Err(ctx + ": field '" + key + "' has non-string value")
    None => Err(ctx + ": missing required field '" + key + "'")
  }
}
