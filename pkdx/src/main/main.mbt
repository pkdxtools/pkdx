///|
fn main {
  let args = @sys.get_cli_args()
  let cmd = match @cli.parse_args(args) {
    Ok(c) => c
    Err(e) => {
      println("Error: " + e)
      return
    }
  }
  match cmd {
    Help => println(@cli.format_help())
    Version => println("pkdx 0.1.0")
    Query(name~, version~, format~) => run_query(name, version, format)
    Moves(target~, version~, format~) => run_moves(target, version, format)
    Search(type1~, type2~, min_speed~, version~, format~) =>
      run_search(type1, type2, min_speed, version, format)
    TypeChart(move_type~, def_type1~, def_type2~) =>
      run_type_chart(move_type, def_type1, def_type2)
    Coverage(types~) => run_coverage(types)
    WriteTeams(date~, axis~) => run_write_teams(date, axis)
    WritePokemon(name~, file~) => run_write_pokemon(name, file)
    StatCalc(
      name~, evs~, ivs~, nature~, nature_up~, nature_down~, version~, format~
    ) =>
      run_stat_calc(
        name, evs, ivs, nature, nature_up, nature_down, version, format,
      )
    StatReverse(
      target~, stats~, iv~, ev~, nature_mod~, is_hp~, version~, format~
    ) => run_stat_reverse(target, stats, iv, ev, nature_mod, is_hp, version, format)
    Damage(
      attacker~,
      defender~,
      move_name~,
      version~,
      format~,
      atk_ability~,
      def_ability~,
      atk_item~,
      def_item~,
      weather~,
      field~,
      tera_type~,
      critical~,
      atk_stat~,
      def_stat~,
      def_hp~
    ) =>
      run_damage(
        attacker, defender, move_name, version, format, atk_ability, def_ability,
        atk_item, def_item, weather, field, tera_type, critical, atk_stat, def_stat,
        def_hp,
      )
  }
}

///|
fn[T] with_db(f : (@db.Db) -> T) -> T {
  let db_path = match resolve_db_path() {
    Ok(p) => p
    Err(e) => {
      println("Error: " + e)
      panic()
    }
  }
  let db = match @db.open(db_path) {
    Ok(d) => d
    Err(e) => {
      println("Error: " + e)
      panic()
    }
  }
  match @db.validate_schema(db) {
    Ok(_) => ()
    Err(e) => {
      println("Error: " + e)
      @db.close(db)
      panic()
    }
  }
  let result = f(db)
  @db.close(db)
  result
}

///|
fn run_query(
  name : String,
  version : String,
  format : @cli.OutputFormat,
) -> Unit {
  with_db(fn(db) {
    match @db.query_pokemon(db, name, version) {
      Ok(p) => println(@cli.format_pokemon(p, format))
      Err(e) => println("Error: " + e)
    }
  })
}

///|
fn run_moves(
  target : String,
  version : String,
  format : @cli.OutputFormat,
) -> Unit {
  with_db(fn(db) {
    // If target looks like a number, use it as globalNo directly.
    // Otherwise, look up the Pokemon first to get globalNo.
    let global_no = if is_numeric(target) {
      @db.normalize_global_no(target)
    } else {
      match @db.query_pokemon(db, target, version) {
        Ok(p) => p.global_no
        Err(e) => {
          println("Error: " + e)
          return
        }
      }
    }
    match @db.query_moves(db, global_no, version) {
      Ok(moves) => println(@cli.format_moves(moves, format))
      Err(e) => println("Error: " + e)
    }
  })
}

///|
fn run_search(
  type1 : String,
  type2 : String,
  min_speed : Int,
  version : String,
  format : @cli.OutputFormat,
) -> Unit {
  with_db(fn(db) {
    match @db.search_by_type(db, type1, type2, min_speed, version) {
      Ok(results) => println(@cli.format_search(results, format))
      Err(e) => println("Error: " + e)
    }
  })
}

///|
fn run_damage(
  attacker_name : String,
  defender_name : String,
  move_name : String,
  version : String,
  format : @cli.OutputFormat,
  atk_ability : String,
  def_ability : String,
  atk_item : String,
  def_item : String,
  weather : String,
  field : String,
  tera_type : String,
  critical : Bool,
  atk_stat : Int,
  def_stat : Int,
  def_hp : Int,
) -> Unit {
  with_db(fn(db) {
    let atk_pokemon = match @db.query_pokemon(db, attacker_name, version) {
      Ok(p) => p
      Err(e) => {
        println("Error: " + e)
        return
      }
    }
    let def_pokemon = match @db.query_pokemon(db, defender_name, version) {
      Ok(p) => p
      Err(e) => {
        println("Error: " + e)
        return
      }
    }
    let move_ = match @db.query_move(db, move_name, version) {
      Ok(m) => m
      Err(e) => {
        println("Error: " + e)
        return
      }
    }
    let input = @model.DamageCalcInput::{
      attacker: atk_pokemon,
      defender: def_pokemon,
      move_,
      atk_ability,
      def_ability,
      atk_item,
      def_item,
      weather: @model.weather_from_jp(weather),
      field: @model.field_from_jp(field),
      tera_type,
      critical,
      atk_stat_override: atk_stat,
      def_stat_override: def_stat,
      def_hp_override: def_hp,
    }
    let result = @damage.calc_damage(input)
    println(@cli.format_damage(result, input, format))
  })
}

