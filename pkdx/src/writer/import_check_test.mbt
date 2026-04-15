///|
/// Champions cache (マンムー: ようき / こだわりスカーフ / つららおとし他)
fn mammu_cache() -> Json raise {
  let src =
    #|{
    #|  "version": "champions",
    #|  "regulation": "M-A",
    #|  "pokemon": {
    #|    "name": "マンムー",
    #|    "type1": "こおり",
    #|    "type2": "じめん",
    #|    "base_stats": {"hp":110,"atk":130,"def":80,"spa":70,"spd":60,"spe":80}
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "nature_up": "すばやさ",
    #|    "nature_down": "とくこう",
    #|    "ability": "あついしぼう",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100},
    #|      {"name":"つららおとし","type":"こおり","category":"物理","power":85,"accuracy":90},
    #|      {"name":"つららばり","type":"こおり","category":"物理","power":25,"accuracy":100},
    #|      {"name":"ばかぢから","type":"かくとう","category":"物理","power":120,"accuracy":100}
    #|    ],
    #|    "evs": {"hp":20,"atk":32,"def":0,"spa":0,"spd":0,"spe":14},
    #|    "actual_stats": {"hp":205,"atk":182,"def":100,"spa":81,"spd":80,"spe":145}
    #|  },
    #|  "damage_calcs": []
    #|}
  @json.parse(src)
}

///|
fn parse_move(s : String) -> Json raise {
  @json.parse(s)
}

///|
test "idempotency: identical_cache_returns_skip" {
  let cache = mammu_cache()
  let existing = [("box/pokemons/マンムー/スカーフ型.meta.json", cache)]
  let result = check_pokemon_import(cache, existing)
  inspect(
    result,
    content="Skip(\"box/pokemons/マンムー/スカーフ型.meta.json\")",
  )
}

///|
test "idempotency: differs_only_in_item_returns_diff" {
  let a = mammu_cache()
  let b = @json.parse(a.stringify())
  // item を変更 (こだわりスカーフ → いのちのたま)
  guard b is Object(root) else { fail("unexpected json shape") }
  guard root.get("build") is Some(Object(build)) else {
    fail("missing build")
  }
  build.set("item", "いのちのたま".to_json())
  let existing = [("box/pokemons/マンムー/いのちのたま型.meta.json", b)]
  let result = check_pokemon_import(a, existing)
  match result {
    Diff(path, fields) => {
      inspect(path, content="box/pokemons/マンムー/いのちのたま型.meta.json")
      inspect(fields, content="[\"item\"]")
    }
    _ => fail("Expected Diff, got \{result}")
  }
}

///|
test "idempotency: move_order_difference_is_normalized" {
  let a = mammu_cache()
  let b = @json.parse(a.stringify())
  // 技順を変更: じしんを末尾へ
  guard b is Object(root) else { fail("unexpected json shape") }
  guard root.get("build") is Some(Object(build)) else {
    fail("missing build")
  }
  let m1 =
    #|{"name":"つららおとし","type":"こおり","category":"物理","power":85,"accuracy":90}
  let m2 =
    #|{"name":"つららばり","type":"こおり","category":"物理","power":25,"accuracy":100}
  let m3 =
    #|{"name":"ばかぢから","type":"かくとう","category":"物理","power":120,"accuracy":100}
  let m4 =
    #|{"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100}
  let moves : Array[Json] = [
    parse_move(m1),
    parse_move(m2),
    parse_move(m3),
    parse_move(m4),
  ]
  build.set("moves", moves.to_json())
  let existing = [("box/pokemons/マンムー/スカーフ型.meta.json", b)]
  let result = check_pokemon_import(a, existing)
  // sort 後は一致 → Skip
  inspect(
    result,
    content="Skip(\"box/pokemons/マンムー/スカーフ型.meta.json\")",
  )
}

///|
test "idempotency: empty_existing_returns_new" {
  let cache = mammu_cache()
  let existing : Array[(String, Json)] = []
  let result = check_pokemon_import(cache, existing)
  inspect(result, content="New")
}
