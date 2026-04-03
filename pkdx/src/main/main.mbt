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
      def_hp~,
    ) =>
      run_damage(
        attacker, defender, move_name, version, format, atk_ability,
        def_ability, atk_item, def_item, weather, field, tera_type, critical,
        atk_stat, def_stat, def_hp,
      )
  }
}

fn with_db[T](f : (@db.Db) -> T) -> T {
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

fn run_query(name : String, version : String, format : @cli.OutputFormat) -> Unit {
  with_db(fn(db) {
    match @db.query_pokemon(db, name, version) {
      Ok(p) => println(@cli.format_pokemon(p, format))
      Err(e) => println("Error: " + e)
    }
  })
}

fn run_moves(
  target : String,
  version : String,
  format : @cli.OutputFormat
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

fn run_search(
  type1 : String,
  type2 : String,
  min_speed : Int,
  version : String,
  format : @cli.OutputFormat
) -> Unit {
  with_db(fn(db) {
    match @db.search_by_type(db, type1, type2, min_speed, version) {
      Ok(results) => println(@cli.format_search(results, format))
      Err(e) => println("Error: " + e)
    }
  })
}

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
  def_hp : Int
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
      weather,
      field,
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

fn run_type_chart(
  move_type : String,
  def_type1 : String,
  def_type2 : String
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
    "  Neutral+ coverage: " + result.covered.length().to_string() + "/18 (" +
    pct + "%)",
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
