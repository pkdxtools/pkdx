///|
/// `pkdx_patch/002_champions_pokemon/data.json` を champions.db.pokemon と
/// champions.db.pokemon_name に投入する。`pokemon` テーブルは PRIMARY KEY
/// (`id`) を持つので INSERT OR REPLACE で冪等に上書きできる。
/// `pokemon_name` も (id, language) の複合 PK で同様。
pub fn run_009(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/009_champions_pokemon/data.json"
  let raw = match @db.read_file(path) {
    None => return Err(path + " not found.")
    Some(s) => s
  }
  let json = try @json.parse(raw) catch {
    e => return Err("JSON parse: " + e.to_string())
  }
  let entries = match @champions_schema.parse_pokemon_entries(json) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  // resync 時の重複を避けるため、本 migration が所有する全行を消してから
  // 入れ直す。pokemon は PK で一意だが、pokemon_name は (id, jpn) のみ
  // 入っているので id 単位で削除する。
  match @db.exec(db, "DELETE FROM pokemon") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match @db.exec(db, "DELETE FROM pokemon_name") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  for i = 0; i < entries.length(); i = i + 1 {
    let e = entries[i]
    match @db.exec_binds(
        db,
        "INSERT INTO pokemon (id, no, global_no, form, pokedex, type1, type2, hp, attack, defense, special_attack, special_defense, speed, ability1, ability2, dream_ability) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(e.id),
          @db.BindText(e.no),
          @db.BindText(e.globalNo),
          @db.BindText(e.form),
          @db.BindText(e.pokedex),
          @db.BindText(e.type1),
          @db.BindText(e.type2),
          @db.BindInt(e.hp),
          @db.BindInt(e.attack),
          @db.BindInt(e.defense),
          @db.BindInt(e.special_attack),
          @db.BindInt(e.special_defense),
          @db.BindInt(e.speed),
          @db.BindText(e.ability1),
          @db.BindText(e.ability2),
          @db.BindText(e.dream_ability),
        ],
      ) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    match @db.exec_binds(
        db,
        "INSERT INTO pokemon_name (id, language, name) VALUES (?, ?, ?)",
        [@db.BindText(e.id), @db.BindText("jpn"), @db.BindText(e.name_jpn)],
      ) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  Ok("Inserted " + entries.length().to_string() + " pokemon rows")
}
