///|
fn main {
  // @sys.get_cli_args() returns the program name as the first element. admiral
  // expects argv to begin with the first user-supplied token, so strip args[0]
  // before normalization. The normalizer then restores the legacy behaviors of
  // bare `pkdx`, `pkdx help`, and `pkdx version`, which admiral does not
  // provide on its own.
  let raw = @sys.get_cli_args()
  let user_args : Array[String] = []
  for i = 1; i < raw.length(); i = i + 1 {
    user_args.push(raw[i])
  }
  let argv = @cli.normalize_argv(user_args)
  let app = build_cli()
  try {
    app.run(argv=Some(argv))
  } catch {
    err => {
      pkdx_eprintln(@db.to_c_bytes("Error: " + err.to_string()))
      pkdx_exit(1)
    }
  }
}

///|
/// Read a string option/positional that admiral guarantees to populate
/// (either because the option was declared with `default=Some(...)` or the
/// positional was declared `required=true`). Crashes loudly if the key is
/// missing — this indicates a programming error (typo, or a caller forgot to
/// declare the option), not a user error.
fn ctx_str(ctx : @admiral.Context, name : String) -> String {
  match ctx.get_string(name) {
    Some(s) => s
    None => {
      println("Internal error: missing CLI value for '" + name + "'")
      panic()
    }
  }
}

///|
/// Read an optional string — returns "" when the flag was not supplied and
/// no default is registered with admiral. Use for truly optional flags such
/// as `--nature`, `--atk-ability`, etc. where empty string is the sentinel
/// for "not set" throughout the codebase.
fn ctx_str_opt(ctx : @admiral.Context, name : String) -> String {
  ctx.get_string(name).unwrap_or("")
}

///|
/// Read an int option. Same contract as `ctx_str`: the option must have been
/// declared with `default=Some(...)` so admiral always populates a value.
fn ctx_int(ctx : @admiral.Context, name : String) -> Int {
  match ctx.get_int(name) {
    Some(n) => n
    None => {
      println("Internal error: missing CLI value for '" + name + "'")
      panic()
    }
  }
}

///|
/// Read --format option as OutputFormat. All commands declare `--format`
/// with default="table", so ctx_str is safe here.
fn ctx_format(ctx : @admiral.Context) -> @cli.OutputFormat {
  @cli.parse_output_format(ctx_str(ctx, "format"))
}

///|
fn version_option() -> @admiral.OptionDef {
  @admiral.string(
    "version", description="Game version", default=Some("champions"),
  )
}

///|
fn regulation_option() -> @admiral.OptionDef {
  @admiral.string(
    "regulation",
    description="Regulation filter (e.g. M-A). Only valid with --version champions",
    default=Some(""),
  )
}

///|
fn format_option() -> @admiral.OptionDef {
  @admiral.string(
    "format", description="Output format: json|table", default=Some("table"),
  )
}

///|
pub(all) struct GameContext {
  version : String
  regulation : String
}

///|
/// Build GameContext from CLI context. Validates that --regulation is only used with --version champions.
fn ctx_game(ctx : @admiral.Context) -> GameContext {
  let version = ctx_str(ctx, "version")
  let regulation = ctx_str_opt(ctx, "regulation")
  if regulation != "" && version != "champions" {
    pkdx_eprintln(
      @db.to_c_bytes(
        "Error: --regulation is only valid with --version champions",
      ),
    )
    pkdx_exit(1)
  }
  { version, regulation }
}

///|
fn build_cli() -> @admiral.CliApp {
  @admiral.cli(
    name="pkdx",
    version=pkdx_version,
    description="Pokedex CLI tool",
    commands=[
      cmd_query(),
      cmd_moves(),
      cmd_search(),
      cmd_type_chart(),
      cmd_coverage(),
      cmd_damage(),
      cmd_write(),
      cmd_stat_calc(),
      cmd_stat_reverse(),
      cmd_init_cache(),
      cmd_hbd(),
    ],
  )
}

///|
fn cmd_query() -> @admiral.CommandDef {
  @admiral.command(
    name="query",
    description="Look up a Pokemon by name or globalNo",
    options=[version_option(), regulation_option(), format_option()],
    positionals=[
      @admiral.positional(
        "name", description="Pokemon name (ja or en)", required=true,
      ),
    ],
    examples=["pkdx query ガブリアス --format json"],
    run=Some(fn(ctx) {
      run_query(ctx_str(ctx, "name"), ctx_game(ctx), ctx_format(ctx))
    }),
  )
}

