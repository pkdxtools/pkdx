///|
/// team-builder §8-3 fallback の契約: breed の {pokemon, build} のうち
/// `build` セクションは、member shape に `name` / `types` / `base_stats` を補足するだけで
/// `members[i]` として team schema に食わせられる。
///
/// これを integration で回帰防止する。breed と team で stat_points / nature / moves など
/// キーが揃っているため、skill 側は単純な merge だけで member を組める。
test "team_breed_fallback_smoke: breed build subtree feeds into team member" {
  let breed_src =
    #|{
    #|  "version": "scarlet_violet",
    #|  "pokemon": {
    #|    "name": "ガブリアス",
    #|    "name_en": "Garchomp",
    #|    "globalNo": "0445",
    #|    "types": ["ドラゴン", "じめん"],
    #|    "base_stats": {"h":108,"a":130,"b":95,"c":80,"d":85,"s":102},
    #|    "abilities": ["さめはだ"]
    #|  },
    #|  "build": {
    #|    "nature": "ようき",
    #|    "ability": "さめはだ",
    #|    "item": "こだわりスカーフ",
    #|    "moves": [
    #|      {"name":"じしん","type":"じめん","category":"物理","power":100,"accuracy":100},
    #|      {"name":"げきりん","type":"ドラゴン","category":"物理","power":120,"accuracy":100},
    #|      {"name":"アイアンヘッド","type":"はがね","category":"物理","power":80,"accuracy":100},
    #|      {"name":"ストーンエッジ","type":"いわ","category":"物理","power":100,"accuracy":80}
    #|    ],
    #|    "stat_points": {"h":0,"a":252,"b":0,"c":0,"d":4,"s":252},
    #|    "actual_stats": {"h":183,"a":182,"b":115,"c":90,"d":106,"s":169},
    #|    "role": "物理アタッカー"
    #|  }
    #|}
  let breed = @json.parse(breed_src)

  // まず breed 単体で validate が通ること。
  inspect(validate_pokemon_json(breed), content="Ok(())")

  // breed の build に pokemon.name / types / base_stats を添えて member を合成。
  guard breed is Object(breed_root) else { fail("unexpected shape") }
  guard breed_root.get("pokemon") is Some(Object(pokemon)) else {
    fail("pokemon missing")
  }
  guard breed_root.get("build") is Some(Object(build)) else {
    fail("build missing")
  }
  let mem : Map[String, Json] = {}
  for k, v in build {
    mem[k] = v
  }
  match pokemon.get("name") {
    Some(v) => mem["name"] = v
    _ => ()
  }
  match pokemon.get("types") {
    Some(v) => mem["types"] = v
    _ => ()
  }
  match pokemon.get("base_stats") {
    Some(v) => mem["base_stats"] = v
    _ => ()
  }

  // 合成した member を team_schema に通す。
  let team_src =
    #|{
    #|  "battle_format": "singles",
    #|  "mechanics": "テラスタル",
    #|  "version": "scarlet_violet",
    #|  "members": [],
    #|  "coverage": [],
    #|  "defense_matrix": [],
    #|  "matchup_plans": [],
    #|  "strengths": [],
    #|  "weaknesses": []
    #|}
  let team = @json.parse(team_src)
  guard team is Object(team_root) else { fail("team parse failed") }
  team_root["members"] = [mem.to_json()].to_json()
  inspect(validate_team_json(team.to_json()), content="Ok(())")
}
