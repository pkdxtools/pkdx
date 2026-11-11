///|
/// 攻撃技の二次状態異常 (やけど / まひ / どく / もうどく) を move_meta に投入する。
/// m017 (こおり) と同じ列構成・同じ冪等の書き方 (既存行は ailment 列だけ上書き、無い行は INSERT)。
///
/// 出典は Champions 本文 (`champout/rom-txt/usa/wazainfo_syn.json` の行番号、ラベル行)。
/// 確率はすべて本文の記述から取った (Showdown の確率は使っていない)。
///
/// やけど (14):
/// - ほのおのパンチ 10% (:16) / かえんほうしゃ 10% (:574) / だいもんじ 10% (:1734)
/// - ねっぷう 10% 全体 (:4686) / ブレイズキック 10% (:5550)
/// - フレアドライブ 10% (:7480、解凍技・反動は既存) / ほのおのキバ 10% (:8176、ひるみは未モデル)
/// - ふんえん 30% 全体 (:8406) / ねっとう 30% (:9816、命中後に相手を解凍)
/// - れんごく 100% (:10162 "Burns the target.")
/// - かえんボール 10% (:13396、使用者を解凍) / ねっさのだいち 30% (:14386、相手を解凍)
/// - ひゃっきやこう 30% (:14784、状態異常の相手に威力 2 倍は未モデル)
/// - シャカシャカほう 20% 全体 (:15924、本文は解凍に触れないので Showdown thawsTarget (解凍は
///   freeze PR で既に実装済み))
///
/// まひ (10):
/// - かみなりパンチ 10% (:60) / のしかかり 30% (:304、ミニマイズ時の威力 2 倍は未モデル)
/// - １０まんボルト 10% (:1110) / かみなり 30% (:1154、命中は天候で変わるが未モデル)
/// - でんじほう 100% (:2936 "Paralyzes the target.") / とびはねる 30% (:6368、二ターン技の
///   溜ターンは未モデル。命中ターンに追加効果を付ける既存の 1 ターン近似に従う)
/// - ボルテッカー 10% (:6488、反動は既存) / かみなりのキバ 10% (:8096、ひるみは未モデル)
/// - ほうでん 30% 全体 (:8384) / ほっぺすりすり 100% (:11866 "Paralyzes the target.")
///
/// どく (8):
/// - ヘドロばくだん 30% (:2848) / どくづき 30% (:7582) / クロスポイズン 10% (:8490)
/// - ダストシュート 30% (:8530) / ヘドロウェーブ 10% 全体 (:9186)
/// - シェルアームズ 20% (:13898、物理 / 特殊の切り替えは既存の動的接触判定)
/// - どくばりセンボン 50% (:14642、毒状態の相手に威力 2 倍は未モデル)
/// - キラースピン 100% 全体 (:15152 "Poisons targets."、確率の記述が無いので確定)
///
/// もうどく (1):
/// - どくどくのキバ 50% (:5612 "Has a 50% chance of badly poisoning the target.")
///
/// 意図的に含めないもの:
/// - トライアタック (:2208 "20% chance of leaving the target burned, frozen, or paralyzed."):
///   3 種を 1/3 ずつ振るため、単一の `ailment_ja` / 整数 `ailment_chance` で表せない (複数状態異常)。
/// - フェイタルクロー (:14448 "30% chance of leaving the target poisoned, paralyzed, or asleep."):
///   3 種 (どく / まひ / ねむり) の複数状態異常。ねむりは本 PR の対象外。
/// - しっとのほのお (:14120 "Burns targets if their stats were boosted during the turn"):
///   同ターンに相手の能力が上がったときだけ付く条件付き。能力上昇の追跡が必要 (未モデル)。
/// - くちばしキャノン (:12588): 接触技を受けた後に攻撃者をやけどにする別の仕組み (未モデル)。
///
/// 既存の行 (フレアドライブ / ボルテッカー) は ailment 列だけ上書きし、recoil などは残す。
/// freeze (m017) の 5 行 (こおり) は触らない。何度流しても data.json の状態へ収束する (冪等)。
pub fn run_018(db : @db.Db, repo_root : String) -> Result[String, String] {
  let path = repo_root + "/pkdx_patch/018_move_meta_status/data.json"
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
      _ => return Err("status entry is not an object")
    }
    let name = str_field(entry, "name")
    let ailment_ja = str_field(entry, "ailment_ja")
    let ailment_chance = int_field(entry, "ailment_chance", 100)
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
          "UPDATE move_meta SET ailment_ja = ?, ailment_chance = ? WHERE name_ja = ?",
          [
            @db.BindText(ailment_ja),
            @db.BindInt(ailment_chance),
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
          "INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance) VALUES (?, 0, '[]', ?, ?)",
          [
            @db.BindText(name),
            @db.BindText(ailment_ja),
            @db.BindInt(ailment_chance),
          ],
        ) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      inserted = inserted + 1
    }
  }
  Ok(
    "damaging-move secondary status rows; " +
    updated.to_string() +
    " updated, " +
    inserted.to_string() +
    " inserted",
  )
}
