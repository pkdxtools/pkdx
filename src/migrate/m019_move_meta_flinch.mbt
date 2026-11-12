///|
/// 攻撃技の ひるみ確率 (`flinch_chance`) を move_meta に投入する。m018 (二次状態異常) と同じ
/// 列構成・同じ冪等の書き方で、列は ensure_column で追加し、既存行は flinch 列だけを上書き、
/// 無い行は INSERT する (ailment 列は既定値 '' / 100 のまま = 状態異常なし)。
///
/// 出典は Champions 本文 `champout/rom-txt/usa/wazainfo_syn.json` の「N% chance of making the target
/// flinch」(ラベル行。Showdown の確率は使っていない)。技名は DB の jpn 名で持つ。
/// - champions 経路 (`query_champions_move` / `query_champions_moves`) は champout の jpn 本文を
///   技名に使うので「３ぼんのや」(全角 3)、pokedex 経路 (`query_moves` 旧経路) は upstream DB の
///   「3ぼんのや」(ASCII 3)。両方のキーを入れる (同じ 30%)。
///
/// 投入 (18 技 + 表記違い 1 件):
/// - かみつく 30% (:450) / たきのぼり 20% (:1756) / ゴッドバード 30% (:1924、2 ターン技は
///   溜ターンを持たず命中ターンに付ける 1 ターン近似。とびはねる (m018) と同じ扱い)
/// - いわなだれ 30% (:2186、全体技の複数対象は単体戦では同じ) / いびき 30% (:2426、
///   「ねむっている間だけ使える」は未モデル。ひるみの確率だけ投入)
/// - じんつうりき 10% (:6050) / あくのはどう 20% (:7604) / エアスラッシュ 30% (:7648)
/// - ドラゴンダイブ 20% (:7710、ミニマイズ時の威力 2 倍は未モデル)
/// - かみなりのキバ 10% (:8096) / こおりのキバ 10% (:8136) / ほのおのキバ 10% (:8176)
///   (牙 3 種は m017 / m018 が投入済みの状態異常 10% と独立の 10% として併記。状態異常の行は触らない)
/// - しねんのずつき 20% (:8238) / アイアンヘッド 20% (:8552、本文どおり 20%)
/// - つららおとし 30% (:10796) / びりびりちくちく 30% (:12868) / ひょうざんおろし 30% (:14598)
/// - ３ぼんのや 30% (:14726、本文は別に 50% の防御ダウンを持つ。防御ダウンは本 PR の対象外)
///
/// 意図的に含めないもの:
/// - ねこだまし (:252 "fails unless it is the first move used by the user after it enters a
///   battle"): 初回行動だけで成功し、2 手目以降は失敗する。switch-in 後の初回行動を表す状態が
///   モデルに無いため、100% のひるみを行として入れると 2 手目以降も必ずひるむことになる。見送り。
/// - はやてがえし (:918 "fails if the target isn't about to use a priority attack"): 相手の
///   選択技が先制技のときだけ成功する条件付き。見送り。
///
/// 何度流しても data.json の状態へ収束する (冪等)。
pub fn run_019(db : @db.Db, repo_root : String) -> Result[String, String] {
  match
    ensure_column(
      db,
      "move_meta",
      "flinch_chance",
      "ALTER TABLE move_meta ADD COLUMN flinch_chance INTEGER NOT NULL DEFAULT 0",
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let path = repo_root + "/pkdx_patch/019_move_meta_flinch/data.json"
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
      _ => return Err("flinch entry is not an object")
    }
    let name = str_field(entry, "name")
    let flinch_chance = int_field(entry, "flinch_chance", 0)
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
          "UPDATE move_meta SET flinch_chance = ? WHERE name_ja = ?",
          [@db.BindInt(flinch_chance), @db.BindText(name)],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      updated = updated + 1
    } else {
      match
        @db.exec_binds(
          db,
          "INSERT INTO move_meta (name_ja, priority, stat_effects_json, flinch_chance) VALUES (?, 0, '[]', ?)",
          [@db.BindText(name), @db.BindInt(flinch_chance)],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "flinch rows; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}