///|
fn cmd_moves() -> @admiral.CommandDef {
  @admiral.command(
    name="moves",
    description="List moves a Pokemon can learn",
    options=[version_option(), regulation_option(), format_option()],
    positionals=[
      @admiral.positional(
        "target",
        description="Pokemon name or globalNo",
        required=true,
      ),
    ],
    run=Some(fn(ctx) {
      run_moves(ctx_str(ctx, "target"), ctx_game(ctx), ctx_format(ctx))
    }),
  )
}

///|
fn cmd_search() -> @admiral.CommandDef {
  @admiral.command(
    name="search",
    description="Search Pokemon by type and minimum speed",
    options=[
      @admiral.string("type", description="Primary type (ja)", required=true),
      @admiral.string("type2", description="Secondary type (ja)", default=Some("")),
      @admiral.int("min-speed", description="Minimum base speed", default=Some(0)),
      version_option(),
      regulation_option(),
      format_option(),
    ],
    run=Some(fn(ctx) {
      run_search(
        ctx_str(ctx, "type"),
        ctx_str(ctx, "type2"),
        ctx_int(ctx, "min-speed"),
        ctx_game(ctx),
        ctx_format(ctx),
      )
    }),
  )
}

///|
fn cmd_type_chart() -> @admiral.CommandDef {
  @admiral.command(
    name="type-chart",
    description="Show type effectiveness multiplier",
    positionals=[
      @admiral.positional(
        "move_type", description="Attacking move type", required=true,
      ),
      @admiral.positional(
        "def_types",
        description="Defender type(s), comma-separated for dual type (e.g. 'ひこう,はがね')",
        required=true,
      ),
    ],
    run=Some(fn(ctx) {
      run_type_chart(ctx_str(ctx, "move_type"), ctx_str(ctx, "def_types"))
    }),
  )
}

///|
fn cmd_coverage() -> @admiral.CommandDef {
  @admiral.command(
    name="coverage",
    description="Compute neutral+ coverage rate of a list of attacking types",
    positionals=[
      @admiral.positional(
        "types",
        description="Comma-separated type list (ja), e.g. 'ほのお,みず,くさ'",
        required=true,
      ),
    ],
    run=Some(fn(ctx) {
      run_coverage(@cli.split_csv(ctx_str(ctx, "types")))
    }),
  )
}

///|
fn cmd_damage() -> @admiral.CommandDef {
  @admiral.command(
    name="damage",
    description="Compute Lv50 damage roll",
    options=[
      version_option(),
      regulation_option(),
      format_option(),
      @admiral.string("atk-ability", description="Attacker ability (ja)", default=Some("")),
      @admiral.string("def-ability", description="Defender ability (ja)", default=Some("")),
      @admiral.string("atk-item", description="Attacker held item (ja)", default=Some("")),
      @admiral.string("def-item", description="Defender held item (ja)", default=Some("")),
      @admiral.string("weather", description="Weather (ja): はれ|あめ|すなあらし|ゆき", default=Some("")),
      @admiral.string("field", description="Terrain (ja): エレキ|グラス|ミスト|サイコ", default=Some("")),
      @admiral.string("tera-type", description="Tera type (ja)", default=Some("")),
      @admiral.bool("critical", description="Treat the hit as a critical"),
      @admiral.int("atk-stat", description="Override attacker attack/special stat", default=Some(0)),
      @admiral.int("def-stat", description="Override defender defense/special stat", default=Some(0)),
      @admiral.int("def-hp", description="Override defender HP", default=Some(0)),
      @admiral.int("atk-rank", description="Attacker stat stage (-6..+6). For Body Press this is the Defense stage", default=Some(0)),
      @admiral.int("def-rank", description="Defender stat stage (-6..+6)", default=Some(0)),
    ],
    positionals=[
      @admiral.positional("attacker", description="Attacker Pokemon name", required=true),
      @admiral.positional("defender", description="Defender Pokemon name", required=true),
      @admiral.positional("move", description="Move name", required=true),
    ],
    run=Some(fn(ctx) {
      // Convert string CLI values to domain enums at the ADT boundary, before
      // handing them to run_damage. This matches the `weather_from_jp` /
      // `field_from_jp` idiom used elsewhere in the project.
      let weather = @model.weather_from_jp(ctx_str(ctx, "weather"))
      let field = @model.field_from_jp(ctx_str(ctx, "field"))
      run_damage(
        ctx_str(ctx, "attacker"),
        ctx_str(ctx, "defender"),
        ctx_str(ctx, "move"),
        ctx_game(ctx),
        ctx_format(ctx),
        ctx_str(ctx, "atk-ability"),
        ctx_str(ctx, "def-ability"),
        ctx_str(ctx, "atk-item"),
        ctx_str(ctx, "def-item"),
        weather,
        field,
        ctx_str(ctx, "tera-type"),
        ctx.get_bool("critical"),
        ctx_int(ctx, "atk-stat"),
        ctx_int(ctx, "def-stat"),
        ctx_int(ctx, "def-hp"),
        ctx_int(ctx, "atk-rank"),
        ctx_int(ctx, "def-rank"),
      )
    }),
  )
}

