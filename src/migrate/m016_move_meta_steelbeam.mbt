///|
/// てっていこうせん (Steel Beam) の自己ステータス低下を取り除く。
///
/// m005 (`pkdx_patch/005_move_meta_posthit`) が `stat_effects` に
/// `[[1,-2,0],[3,-2,0]]` (使用者の防御 / 特防 -2) を投入していたが、Champions の
/// 技説明 (`champout/rom-txt/usa/wazainfo_syn.json:13644` "After attacking, the
/// user takes damage equal to 1/2 of its max HP.") にも本家にも能力低下は無い。
/// 使用者が受けるのは最大 HP の 1/2 の反動で、これは `stat_effects` ではなく
/// 別経路 (payoff の `max_hp_recoil`) でモデルする。
///
/// 005 の data.json からエントリを削除せず、新 migration で上書きする理由:
/// 各 migration は毎回の `pkdx migrate` で全件流れるが、data.json から消えた行の
/// 値は DB に残り続ける (m005 は data.json に無い行を触らない)。既に古い値が
/// 入った DB を収束させるには、この migration が明示的に値を書き戻す必要がある。
/// m005 → m016 の順で流れるため、何度流しても最終状態は `[]` に収束する。
///
/// 冪等性: UPDATE は対象行の `stat_effects_json` だけを data.json の値で置き換える。
/// 行が無い場合は何もしない (技メタが無い = 能力変化も無い)。他の列は触らない。
pub fn run_016(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/016_move_meta_steelbeam/data.json"
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
  let mut corrected = 0
  for entry_json in entries {
    let entry = match entry_json {
      Object(o) => o
      _ => return Err("steelbeam entry is not an object")
    }
    let name = str_field(entry, "name")
    let effects_json = match entry.get("stat_effects") {
      Some(j) => j.stringify()
      None => "[]"
    }
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
          "UPDATE move_meta SET stat_effects_json = ? WHERE name_ja = ?",
          [@db.BindText(effects_json), @db.BindText(name)],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      corrected = corrected + 1
    }
  }
  Ok(
    "steelbeam stat_effects corrected; " + corrected.to_string() + " rows updated",
  )
}
