///|
/// Tests for the pokedex / champions migration split. Champions マスター
/// データを champout 由来 + champions.db 専用 migration に切り替えた後の
/// 期待値を反映する。

///|
test "migrations() is the concatenation of pokedex + champions" {
  let pdx = migrations_pokedex()
  let cmp = migrations_champions()
  let all = migrations()
  inspect(pdx.length() + cmp.length() == all.length(), content="true")
  let names : Array[String] = []
  for i = 0; i < all.length(); i = i + 1 {
    names.push(all[i].name)
  }
  inspect(
    names,
    content="[\"001_mega_legendsza\", \"002_move_meta\", \"003_mega_forms\", \"004_move_meta_ailment\", \"005_move_meta_posthit\", \"006_form_name_aliases\", \"007_gender_symbol_aliases\", \"008_champions_init_schema\", \"009_champions_pokemon\", \"010_champions_moves\", \"011_champions_learnset\", \"012_champions_items\", \"013_champions_form_aliases\"]",
  )
}

///|
test "migrations_champions hosts the champions.db lineup" {
  let cmp = migrations_champions()
  inspect(cmp.length(), content="6")
  let expected = [
    "008_champions_init_schema",
    "009_champions_pokemon",
    "010_champions_moves",
    "011_champions_learnset",
    "012_champions_items",
    "013_champions_form_aliases",
  ]
  for i = 0; i < expected.length(); i = i + 1 {
    let mut found = false
    for j = 0; j < cmp.length(); j = j + 1 {
      if cmp[j].name == expected[i] {
        found = true
      }
    }
    inspect(found, content="true")
  }
}

///|
test "migrations_pokedex hosts the live pokedex-side entries" {
  let pdx = migrations_pokedex()
  let expected = [
    "001_mega_legendsza", "002_move_meta", "003_mega_forms",
    "004_move_meta_ailment", "005_move_meta_posthit",
    "006_form_name_aliases", "007_gender_symbol_aliases",
  ]
  inspect(pdx.length() == expected.length(), content="true")
  for i = 0; i < expected.length(); i = i + 1 {
    let mut found = false
    for j = 0; j < pdx.length(); j = j + 1 {
      if pdx[j].name == expected[i] {
        found = true
      }
    }
    inspect(found, content="true")
  }
}