///|
fn run_type_chart(
  move_type : String,
  def_type1 : String,
  def_type2 : String,
) -> Unit {
  let atk = match @types.type_from_jp(move_type) {
    Some(t) => t
    None => {
      println("Error: Unknown type: " + move_type)
      return
    }
  }
  let d1 = match @types.type_from_jp(def_type1) {
    Some(t) => t
    None => {
      println("Error: Unknown type: " + def_type1)
      return
    }
  }
  let d2 : @types.PokemonType? = if def_type2.length() > 0 {
    match @types.type_from_jp(def_type2) {
      Some(t) => Some(t)
      None => {
        println("Error: Unknown type: " + def_type2)
        return
      }
    }
  } else {
    None
  }
  let eff = @types.get_dual_effectiveness(atk, d1, d2)
  let def_str = match d2 {
    Some(t2) => def_type1 + "/" + @types.type_to_jp(t2)
    None => def_type1
  }
  println(move_type + " -> " + def_str + ": " + format_effectiveness(eff))
}

///|
fn format_effectiveness(eff : Double) -> String {
  if eff == 0.0 {
    "0x (immune)"
  } else if eff == 0.25 {
    "0.25x"
  } else if eff == 0.5 {
    "0.5x"
  } else if eff == 1.0 {
    "1x"
  } else if eff == 2.0 {
    "2x"
  } else if eff == 4.0 {
    "4x"
  } else {
    eff.to_string() + "x"
  }
}

///|
fn run_coverage(types : Array[String]) -> Unit {
  let atk_types : Array[@types.PokemonType] = []
  for i = 0; i < types.length(); i = i + 1 {
    match @types.type_from_jp(types[i]) {
      Some(t) => atk_types.push(t)
      None => {
        println("Error: Unknown type: " + types[i])
        return
      }
    }
  }
  let result = @types.calc_coverage(atk_types)
  let mut type_names = ""
  for i = 0; i < types.length(); i = i + 1 {
    if i > 0 {
      type_names = type_names + ", "
    }
    type_names = type_names + types[i]
  }
  println("Coverage for [" + type_names + "]:")
  let pct = (result.coverage_rate * 100.0).to_int().to_string()
  println(
    "  Neutral+ coverage: " +
    result.covered.length().to_string() +
    "/18 (" +
    pct +
    "%)",
  )
  if result.not_covered.length() > 0 {
    let mut nc = ""
    for i = 0; i < result.not_covered.length(); i = i + 1 {
      if i > 0 {
        nc = nc + ", "
      }
      nc = nc + @types.type_to_jp(result.not_covered[i])
    }
    println("  Not covered: " + nc)
  }
}

///|
fn resolve_db_path() -> Result[String, String] {
  match @sys.get_env_var("POKEDEX_DB") {
    Some(path) => return Ok(path)
    None => ()
  }
  let candidates = ["pokedex/pokedex.db", "../pokedex/pokedex.db"]
  for i = 0; i < candidates.length(); i = i + 1 {
    let path = candidates[i]
    match @db.open(path) {
      Ok(db) => {
        @db.close(db)
        return Ok(path)
      }
      Err(_) => continue
    }
  }
  Err(
    "pokedex.db not found. Set POKEDEX_DB environment variable or run from repo root.",
  )
}

///|
fn is_numeric(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 0x30 || c > 0x39 {
      return false
    }
  }
  true
}

///|
fn is_safe_path_component(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    // prevent directory traversal via user-supplied path components
    if c == 0x2F || c == 0x5C {
      return false
    }
  }
  for i = 0; i < s.length() - 1; i = i + 1 {
    if s[i].to_int() == 0x2E && s[i + 1].to_int() == 0x2E {
      return false
    }
  }
  true
}

///|
fn exit_error(msg : String) -> Unit {
  pkdx_eprintln(@db.to_c_bytes("Error: " + msg))
  pkdx_exit(1)
}

