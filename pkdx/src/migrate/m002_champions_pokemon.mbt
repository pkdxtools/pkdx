///|
/// Champions ポケモンデータを pokedex.db に載せる。
/// 各エントリについて local_pokedex/status/type/ability を INSERT OR
/// REPLACE し、`new_pokedex_entry` が真のものだけ pokedex / pokedex_name
/// に対して UPDATE→必要なら INSERT の順で同期する。
pub fn run_002(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/002_champions_pokemon/data.json"
  let raw = match @db.read_file(path) {
    Some(s) => s
    None => return Err(path + " not found.")
  }
  let json = try @json.parse(raw) catch {
    e => return Err("JSON parse: " + e.to_string())
  }
  let entries = match expect_array(json) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let version = "champions"
  // local_pokedex / _status / _type / _ability には UNIQUE 制約が無く、
  // `INSERT OR REPLACE` が実質プレーン INSERT になる。--resync で再投入
  // する前に Champions 行を明示的に削除しておくと、table は data.json の
  // 現在状態へ収束する (pokedex_name と pokedex は UPDATE-first で吸収)。
  let cleanup_tables = [
    "local_pokedex",
    "local_pokedex_status",
    "local_pokedex_type",
    "local_pokedex_ability",
  ]
  for t in cleanup_tables {
    match @db.exec_binds(
        db,
        "DELETE FROM " + t + " WHERE version = ?",
        [@db.BindText(version)],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  for entry_json in entries {
    let entry = match entry_json {
      Object(m) => m
      _ => return Err("entry is not an object")
    }
    let id = str_field(entry, "id")
    let no = str_field(entry, "no")
    let global_no = str_field(entry, "globalNo")
    let form = bind_text_opt(str_opt(entry, "form"))
    let region = bind_text_opt(str_opt(entry, "region"))
    let mega_evo = bind_text_opt(str_opt(entry, "mega_evolution"))
    let gigantamax = bind_text_opt(str_opt(entry, "gigantamax"))
    let pokedex_s = str_field(entry, "pokedex")
    let mega_evo_str = str_field(entry, "mega_evolution")
    if bool_field(entry, "new_pokedex_entry") {
      match @db.exec_binds(
          db,
          "UPDATE pokedex SET mega_evolution = ? WHERE id = ?",
          [bind_text_opt(str_opt(entry, "mega_evolution")), @db.BindText(id)],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      if @db.changes(db) == 0 {
        match @db.exec_binds(
            db,
            "INSERT INTO pokedex (id, globalNo, form, region, mega_evolution, gigantamax, height, weight) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [
              @db.BindText(id),
              @db.BindText(global_no),
              form,
              region,
              mega_evo,
              gigantamax,
              @db.BindText("-"),
              @db.BindText("-"),
            ],
          ) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
      }
      match sync_pokedex_name(
          db, id, global_no, form, region, mega_evo, gigantamax, mega_evo_str,
          "jpn", entry.get("new_pokedex_name_jpn"),
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      match sync_pokedex_name(
          db, id, global_no, form, region, mega_evo, gigantamax, mega_evo_str,
          "eng", entry.get("new_pokedex_name_eng"),
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    }
    match @db.exec_binds(
        db,
        "INSERT OR REPLACE INTO local_pokedex (id, no, globalNo, form, region, mega_evolution, gigantamax, version, pokedex) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(id),
          @db.BindText(no),
          @db.BindText(global_no),
          form,
          region,
          mega_evo,
          gigantamax,
          @db.BindText(version),
          @db.BindText(pokedex_s),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match @db.exec_binds(
        db,
        "INSERT OR REPLACE INTO local_pokedex_status (id, globalNo, form, region, mega_evolution, gigantamax, version, hp, attack, defense, special_attack, special_defense, speed) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(id),
          @db.BindText(global_no),
          form,
          region,
          mega_evo,
          gigantamax,
          @db.BindText(version),
          @db.BindInt(int_field(entry, "hp", 0)),
          @db.BindInt(int_field(entry, "attack", 0)),
          @db.BindInt(int_field(entry, "defense", 0)),
          @db.BindInt(int_field(entry, "special_attack", 0)),
          @db.BindInt(int_field(entry, "special_defense", 0)),
          @db.BindInt(int_field(entry, "speed", 0)),
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let type2 = bind_text_opt(str_opt(entry, "type2"))
    match @db.exec_binds(
        db,
        "INSERT OR REPLACE INTO local_pokedex_type (id, globalNo, form, region, mega_evolution, gigantamax, version, type1, type2) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(id),
          @db.BindText(global_no),
          form,
          region,
          mega_evo,
          gigantamax,
          @db.BindText(version),
          @db.BindText(str_field(entry, "type1")),
          type2,
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let ability1 = bind_text_opt(str_opt(entry, "ability1"))
    let ability2 = bind_text_opt(str_opt(entry, "ability2"))
    let dream = bind_text_opt(str_opt(entry, "dream_ability"))
    match @db.exec_binds(
        db,
        "INSERT OR REPLACE INTO local_pokedex_ability (id, globalNo, form, region, mega_evolution, gigantamax, version, ability1, ability2, dream_ability) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          @db.BindText(id),
          @db.BindText(global_no),
          form,
          region,
          mega_evo,
          gigantamax,
          @db.BindText(version),
          ability1,
          ability2,
          dream,
        ],
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  Ok(
    "Inserted/replaced " + entries.length().to_string() + " Champions pokemon entries",
  )
}

///|
/// Upsert a pokedex_name row for a specific language. Mirrors the
/// existence-check + UPDATE/INSERT branching in the original Ruby
/// migration so the per-language COALESCE clause stays intact.
fn sync_pokedex_name(
  db : @db.Db,
  id : String,
  global_no : String,
  form : @db.BindValue,
  region : @db.BindValue,
  mega_evo : @db.BindValue,
  gigantamax : @db.BindValue,
  mega_evo_str : String,
  lang : String,
  name_json : Json?,
) -> Result[Unit, String] {
  let name_str = match name_json {
    Some(String(s)) => s
    _ => return Ok(())
  }
  let rows = match @db.query_binds(
      db,
      "SELECT 1 FROM pokedex_name WHERE id = ? AND language = ? LIMIT 1",
      [@db.BindText(id), @db.BindText(lang)],
    ) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  let exists = rows.length() > 0
  if exists {
    let update_sql = "UPDATE pokedex_name SET mega_evolution = ?, name = ? WHERE id = ? AND language = ? AND (COALESCE(mega_evolution, '') = '' OR mega_evolution = ?)"
    @db.exec_binds(db, update_sql, [
      mega_evo,
      @db.BindText(name_str),
      @db.BindText(id),
      @db.BindText(lang),
      @db.BindText(mega_evo_str),
    ])
  } else {
    @db.exec_binds(
      db,
      "INSERT INTO pokedex_name (id, globalNo, form, region, mega_evolution, gigantamax, language, name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [
        @db.BindText(id),
        @db.BindText(global_no),
        form,
        region,
        mega_evo,
        gigantamax,
        @db.BindText(lang),
        @db.BindText(name_str),
      ],
    )
  }
}
