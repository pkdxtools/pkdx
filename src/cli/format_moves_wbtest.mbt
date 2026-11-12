///|
/// `pkdx moves` の JSON (`moves_to_json`) に載る追加効果キー。
/// - 既定値 (status なし / flinch 0) の技はキーを省略し、旧形式とバイト単位で一致する。
/// - `status_effect` は `{"kind":和名,"chance":N}`、`flinch_chance` は整数。
/// 形は `pkdx select` の JSON 入力 (`parse_move_json`) が読む契約と一致させる。

///|
fn fm_move(
  name : String,
  type_ : String,
  category : @model.MoveCategory,
  power : Int,
  accuracy : Int,
  status_effect : (@model.StatusKind, Int)?,
  flinch_chance : Int,
) -> @model.Move {
  {
    name,
    type_,
    category,
    power,
    accuracy,
    pp: 15,
    learn_method: "基本",
    priority: 0,
    stat_effects: [],
    status_effect,
    recoil_num: 0,
    recoil_den: 1,
    self_ko: false,
    recharge: false,
    healing: None,
    weather_set: None,
    field_set: None,
    flinch_chance,
  }
}

///|
test "moves_to_json: a move with no secondary effect keeps the legacy shape (keys omitted)" {
  let mv = fm_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None, 0)
  assert_eq(
    moves_to_json([mv]),
    "[{\"name\":\"たいあたり\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":40,\"accuracy\":100,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[]}]",
  )
}

///|
test "moves_to_json: status_effect is emitted as {kind, chance} after stat_effects" {
  let mv = fm_move(
    "かえんほうしゃ",
    "ほのお",
    @model.Special,
    90,
    100,
    Some((@model.BurnKind, 10)),
    0,
  )
  assert_eq(
    moves_to_json([mv]),
    "[{\"name\":\"かえんほうしゃ\",\"type\":\"ほのお\",\"category\":\"特殊\",\"power\":90,\"accuracy\":100,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"status_effect\":{\"kind\":\"やけど\",\"chance\":10}}]",
  )
}

///|
test "moves_to_json: flinch_chance is emitted only when positive" {
  let mv = fm_move("アイアンヘッド", "はがね", @model.Physical, 80, 100, None, 20)
  assert_eq(
    moves_to_json([mv]),
    "[{\"name\":\"アイアンヘッド\",\"type\":\"はがね\",\"category\":\"物理\",\"power\":80,\"accuracy\":100,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"flinch_chance\":20}]",
  )
}

///|
test "moves_to_json: status_effect and flinch_chance together, status first" {
  let mv = fm_move(
    "かみなりのキバ",
    "でんき",
    @model.Physical,
    65,
    95,
    Some((@model.ParalyzeKind, 10)),
    10,
  )
  assert_eq(
    moves_to_json([mv]),
    "[{\"name\":\"かみなりのキバ\",\"type\":\"でんき\",\"category\":\"物理\",\"power\":65,\"accuracy\":95,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"status_effect\":{\"kind\":\"まひ\",\"chance\":10},\"flinch_chance\":10}]",
  )
}

///|
test "moves_to_json: pure status chance is printed as stored (DB path already normalised it to 100)" {
  let mv = fm_move(
    "おにび",
    "ほのお",
    @model.Status,
    0,
    85,
    Some((@model.BurnKind, 100)),
    0,
  )
  assert_eq(
    moves_to_json([mv]),
    "[{\"name\":\"おにび\",\"type\":\"ほのお\",\"category\":\"変化\",\"power\":0,\"accuracy\":85,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"status_effect\":{\"kind\":\"やけど\",\"chance\":100}}]",
  )
}

///|
test "moves_to_json: separator placement across several moves" {
  let plain = fm_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None, 0)
  let flinch = fm_move("アイアンヘッド", "はがね", @model.Physical, 80, 100, None, 20)
  let out = moves_to_json([plain, flinch])
  assert_true(out.has_prefix("[{\"name\":\"たいあたり\""))
  assert_true(out.contains("\"stat_effects\":[]},{\"name\":\"アイアンヘッド\""))
  assert_true(out.has_suffix("\"stat_effects\":[],\"flinch_chance\":20}]"))
}

///|
test "moves_to_json: empty move list is an empty JSON array" {
  assert_eq(moves_to_json([]), "[]")
}

///|
/// 014–016 系 (move_meta 由来の反動・自滅・反動ターン・回復・天候設定・フィールド設定) のキー。
/// 既定値 (recoil 0 / self_ko false / recharge false / None) はキーを省略する。
test "moves_to_json: recoil_num and recoil_den are emitted together when recoil_num > 0" {
  let base = fm_move("もろはのずつき", "ノーマル", @model.Physical, 120, 100, None, 0)
  let mv = { ..base, recoil_num: 1, recoil_den: 2 }
  assert_eq(
    moves_to_json([mv]),
    "[{\"name\":\"もろはのずつき\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":120,\"accuracy\":100,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"recoil_num\":1,\"recoil_den\":2}]",
  )
}

///|
test "moves_to_json: self_ko and recharge are emitted only when true" {
  let base = fm_move("だいばくはつ", "ノーマル", @model.Physical, 250, 100, None, 0)
  let explode = { ..base, self_ko: true }
  assert_eq(
    moves_to_json([explode]),
    "[{\"name\":\"だいばくはつ\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":250,\"accuracy\":100,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"self_ko\":true}]",
  )
  let base2 = fm_move("はかいこうせん", "ノーマル", @model.Special, 150, 90, None, 0)
  let recharge = { ..base2, recharge: true }
  assert_eq(
    moves_to_json([recharge]),
    "[{\"name\":\"はかいこうせん\",\"type\":\"ノーマル\",\"category\":\"特殊\",\"power\":150,\"accuracy\":90,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"recharge\":true}]",
  )
}