///|
fn cmd_write() -> @admiral.CommandDef {
  @admiral.command(
    name="write",
    description="Write skill cache JSON (stdin) to a markdown file",
    subcommands=[
      @admiral.command(
        name="teams",
        description="Write a team build report to box/teams/",
        options=[
          @admiral.string("date", description="YYYY-MM-DD", required=true),
          @admiral.string("axis", description="Axis Pokemon name", required=true),
        ],
        run=Some(fn(ctx) {
          run_write_teams(ctx_str(ctx, "date"), ctx_str(ctx, "axis"))
        }),
      ),
      @admiral.command(
        name="pokemon",
        description="Write a Pokemon build to box/pokemons/",
        options=[
          @admiral.string("name", description="Pokemon name", required=true),
          @admiral.string("file", description="Output filename (no extension)", required=true),
        ],
        run=Some(fn(ctx) {
          run_write_pokemon(ctx_str(ctx, "name"), ctx_str(ctx, "file"))
        }),
      ),
    ],
  )
}

///|
fn cmd_stat_calc() -> @admiral.CommandDef {
  @admiral.command(
    name="stat-calc",
    description="Compute Lv50 stats from base + EV/IV + nature",
    options=[
      @admiral.string("ev", description="EVs as 'H,A,B,C,D,S'", default=Some("")),
      @admiral.string("iv", description="IVs as 'H,A,B,C,D,S' or single value", default=Some("")),
      @admiral.string("nature", description="Nature name (ja)", default=Some("")),
      @admiral.string("nature-up", description="Stat that nature boosts", default=Some("")),
      @admiral.string("nature-down", description="Stat that nature lowers", default=Some("")),
      version_option(),
      regulation_option(),
      format_option(),
    ],
    positionals=[
      @admiral.positional("name", description="Pokemon name (ja or en)", required=true),
    ],
    run=Some(fn(ctx) {
      run_stat_calc(
        ctx_str(ctx, "name"),
        ctx_str(ctx, "ev"),
        ctx_str(ctx, "iv"),
        ctx_str(ctx, "nature"),
        ctx_str(ctx, "nature-up"),
        ctx_str(ctx, "nature-down"),
        ctx_game(ctx),
        ctx_format(ctx),
      )
    }),
  )
}

///|
fn cmd_stat_reverse() -> @admiral.CommandDef {
  @admiral.command(
    name="stat-reverse",
    description="Reverse-derive base stat (single mode) or EV spread (pokemon mode)",
    options=[
      @admiral.string("stats", description="Actual stats 'H,A,B,C,D,S' (pokemon mode)", default=Some("")),
      @admiral.int("iv", description="IV", default=Some(31)),
      @admiral.int("ev", description="EV", default=Some(0)),
      @admiral.string("nature", description="Nature mod: up|down|neutral", default=Some("neutral")),
      @admiral.bool("hp", description="Treat target as HP stat (single mode)"),
      version_option(),
      regulation_option(),
      format_option(),
    ],
    positionals=[
      @admiral.positional(
        "target", description="Stat value (single mode) or Pokemon name (pokemon mode)", required=true,
      ),
    ],
    run=Some(fn(ctx) {
      run_stat_reverse(
        ctx_str(ctx, "target"),
        ctx_str(ctx, "stats"),
        ctx_int(ctx, "iv"),
        ctx_int(ctx, "ev"),
        ctx_str(ctx, "nature"),
        ctx.get_bool("hp"),
        ctx_game(ctx),
        ctx_format(ctx),
      )
    }),
  )
}

///|
fn cmd_init_cache() -> @admiral.CommandDef {
  @admiral.command(
    name="init-cache",
    description="Output a placeholder JSON skeleton for skill caches",
    subcommands=[
      @admiral.command(
        name="team",
        description="Team cache placeholder",
        run=Some(fn(_ctx) { run_init_cache_team() }),
      ),
      @admiral.command(
        name="pokemon",
        description="Pokemon cache placeholder",
        run=Some(fn(_ctx) { run_init_cache_pokemon() }),
      ),
    ],
  )
}

