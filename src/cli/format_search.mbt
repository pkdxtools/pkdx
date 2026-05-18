///|
/// Format search results as JSON.
fn search_to_json(results : Array[@db.SearchResult]) -> String {
  let mut s = "["
  for i = 0; i < results.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    let r = results[i]
    let t2 = if r.type2.length() > 0 { "\"" + r.type2 + "\"" } else { "null" }
    s = s +
      "{\"globalNo\":\"" +
      r.global_no +
      "\",\"name_ja\":\"" +
      r.name_ja +
      "\",\"type1\":\"" +
      r.type1 +
      "\",\"type2\":" +
      t2 +
      ",\"hp\":" +
      r.hp.to_string() +
      ",\"atk\":" +
      r.atk.to_string() +
      ",\"def\":" +
      r.def_.to_string() +
      ",\"spa\":" +
      r.spa.to_string() +
      ",\"spd\":" +
      r.spd.to_string() +
      ",\"spe\":" +
      r.spe.to_string() +
      ",\"bst\":" +
      r.bst.to_string() +
      "}"
  }
  s + "]"
}

///|
/// Format search results as a table.
fn search_to_table(results : Array[@db.SearchResult]) -> String {
  let mut s = pad_right("Name", 14) +
    pad_right("Type", 14) +
    pad_right("HP", 5) +
    pad_right("Atk", 5) +
    pad_right("Def", 5) +
    pad_right("SpA", 5) +
    pad_right("SpD", 5) +
    pad_right("Spe", 5) +
    "BST\n"
  s = s + "─".to_string().repeat(62) + "\n"
  for i = 0; i < results.length(); i = i + 1 {
    let r = results[i]
    let type_str = if r.type2.length() > 0 {
      r.type1 + "/" + r.type2
    } else {
      r.type1
    }
    s = s +
      pad_right(r.name_ja, 14) +
      pad_right(type_str, 14) +
      pad_right(r.hp.to_string(), 5) +
      pad_right(r.atk.to_string(), 5) +
      pad_right(r.def_.to_string(), 5) +
      pad_right(r.spa.to_string(), 5) +
      pad_right(r.spd.to_string(), 5) +
      pad_right(r.spe.to_string(), 5) +
      r.bst.to_string() +
      "\n"
  }
  s
}

///|
/// Output search results.
pub fn format_search(
  results : Array[@db.SearchResult],
  fmt : OutputFormat,
) -> String {
  match fmt {
    Json => search_to_json(results)
    Table => search_to_table(results)
  }
}
