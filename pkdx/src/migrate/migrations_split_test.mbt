///|
/// Tests for the pokedex / champions migration split (issue #95).
/// Step 0 (Red Phase): fails until migrations_pokedex / migrations_champions
/// are introduced.

///|
test "migrations() is the chronological merge of pokedex + champions by name" {
  // Backward compat: existing pkdx_migrations bookkeeping rows assume
  // chronological apply order (001 → 012). The split lists are each
  // individually sorted, so migrations() interleaves them by name to
  // preserve the original sequence.
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
  // 1. Sizes match (no duplicates, no drops)
  inspect(combined_set.length() == all.length(), content="true")
  // 2. Every migration in the split lists appears in migrations()
  for i = 0; i < combined_set.length(); i = i + 1 {
    let mut found = false
    for j = 0; j < all.length(); j = j + 1 {
      if combined_set[i] == all[j].name {
        found = true
      }
    }
    inspect(found, content="true")
  }
  // 3. migrations() is sorted by name (chronological order preserved)
  let names : Array[String] = []
  for i = 0; i < all.length(); i = i + 1 {
    names.push(all[i].name)
  }
  inspect(
    names,
    content="[\"001_mega_legendsza\", \"002_champions_pokemon\", \"003_champions_moves\", \"004_champions_learnset\", \"005_champions_learnset_normalize\", \"006_move_meta\", \"007_mega_forms\", \"008_move_meta_ailment\", \"010_move_meta_posthit\", \"011_form_name_aliases\", \"012_gender_symbol_aliases\", \"013_items\"]",
  )
}

///|
test "migrations_champions hosts 013_items (P2-C #94)" {
  let cmp = migrations_champions()
  inspect(cmp.length() >= 1, content="true")
  let mut found = false
  for i = 0; i < cmp.length(); i = i + 1 {
    if cmp[i].name == "013_items" {
      found = true
    }
  }
  inspect(found, content="true")
}

///|
test "all current migrations live on pokedex.db" {
  let pdx = migrations_pokedex()
  // Every migration name from the original chronological list must be
  // present in migrations_pokedex.
  let expected = [
    "001_mega_legendsza", "002_champions_pokemon", "003_champions_moves",
    "004_champions_learnset", "005_champions_learnset_normalize",
    "006_move_meta", "007_mega_forms", "008_move_meta_ailment",
    "010_move_meta_posthit", "011_form_name_aliases",
    "012_gender_symbol_aliases",
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
