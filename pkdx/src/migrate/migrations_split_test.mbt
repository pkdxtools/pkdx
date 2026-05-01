///|
/// Tests for the pokedex / champions migration split. Champions マスター
/// データを champout 由来 + champions.db 専用 migration に切り替えた後の
/// 期待値を反映する。

///|
test "migrations() is the chronological merge of pokedex + champions by name" {
  let combined_set : Array[String] = []
  let pdx = migrations_pokedex()
  for i = 0; i < pdx.length(); i = i + 1 {
    combined_set.push(pdx[i].name)
  }
  let cmp = migrations_champions()
  for i = 0; i < cmp.length(); i = i + 1 {
    combined_set.push(cmp[i].name)
  }
  let all = migrations()
  inspect(combined_set.length() == all.length(), content="true")
  for i = 0; i < combined_set.length(); i = i + 1 {
    let mut found = false
    for j = 0; j < all.length(); j = j + 1 {
      if combined_set[i] == all[j].name {
        found = true
      }
    }
    inspect(found, content="true")
  }
  // Lexicographic / chronological order preserved.
  let names : Array[String] = []
  for i = 0; i < all.length(); i = i + 1 {
    names.push(all[i].name)
  }
  inspect(
    names,
    content="[\"001_mega_legendsza\", \"006_move_meta\", \"007_mega_forms\", \"008_move_meta_ailment\", \"010_move_meta_posthit\", \"011_form_name_aliases\", \"012_gender_symbol_aliases\", \"014_champions_init_schema\", \"015_champions_pokemon\", \"016_champions_moves\", \"017_champions_learnset\", \"018_champions_items\", \"019_pokedex_purge_champions\"]",
  )
}

///|
test "migrations_champions hosts the new champions.db lineup" {
  let cmp = migrations_champions()
  inspect(cmp.length(), content="5")
  let expected = [
    "014_champions_init_schema",
    "015_champions_pokemon",
    "016_champions_moves",
    "017_champions_learnset",
    "018_champions_items",
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
test "migrations_pokedex hosts the live pokedex-side entries plus the purge migration" {
  let pdx = migrations_pokedex()
  let expected = [
    "001_mega_legendsza", "006_move_meta", "007_mega_forms",
    "008_move_meta_ailment", "010_move_meta_posthit",
    "011_form_name_aliases", "012_gender_symbol_aliases",
    "019_pokedex_purge_champions",
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

///|
test "latest_migration_name_pokedex returns the tail of migrations_pokedex" {
  let pdx = migrations_pokedex()
  let expected = if pdx.length() == 0 {
    ""
  } else {
    pdx[pdx.length() - 1].name
  }
  inspect(latest_migration_name_pokedex() == expected, content="true")
}

///|
test "latest_migration_name_champions returns the tail of migrations_champions" {
  let cmp = migrations_champions()
  let expected = if cmp.length() == 0 {
    ""
  } else {
    cmp[cmp.length() - 1].name
  }
  inspect(latest_migration_name_champions() == expected, content="true")
}