///|
test "moves_to_json: fixed and drain heal carry heal_num / heal_den only" {
  let base = fm_move("じこさいせい", "ノーマル", @model.Status, 0, 100, None, 0)
  let fixed = { ..base, healing: Some(@model.FixedFraction(1, 2)) }
  assert_eq(
    moves_to_json([fixed]),
    "[{\"name\":\"じこさいせい\",\"type\":\"ノーマル\",\"category\":\"変化\",\"power\":0,\"accuracy\":100,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"heal_kind\":\"fixed\",\"heal_num\":1,\"heal_den\":2}]",
  )
  let drain_base = fm_move("ギガドレイン", "くさ", @model.Special, 75, 100, None, 0)
  let drain = { ..drain_base, healing: Some(@model.Drain(1, 2)) }
  assert_eq(
    moves_to_json([drain]),
    "[{\"name\":\"ギガドレイン\",\"type\":\"くさ\",\"category\":\"特殊\",\"power\":75,\"accuracy\":100,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"heal_kind\":\"drain\",\"heal_num\":1,\"heal_den\":2}]",
  )
}

///|
test "moves_to_json: weather heal carries the default, sunny and harsh fractions" {
  let base = fm_move("つきのひかり", "フェアリー", @model.Status, 0, 100, None, 0)
  let mv = {
    ..base,
    healing: Some(@model.WeatherDependent(1, 2, 2, 3, 1, 4)),
  }
  assert_eq(
    moves_to_json([mv]),
    "[{\"name\":\"つきのひかり\",\"type\":\"フェアリー\",\"category\":\"変化\",\"power\":0,\"accuracy\":100,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"heal_kind\":\"weather\",\"heal_num\":1,\"heal_den\":2,\"heal_sunny_num\":2,\"heal_sunny_den\":3,\"heal_harsh_num\":1,\"heal_harsh_den\":4}]",
  )
}

///|
test "moves_to_json: rest / leech_seed / pain_split / wish carry the kind only" {
  let base = fm_move("ねむる", "エスパー", @model.Status, 0, 100, None, 0)
  let kinds : Array[(@model.HealingEffect, String)] = [
    (@model.Rest, "rest"),
    (@model.LeechSeed, "leech_seed"),
    (@model.PainSplit, "pain_split"),
    (@model.Wish, "wish"),
  ]
  for k in kinds {
    let (h, want) = k
    let mv = { ..base, healing: Some(h) }
    assert_true(
      moves_to_json([mv]).has_suffix(",\"heal_kind\":\"" + want + "\"}]"),
    )
  }
}

///|
test "moves_to_json: weather_set and field_set use the DB canonical names" {
  let base = fm_move("あまごい", "みず", @model.Status, 0, 100, None, 0)
  let weathers : Array[(@model.Weather, String)] = [
    (@model.Sun, "sun"),
    (@model.Rain, "rain"),
    (@model.Sand, "sand"),
    (@model.Snow, "snow"),
  ]
  for w in weathers {
    let (wv, want) = w
    let mv = { ..base, weather_set: Some(wv) }
    assert_true(
      moves_to_json([mv]).has_suffix(
        ",\"weather_set\":\"" + want + "\"}]",
      ),
    )
  }
  let fbase = fm_move("エレキフィールド", "でんき", @model.Status, 0, 100, None, 0)
  let fields : Array[(@model.Field, String)] = [
    (@model.Electric, "electric"),
    (@model.Grassy, "grassy"),
    (@model.Misty, "misty"),
    (@model.Psychic, "psychic"),
  ]
  for f in fields {
    let (fv, want) = f
    let mv = { ..fbase, field_set: Some(fv) }
    assert_true(
      moves_to_json([mv]).has_suffix(",\"field_set\":\"" + want + "\"}]"),
    )
  }
}

///|
test "moves_to_json: all 014-016 keys after the legacy keys, in a fixed order" {
  let base = fm_move("テスト技", "ノーマル", @model.Physical, 80, 100, None, 0)
  let mv = {
    ..base,
    status_effect: Some((@model.ParalyzeKind, 10)),
    flinch_chance: 10,
    recoil_num: 1,
    recoil_den: 4,
    self_ko: true,
    recharge: true,
    healing: Some(@model.Drain(1, 2)),
    weather_set: Some(@model.Rain),
    field_set: Some(@model.Electric),
  }
  assert_eq(
    moves_to_json([mv]),
    "[{\"name\":\"テスト技\",\"type\":\"ノーマル\",\"category\":\"物理\",\"power\":80,\"accuracy\":100,\"pp\":15,\"learn_method\":\"基本\",\"priority\":0,\"stat_effects\":[],\"status_effect\":{\"kind\":\"まひ\",\"chance\":10},\"flinch_chance\":10,\"recoil_num\":1,\"recoil_den\":4,\"self_ko\":true,\"recharge\":true,\"heal_kind\":\"drain\",\"heal_num\":1,\"heal_den\":2,\"weather_set\":\"rain\",\"field_set\":\"electric\"}]",
  )
}

///|
test "moves_to_json: recoil_num 0 hides recoil_den too (no recoil)" {
  let base = fm_move("たいあたり", "ノーマル", @model.Physical, 40, 100, None, 0)
  let mv = { ..base, recoil_num: 0, recoil_den: 3 }
  assert_false(moves_to_json([mv]).contains("recoil"))
}