///|
fn run_write_teams(date : String, axis : String) -> Unit {
  if !(is_safe_path_component(axis)) || !(is_safe_path_component(date)) {
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
  let doc = @writer.build_team_document(json, axis, date)
  let md = @markdown.serialize(doc)
  let path = "box/teams/" + axis + "-build-" + date + ".md"
  let rc = pkdx_write_file(@db.to_c_bytes(path), @db.to_c_bytes(md))
  if rc != 0 {
    exit_error("Failed to write " + path)
  } else {
    println(path)
  }
}

///|
fn run_write_pokemon(name : String, file : String) -> Unit {
  if !(is_safe_path_component(name)) || !(is_safe_path_component(file)) {
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
  let path = "box/pokemons/" + name + "/" + file + ".md"
  let rc = pkdx_write_file(@db.to_c_bytes(path), @db.to_c_bytes(md))
  if rc != 0 {
    exit_error("Failed to write " + path)
  } else {
    println(path)
  }
}

///|
fn parse_csv_ints(s : String, default_val : Int, count : Int) -> FixedArray[Int] {
  let result : FixedArray[Int] = FixedArray::make(count, default_val)
  if s.length() == 0 {
    return result
  }
  // Check if contains comma
  let mut has_comma = false
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ',' {
      has_comma = true
      break
    }
  }
  if has_comma {
    let mut idx = 0
    let mut start = 0
    for i = 0; i <= s.length(); i = i + 1 {
      if i == s.length() || s[i] == ',' {
        if idx < count && i > start {
          result[idx] = parse_int_from_str(s[start:i].to_string(), default_val)
        }
        idx = idx + 1
        start = i + 1
      }
    }
  } else {
    // Single value applied to all
    let val = parse_int_from_str(s, default_val)
    for i = 0; i < count; i = i + 1 {
      result[i] = val
    }
  }
  result
}

///|
fn parse_int_from_str(s : String, default : Int) -> Int {
  let mut result = 0
  let mut i = 0
  let mut negative = false
  if i < s.length() && s[i] == '-' {
    negative = true
    i = i + 1
  }
  let mut has_digit = false
  while i < s.length() {
    let c = s[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      result = result * 10 + (c - 0x30)
      has_digit = true
    } else {
      break
    }
    i = i + 1
  }
  if not(has_digit) {
    return default
  }
  if negative { -result } else { result }
}

///|
fn resolve_nature(
  nature_name : String,
  nature_up : String,
  nature_down : String,
) -> @model.Nature {
  // Priority 1: Japanese nature name
  if nature_name.length() > 0 {
    match @model.nature_from_ja(nature_name) {
      Some(n) => return n
      None => {
        println("Warning: Unknown nature '" + nature_name + "', using neutral")
      }
    }
  }
  // Priority 2: up/down stat specification
  if nature_up.length() > 0 && nature_down.length() > 0 {
    let up = @model.stat_index_from_str(nature_up)
    let down = @model.stat_index_from_str(nature_down)
    match (up, down) {
      (Some(u), Some(d)) =>
        return {
          name_ja: nature_up + "↑" + nature_down + "↓",
          name_en: "Custom",
          up: Some(u),
          down: Some(d),
        }
      _ =>
        println(
          "Warning: Unknown stat '" +
          nature_up +
          "'/'" +
          nature_down +
          "', using neutral",
        )
    }
  }
  // Default: neutral (Hardy)
  { name_ja: "がんばりや", name_en: "Hardy", up: None, down: None }
}

///|
fn run_stat_calc(
  name : String,
  evs_str : String,
  ivs_str : String,
  nature_name : String,
  nature_up : String,
  nature_down : String,
  version : String,
  format : @cli.OutputFormat,
) -> Unit {
  let evs = parse_csv_ints(evs_str, 0, 6)
  let ivs = parse_csv_ints(ivs_str, 31, 6)
  let nature = resolve_nature(nature_name, nature_up, nature_down)
  with_db(fn(db) {
    match @db.query_pokemon(db, name, version) {
      Ok(pokemon) => {
        let stats = @damage.calc_all_stats(pokemon, ivs, evs, nature)
        println(@cli.format_stat_calc(pokemon, stats, nature, ivs, evs, format))
      }
      Err(e) => println("Error: " + e)
    }
  })
}

///|
fn run_stat_reverse(
  target : String,
  stats_str : String,
  iv : Int,
  ev : Int,
  nature_mod : String,
  is_hp : Bool,
  version : String,
  format : @cli.OutputFormat,
) -> Unit {
  if stats_str.length() > 0 {
    // Pokemon mode
    let actual_stats = parse_csv_ints(stats_str, 0, 6)
    with_db(fn(db) {
      match @db.query_pokemon(db, target, version) {
        Ok(pokemon) => {
          let results = @damage.reverse_spread(pokemon, actual_stats, iv)
          println(
            @cli.format_stat_reverse_pokemon(
              pokemon, actual_stats, results, format,
            ),
          )
        }
        Err(e) => println("Error: " + e)
      }
    })
  } else {
    // Single stat mode
    let actual = parse_int_from_str(target, 0)
    if actual <= 0 {
      println("Error: Invalid stat value '" + target + "'")
      return
    }
    let (nature_num, nature_den) = match nature_mod {
      "up" => (11, 10)
      "down" => (9, 10)
      _ => (1, 1)
    }
    let base = @damage.reverse_base_from_stat(
      actual, iv, ev, is_hp, nature_num, nature_den,
    )
    println(
      @cli.format_stat_reverse_single(actual, base, iv, ev, is_hp, nature_mod, format),
    )
  }
}
