///|
fn run_write_teams(
  date : String,
  axis : String,
  force : Bool,
  publish : Bool,
) -> Unit {
  if !is_safe_path_component(axis) || !is_safe_path_component(date) {
    exit_error("Invalid characters in --axis or --date")
    return
  }
  let raw = pkdx_read_stdin()
  if raw.length() == 0 {
    exit_error("No input from stdin")
    return
  }
  let json = @json.parse(raw) catch {
    e => {
      exit_error("JSON parse error: " + e.to_string())
      return
    }
  }
  match @writer.validate_team_json(json) {
    Err(errors) => {
      let msg = "Validation errors (" +
        errors.length().to_string() +
        "):\n" +
        errors.map(fn(e) { "  - " + e }).join("\n")
      exit_error(msg)
      return
    }
    Ok(_) => ()
  }
  let doc = @writer.build_team_document(json, axis, date, publish~)
  let md = @markdown.serialize(doc)
  let base = "box/teams/" + axis + "-build-" + date
  let md_path = base + ".md"
  let meta_path = base + ".meta.json"
  // `edited: true` frontmatter を持つ手編集済み MD は --force なしでは上書きしない。
  // meta.json は常に更新 — 構造化データはビルダーが SSoT。
  let skip_md = if force {
    false
  } else {
    match @db.read_file(md_path) {
      Some(existing) => @writer.has_edit_lock(existing)
      None => false
    }
  }
  if !skip_md {
    let rc = pkdx_write_file(@db.to_c_bytes(md_path), @db.to_c_bytes(md))
    if rc != 0 {
      exit_error("Failed to write " + md_path)
      return
    }
  } else {
    pkdx_eprintln(
      @db.to_c_bytes(
        "Preserved hand-edited " +
        md_path +
        " (frontmatter edited: true). meta.json was updated. Re-run with --force to overwrite.",
      ),
    )
  }
  let meta = json.stringify()
  let rc2 = pkdx_write_file(@db.to_c_bytes(meta_path), @db.to_c_bytes(meta))
  if rc2 != 0 {
    exit_error("Failed to write " + meta_path)
  } else {
    println(md_path)
  }
}

///|
fn run_write_pokemon(name : String, file : String) -> Unit {
  if !is_safe_path_component(name) || !is_safe_path_component(file) {
    exit_error("Invalid characters in --name or --file")
    return
  }
  let raw = pkdx_read_stdin()
  if raw.length() == 0 {
    exit_error("No input from stdin")
    return
  }
  let json = @json.parse(raw) catch {
    e => {
      exit_error("JSON parse error: " + e.to_string())
      return
    }
  }
  match @writer.validate_pokemon_json(json) {
    Err(errors) => {
      let msg = "Validation errors (" +
        errors.length().to_string() +
        "):\n" +
        errors.map(fn(e) { "  - " + e }).join("\n")
      exit_error(msg)
      return
    }
    Ok(_) => ()
  }
  let doc = @writer.build_pokemon_document(json, name)
  let md = @markdown.serialize(doc)
  let base = "box/pokemons/" + name + "/" + file
  let md_path = base + ".md"
  let meta_path = base + ".meta.json"
  let rc = pkdx_write_file(@db.to_c_bytes(md_path), @db.to_c_bytes(md))
  if rc != 0 {
    exit_error("Failed to write " + md_path)
    return
  }
  let meta = json.stringify()
  let rc2 = pkdx_write_file(@db.to_c_bytes(meta_path), @db.to_c_bytes(meta))
  if rc2 != 0 {
    exit_error("Failed to write " + meta_path)
  } else {
    println(md_path)
  }
}

///|
fn run_import_check_cli() -> Unit {
  let raw = pkdx_read_stdin()
  if raw.length() == 0 {
    exit_error("No input from stdin")
    return
  }
  let input = @json.parse(raw) catch {
    e => {
      exit_error("JSON parse error: " + e.to_string())
      return
    }
  }
  match @writer.run_import_check(input) {
    Ok(j) => println(j.stringify())
    Err(msg) => exit_error(msg)
  }
}

///|
