///|
fn validate_with_schema(
  schema : @jsonschema.JsonSchema,
  json : Json,
) -> Array[@jsonschema.ValidationError] raise {
  let resolver = @jsonschema.build_resolver(
    ({} : Map[String, Json]).to_json(),
  )
  @jsonschema.Validatable::validate(
    schema,
    json,
    resolver~,
    json_path=@jsonschema.JsonPointer::Root,
    schema_path=@jsonschema.JsonPointer::Root,
  )
}

///|
test "generate_pokemon_placeholder: roundtrip relaxed schema accepts" {
  let b = @jsonschema.Builder::new()
  let schema = pokemon_schema(b, strict=false)
  let placeholder = generate_pokemon_placeholder()
  let errors = validate_with_schema(schema, placeholder)
  inspect(errors.is_empty(), content="true")
}

///|
test "generate_pokemon_placeholder: strict schema rejects" {
  let b = @jsonschema.Builder::new()
  let schema = pokemon_schema(b, strict=true)
  let placeholder = generate_pokemon_placeholder()
  let errors = validate_with_schema(schema, placeholder)
  inspect(errors.is_empty(), content="false")
}

///|
test "generate_team_placeholder: roundtrip relaxed schema accepts" {
  let b = @jsonschema.Builder::new()
  let schema = team_schema(b, strict=false)
  let placeholder = generate_team_placeholder()
  let errors = validate_with_schema(schema, placeholder)
  inspect(errors.is_empty(), content="true")
}

///|
test "generate_team_placeholder: strict schema rejects" {
  let b = @jsonschema.Builder::new()
  let schema = team_schema(b, strict=true)
  let placeholder = generate_team_placeholder()
  let errors = validate_with_schema(schema, placeholder)
  inspect(errors.is_empty(), content="false")
}

///|
test "generate_pokemon_placeholder: nullable fields are null" {
  let json = generate_pokemon_placeholder()
  guard json is Object(root) else { fail("expected object") }
  guard root.get("build") is Some(Object(build)) else {
    fail("expected build object")
  }
  inspect(build.get("nature"), content="Some(Null)")
  inspect(build.get("ability"), content="Some(Null)")
  inspect(build.get("item"), content="Some(Null)")
  // role は optional nullable なので null placeholder
  inspect(build.get("role"), content="Some(Null)")
}

///|
test "generate_pokemon_placeholder: numeric fields are zero" {
  let json = generate_pokemon_placeholder()
  guard json is Object(root) else { fail("expected object") }
  guard root.get("build") is Some(Object(build)) else {
    fail("expected build object")
  }
  guard build.get("stat_points") is Some(Object(sp)) else {
    fail("expected stat_points object")
  }
  inspect(sp.get("h"), content="Some(Number(0))")
  inspect(sp.get("a"), content="Some(Number(0))")
}

///|
test "generate_pokemon_placeholder: arrays default to empty" {
  let json = generate_pokemon_placeholder()
  guard json is Object(root) else { fail("expected object") }
  guard root.get("damage_calcs") is Some(Array(arr)) else {
    fail("expected damage_calcs array")
  }
  inspect(arr.length(), content="0")
}

///|
test "generate_pokemon_placeholder: moves has 4 null-name slots" {
  let json = generate_pokemon_placeholder()
  guard json is Object(root) else { fail("expected object") }
  guard root.get("build") is Some(Object(build)) else {
    fail("expected build object")
  }
  guard build.get("moves") is Some(Array(moves)) else {
    fail("expected moves array")
  }
  inspect(moves.length(), content="4")
  for mv in moves {
    guard mv is Object(mv_obj) else { fail("expected move object") }
    inspect(mv_obj.get("name"), content="Some(Null)")
  }
}

///|
test "generate_team_placeholder: nullable fields are null" {
  let json = generate_team_placeholder()
  guard json is Object(root) else { fail("expected object") }
  inspect(root.get("battle_format"), content="Some(Null)")
  inspect(root.get("mechanics"), content="Some(Null)")
  inspect(root.get("version"), content="Some(Null)")
}

///|
test "generate_team_placeholder: members is empty array" {
  let json = generate_team_placeholder()
  guard json is Object(root) else { fail("expected object") }
  guard root.get("members") is Some(Array(members)) else {
    fail("expected members array")
  }
  inspect(members.length(), content="0")
}

///|
/// pokemon.types[] は日本語 string の配列。要素数 1〜2 を strict schema で許容。
test "pokemon_schema: types[] accepts 1..=2 japanese type strings" {
  let b = @jsonschema.Builder::new()
  let schema = pokemon_schema(b, strict=true)
  let src =
    #|{
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169}
    #|  }
    #|}
  let json = @json.parse(src)
  let errors = validate_with_schema(schema, json)
  inspect(errors.is_empty(), content="true")
}

///|
/// pokemon.abilities[] は日本語 string の配列。要素数 1〜3 を strict schema で許容。
/// 4 要素以上は拒否される。
test "pokemon_schema: abilities[] accepts 1..=3 entries" {
  let b = @jsonschema.Builder::new()
  let schema = pokemon_schema(b, strict=true)
  let src =
    #|{
    #|  "pokemon": {
    #|    "name": "マンムー",
    #|    "types": ["こおり", "じめん"],
    #|    "base_stats": {"h":110,"a":130,"b":80,"c":70,"d":60,"s":80},
    #|    "abilities": ["あついしぼう", "どんかん", "ゆきがくれ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "あついしぼう",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
    #|    ],
    #|    "stat_points": {"h":0,"a":32,"b":0,"c":0,"d":0,"s":32},
    #|    "actual_stats": {"h":205,"a":182,"b":100,"c":81,"d":80,"s":145}
    #|  }
    #|}
  let json = @json.parse(src)
  let errors = validate_with_schema(schema, json)
  inspect(errors.is_empty(), content="true")
}

///|
/// issue #68: member moves の accuracy は optional で許容される。
/// pkdx moves CLI 出力をそのまま team cache に格納できる保証。
test "team_schema: member moves accuracy optional is accepted" {
  let b = @jsonschema.Builder::new()
  let schema = team_schema(b, strict=true)
  let src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "members": [{
    #|    "name": "ガブリアス",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "ability": "さめはだ",
    #|    "item": "こだわりハチマキ",
    #|    "role": "軸",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100},
    #|      {"name":"げきりん","type":"ドラゴン","category":"物理","power":120,"accuracy":100},
    #|      {"name":"アイアンヘッド","type":"はがね","category":"物理","power":80,"accuracy":100},
    #|      {"name":"ストーンエッジ","type":"いわ","category":"物理","power":100,"accuracy":80}
    #|    ]
    #|  }],
    #|  "coverage": [],
    #|  "defense_matrix": [],
    #|  "matchup_plans": [],
    #|  "strengths": [],
    #|  "weaknesses": []
    #|}
  let json = @json.parse(src)
  let errors = validate_with_schema(schema, json)
  inspect(errors.is_empty(), content="true")
}