///|
fn cmd_hbd() -> @admiral.CommandDef {
  @admiral.command(
    name="hbd",
    description="Optimize H/B/D EV spread under HBD/(p*B+s*D) objective",
    options=[
      @admiral.string("fixed-ev", description="Fixed EVs 'H,A,B,C,D,S' (_ to optimize)", default=Some("")),
      @admiral.string("iv", description="IVs as 'H,A,B,C,D,S' or single value", default=Some("")),
      @admiral.string("nature", description="Nature name (ja)", default=Some("")),
      @admiral.string("nature-up", description="Stat that nature boosts", default=Some("")),
      @admiral.string("nature-down", description="Stat that nature lowers", default=Some("")),
      @admiral.string("hp-snap", description="HP snap mode: none|leftovers|residual|sitrus|lifeorb", default=Some("none")),
      @admiral.int("phys-weight", description="Weight applied to B term", default=Some(1)),
      @admiral.int("spec-weight", description="Weight applied to D term", default=Some(1)),
      @admiral.int("top", description="Number of candidates to return", default=Some(1)),
      version_option(),
      regulation_option(),
      format_option(),
    ],
    positionals=[
      @admiral.positional("name", description="Pokemon name (ja or en)", required=true),
    ],
    run=Some(fn(ctx) {
      // Convert --hp-snap string to the HpSnap ADT at the CLI boundary.
      // Unknown values are a user error, not a programming error, so print
      // and exit instead of panicking.
      let hp_snap_str = ctx_str(ctx, "hp-snap")
      let snap = match @model.hp_snap_from_str(hp_snap_str) {
        Some(s) => s
        None => {
          exit_error("unknown --hp-snap value '" + hp_snap_str + "'")
          return
        }
      }
      run_hbd(
        ctx_str(ctx, "name"),
        ctx_str(ctx, "fixed-ev"),
        ctx_str(ctx, "iv"),
        ctx_str(ctx, "nature"),
        ctx_str(ctx, "nature-up"),
        ctx_str(ctx, "nature-down"),
        snap,
        ctx_int(ctx, "phys-weight"),
        ctx_int(ctx, "spec-weight"),
        ctx_int(ctx, "top"),
        ctx_game(ctx),
        ctx_format(ctx),
      )
    }),
  )
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
  game : GameContext,
  format : @cli.OutputFormat,
) -> Unit {
  with_db(fn(db) {
    match @db.query_pokemon(db, name, game.version) {
      Ok(p) => println(@cli.format_pokemon(p, format))
      Err(e) => println("Error: " + e)
    }
  })
}

