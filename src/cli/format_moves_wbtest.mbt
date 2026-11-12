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
