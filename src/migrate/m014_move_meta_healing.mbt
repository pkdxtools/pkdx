///|
/// move_meta に回復技 (じこさいせい / つきのひかり / ギガドレイン /
/// ねむる / やどりぎのタネ / いたみわけ / ねがいごと) と天候設定技
/// (にほんばれ / あまごい / すなあらし / ゆきげしき) のメタデータを
/// 投入する。
///
/// 列構成:
/// - `heal_kind`        : '' (なし) / 'fixed' / 'weather' / 'drain' /
///                        'rest' / 'leech_seed' / 'pain_split' / 'wish'
/// - `heal_num / heal_den` : default fraction (固定割合 / drain は dmg 比)
/// - `heal_sunny_num / heal_sunny_den` : weather='Sun' のときの fraction
/// - `heal_harsh_num / heal_harsh_den` : weather=Rain/Sand/Snow のときの fraction
/// - `weather_set`      : '' (なし) / 'sun' / 'rain' / 'sand' / 'snow'
/// - `weather_turns`    : 天候持続ターン数 (Gen9 base 5、天候石は本 PR 未対応)
///
/// 冪等性戦略 (authoritative overlay):
/// 1. ensure_column で 9 列追加 (DEFAULT neutral)
/// 2. **全 move_meta 行を heal/weather 列について neutral に reset** —
///    過去 data.json から技を消した場合に「以前は drain だった行」が
///    DB に残り続けるのを防ぐ
/// 3. data.json から upsert (UPDATE 優先、無ければ INSERT)
///
/// この戦略により m014 は何度流しても data.json の現在状態へ収束する。
pub fn run_014(db : @db.Db, repo_root : String) -> Result[String, String] {
  let alters = [
    (
      "heal_kind", "ALTER TABLE move_meta ADD COLUMN heal_kind TEXT NOT NULL DEFAULT ''",
    ),
    (
      "heal_num", "ALTER TABLE move_meta ADD COLUMN heal_num INTEGER NOT NULL DEFAULT 0",
    ),
    (
      "heal_den", "ALTER TABLE move_meta ADD COLUMN heal_den INTEGER NOT NULL DEFAULT 1",
    ),
    (
      "heal_sunny_num", "ALTER TABLE move_meta ADD COLUMN heal_sunny_num INTEGER NOT NULL DEFAULT 0",
    ),
    (
      "heal_sunny_den", "ALTER TABLE move_meta ADD COLUMN heal_sunny_den INTEGER NOT NULL DEFAULT 1",
    ),
    (
      "heal_harsh_num", "ALTER TABLE move_meta ADD COLUMN heal_harsh_num INTEGER NOT NULL DEFAULT 0",
    ),
    (
      "heal_harsh_den", "ALTER TABLE move_meta ADD COLUMN heal_harsh_den INTEGER NOT NULL DEFAULT 1",
    ),
    (
      "weather_set", "ALTER TABLE move_meta ADD COLUMN weather_set TEXT NOT NULL DEFAULT ''",
    ),
    (
      "weather_turns", "ALTER TABLE move_meta ADD COLUMN weather_turns INTEGER NOT NULL DEFAULT 0",
    ),
  ]
  for col in alters {
    let (name, sql) = col
    match ensure_column(db, "move_meta", name, sql) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  // Authoritative reset: 過去の m014 run で投入された行を data.json から
  // 削除した場合にも DB を収束させるため、全行を neutral に戻してから
  // upsert する。
  match
    @db.exec(
      db, "UPDATE move_meta SET heal_kind='', heal_num=0, heal_den=1, heal_sunny_num=0, heal_sunny_den=1, heal_harsh_num=0, heal_harsh_den=1, weather_set='', weather_turns=0",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let path = repo_root + "/pkdx_patch/014_move_meta_healing/data.json"
  let raw = match @db.read_file(path) {
    Some(s) => s
    None => return Err(path + " not found.")
  }
  let json = @json.parse(raw) catch {
    e => return Err("JSON parse: " + e.to_string())
  }
  let entries = match expect_array(json) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let mut updated = 0
  let mut inserted = 0
  for entry_json in entries {
    let entry = match entry_json {
      Object(o) => o
      _ => return Err("healing entry is not an object")
    }
    let name = str_field(entry, "name")
    let heal_kind = str_field(entry, "heal_kind")
    let heal_num = int_field(entry, "heal_num", 0)
    let heal_den_raw = int_field(entry, "heal_den", 1)
    let heal_den = if heal_den_raw <= 0 { 1 } else { heal_den_raw }
    let heal_sunny_num = int_field(entry, "heal_sunny_num", 0)
    let heal_sunny_den_raw = int_field(entry, "heal_sunny_den", 1)
    let heal_sunny_den = if heal_sunny_den_raw <= 0 {
      1
    } else {
      heal_sunny_den_raw
    }
    let heal_harsh_num = int_field(entry, "heal_harsh_num", 0)
    let heal_harsh_den_raw = int_field(entry, "heal_harsh_den", 1)
    let heal_harsh_den = if heal_harsh_den_raw <= 0 {
      1
    } else {
      heal_harsh_den_raw
    }
    let weather_set = str_field(entry, "weather_set")
    let weather_turns = int_field(entry, "weather_turns", 0)
    let rows = match
      @db.query_binds(db, "SELECT 1 FROM move_meta WHERE name_ja = ? LIMIT 1", [
        @db.BindText(name),
      ]) {
      Err(e) => return Err(e)
      Ok(r) => r
    }
    if rows.length() > 0 {
      match
        @db.exec_binds(
          db,
          "UPDATE move_meta SET heal_kind = ?, heal_num = ?, heal_den = ?, heal_sunny_num = ?, heal_sunny_den = ?, heal_harsh_num = ?, heal_harsh_den = ?, weather_set = ?, weather_turns = ? WHERE name_ja = ?",
          [
            @db.BindText(heal_kind),
            @db.BindInt(heal_num),
            @db.BindInt(heal_den),
            @db.BindInt(heal_sunny_num),
            @db.BindInt(heal_sunny_den),
            @db.BindInt(heal_harsh_num),
            @db.BindInt(heal_harsh_den),
            @db.BindText(weather_set),
            @db.BindInt(weather_turns),
            @db.BindText(name),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      updated = updated + 1
    } else {
      match
        @db.exec_binds(
          db,
          "INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance, recoil_num, recoil_den, self_ko, recharge, heal_kind, heal_num, heal_den, heal_sunny_num, heal_sunny_den, heal_harsh_num, heal_harsh_den, weather_set, weather_turns) VALUES (?, 0, '[]', '', 100, 0, 1, 0, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [
            @db.BindText(name),
            @db.BindText(heal_kind),
            @db.BindInt(heal_num),
            @db.BindInt(heal_den),
            @db.BindInt(heal_sunny_num),
            @db.BindInt(heal_sunny_den),
            @db.BindInt(heal_harsh_num),
            @db.BindInt(heal_harsh_den),
            @db.BindText(weather_set),
            @db.BindInt(weather_turns),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "healing/weather columns added; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}