///|
fn run_moves(
  target : String,
  game : GameContext,
  format : @cli.OutputFormat,
) -> Unit {
  with_db(fn(db) {
    let global_no = if is_numeric(target) {
      @db.normalize_global_no(target)
    } else {
      match @db.query_pokemon(db, target, game.version) {
        Ok(p) => p.global_no
        Err(e) => {
          println("Error: " + e)
          return
        }
      }
    }
    match @db.query_moves(db, global_no, game.version) {
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
  game : GameContext,
  format : @cli.OutputFormat,
) -> Unit {
  with_db(fn(db) {
    match @db.search_by_type(db, type1, type2, min_speed, game.version) {
      Ok(results) => {
        let filtered = if game.regulation != "" {
          results.filter(fn(p) { @db.is_available(p.global_no, game.regulation) })
        } else {
          results
        }
        println(@cli.format_search(filtered, format))
      }
      Err(e) => println("Error: " + e)
    }
  })
}

///|
fn run_damage(
  attacker_name : String,
  defender_name : String,
  move_name : String,
  game : GameContext,
  format : @cli.OutputFormat,
  atk_ability : String,
  def_ability : String,
  atk_item : String,
  def_item : String,
  weather : @model.Weather,
  field : @model.Field,
  tera_type : String,
  critical : Bool,
  atk_stat : Int,
  def_stat : Int,
  def_hp : Int,
  atk_rank : Int,
  def_rank : Int,
) -> Unit {
  if atk_rank < -6 || atk_rank > 6 {
    println("Error: --atk-rank must be in [-6, 6]")
    return
  }
  if def_rank < -6 || def_rank > 6 {
    println("Error: --def-rank must be in [-6, 6]")
    return
  }
  with_db(fn(db) {
    let atk_pokemon = match @db.query_pokemon(db, attacker_name, game.version) {
      Ok(p) => p
      Err(e) => {
        println("Error: " + e)
        return
      }
    }
    let def_pokemon = match @db.query_pokemon(db, defender_name, game.version) {
      Ok(p) => p
      Err(e) => {
        println("Error: " + e)
        return
      }
    }
    let move_ = match @db.query_move(db, move_name, game.version) {
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
      atk_rank,
      def_rank,
    }
    let result = @damage.calc_damage(input)
    println(@cli.format_damage(result, input, format))
  })
}

///|
fn run_type_chart(move_type : String, def_types_csv : String) -> Unit {
  let atk = match @types.type_from_jp(move_type) {
    Some(t) => t
    None => {
      println("Error: Unknown type: " + move_type)
      return
    }
  }
  let parts = @cli.split_csv(def_types_csv)
  if parts.length() == 0 || parts.length() > 2 {
    println("Error: Specify 1 or 2 defender types (comma-separated), got " + parts.length().to_string())
    return
  }
  let d1 = match @types.type_from_jp(parts[0]) {
    Some(t) => t
    None => {
      println("Error: Unknown type: " + parts[0])
      return
    }
  }
  let d2 : @types.PokemonType? = if parts.length() == 2 {
    match @types.type_from_jp(parts[1]) {
      Some(t) => Some(t)
      None => {
        println("Error: Unknown type: " + parts[1])
        return
      }
    }
  } else {
    None
  }
  let eff = @types.get_dual_effectiveness(atk, d1, d2)
  let def_str = match d2 {
    Some(t2) => parts[0] + "/" + @types.type_to_jp(t2)
    None => parts[0]
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
/// Print an error to stderr and terminate with exit code 1. Never returns at
/// runtime: the trailing panic() is a guard in case the FFI exit call ever
/// returns unexpectedly. Callers still include an explicit `return` after
/// calling this, as a readability marker — moonbit's type system cannot
/// express "does not return" across an FFI boundary, so the explicit return
/// makes the control flow unambiguous to readers.
fn exit_error(msg : String) -> Unit {
  pkdx_eprintln(@db.to_c_bytes("Error: " + msg))
  pkdx_exit(1)
  panic()
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
  game : GameContext,
  format : @cli.OutputFormat,
) -> Unit {
  let evs = @cli.parse_csv_ints(evs_str, 0, 6)
  let ivs = @cli.parse_csv_ints(ivs_str, 31, 6)
  let nature = resolve_nature(nature_name, nature_up, nature_down)
  with_db(fn(db) {
    match @db.query_pokemon(db, name, game.version) {
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
  game : GameContext,
  format : @cli.OutputFormat,
) -> Unit {
  if stats_str.length() > 0 {
    // Pokemon mode
    let actual_stats = @cli.parse_csv_ints(stats_str, 0, 6)
    with_db(fn(db) {
      match @db.query_pokemon(db, target, game.version) {
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
    let actual = @cli.parse_int(target, 0)
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

///|
fn run_init_cache_team() -> Unit {
  println(@writer.generate_team_placeholder().stringify())
}

///|
fn run_init_cache_pokemon() -> Unit {
  println(@writer.generate_pokemon_placeholder().stringify())
}

///|
fn run_hbd(
  name : String,
  fixed_ev_str : String,
  ivs_str : String,
  nature_name : String,
  nature_up : String,
  nature_down : String,
  snap : @model.HpSnap,
  phys_weight : Int,
  spec_weight : Int,
  top : Int,
  game : GameContext,
  format : @cli.OutputFormat,
) -> Unit {
  // Default fixed_ev: optimize H/B/D, zero A/C/S.
  let fixed_ev = if fixed_ev_str.length() == 0 {
    let arr : FixedArray[Int] = FixedArray::make(6, 0)
    arr[0] = -1
    arr[2] = -1
    arr[4] = -1
    arr
  } else {
    match @cli.parse_fixed_ev(fixed_ev_str) {
      Ok(arr) => arr
      Err(e) => {
        println("Error: " + e)
        return
      }
    }
  }
  let ivs = @cli.parse_csv_ints(ivs_str, 31, 6)
  let nature = resolve_nature(nature_name, nature_up, nature_down)
  let weights : @damage.HbdWeights = { phys: phys_weight, spec: spec_weight }
  with_db(fn(db) {
    match @db.query_pokemon(db, name, game.version) {
      Ok(pokemon) => {
        let result = if top <= 1 {
          @damage.optimize_hbd(pokemon, fixed_ev, ivs, nature, snap, weights)
        } else {
          @damage.optimize_hbd_topn(
            pokemon, fixed_ev, ivs, nature, snap, weights, top,
          )
        }
        println(@cli.format_hbd(pokemon, nature, snap, weights, result, format))
      }
      Err(e) => println("Error: " + e)
    }
  })
}
