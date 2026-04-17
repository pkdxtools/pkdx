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
      cmd_import_check(),
      cmd_hbd(),
      cmd_learners(),
      cmd_nash(),
      cmd_select(),
      cmd_meta_divergence(),
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
    options=[
      version_option(),
      regulation_option(),
      format_option(),
      @admiral.bool(
        "include-inactive",
        description="Include Champions confiscated moves (state=inactive)",
      ),
    ],
    positionals=[
      @admiral.positional(
        "target",
        description="Pokemon name or globalNo",
        required=true,
      ),
    ],
    run=Some(fn(ctx) {
      run_moves(
        ctx_str(ctx, "target"),
        ctx_game(ctx),
        ctx_format(ctx),
        ctx.get_bool("include-inactive"),
      )
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
      @admiral.bool("double", description="Double battle (applies 0.75x to spread moves)"),
      @admiral.int("atk-stat", description="Override attacker offensive stat (pre-rank). 用途: ボディプレス/イカサマ/カスタム実数値再現", default=Some(0)),
      @admiral.int("def-stat", description="Override defender defensive stat (pre-rank). 用途: カスタム実数値再現", default=Some(0)),
      @admiral.int("def-hp", description="Override defender HP", default=Some(0)),
      @admiral.string("atk-nature", description="Attacker nature (ja), e.g. ようき. Default: 攻撃stat特化相当 (+10%)", default=Some("")),
      @admiral.string("def-nature", description="Defender nature (ja), e.g. ずぶとい. Default: 無補正", default=Some("")),
      @admiral.int("atk-rank", description="Attacker stat stage (-6..+6). For Body Press this is the Defense stage", default=Some(0)),
      @admiral.int("def-rank", description="Defender stat stage (-6..+6)", default=Some(0)),
      @admiral.int("fainted-count", description="Number of fainted allies (0-5, for Supreme Overlord/そうだいしょう)", default=Some(2)),
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
        ctx.get_bool("double"),
        ctx_int(ctx, "atk-stat"),
        ctx_int(ctx, "def-stat"),
        ctx_int(ctx, "def-hp"),
        ctx_str(ctx, "atk-nature"),
        ctx_str(ctx, "def-nature"),
        ctx_int(ctx, "atk-rank"),
        ctx_int(ctx, "def-rank"),
        ctx_int(ctx, "fainted-count"),
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
fn cmd_import_check() -> @admiral.CommandDef {
  @admiral.command(
    name="import-check",
    description="Check if a cache JSON would duplicate an existing record. Reads {kind, cache, existing[]} JSON from stdin; prints {status, matched_file, differing_fields?} JSON.",
    run=Some(fn(_ctx) { run_import_check_cli() }),
  )
}

///|
fn cmd_stat_calc() -> @admiral.CommandDef {
  @admiral.command(
    name="stat-calc",
    description="Compute Lv50 stats from base + SP + nature (EV/IV for deprecated versions)",
    options=[
      @admiral.string("ev", description="SPs as 'H,A,B,C,D,S' (EVs for deprecated versions)", default=Some("")),
      @admiral.string("iv", description="IVs (deprecated versions only, ignored in Champions)", default=Some("")),
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
    description="Reverse-derive base stat (single mode) or SP/EV spread (pokemon mode)",
    options=[
      @admiral.string("stats", description="Actual stats 'H,A,B,C,D,S' (pokemon mode)", default=Some("")),
      @admiral.int("iv", description="IV (deprecated versions only, ignored in Champions)", default=Some(31)),
      @admiral.int("ev", description="SP or EV (deprecated versions)", default=Some(0)),
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
    description="Optimize H/B/D SP spread under HBD/(p*B+s*D) objective (EV for deprecated versions)",
    options=[
      @admiral.string("fixed-ev", description="Fixed SPs 'H,A,B,C,D,S' (_ to optimize) (EVs for deprecated versions)", default=Some("")),
      @admiral.string("iv", description="IVs (deprecated versions only, ignored in Champions)", default=Some("")),
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
  include_inactive : Bool,
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
    let r = @db.query_moves(db, global_no, game.version, include_inactive~)
    match r {
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
fn cmd_learners() -> @admiral.CommandDef {
  @admiral.command(
    name="learners",
    description="List Pokemon that can learn a given move",
    options=[
      version_option(),
      regulation_option(),
      format_option(),
      @admiral.int("limit", description="Max results (default 50)", default=Some(50)),
      @admiral.bool(
        "include-inactive",
        description="Include Champions confiscated moves (state=inactive)",
      ),
    ],
    positionals=[
      @admiral.positional(
        "move",
        description="Move name (ja)",
        required=true,
      ),
    ],
    run=Some(fn(ctx) {
      run_learners(
        ctx_str(ctx, "move"),
        ctx_int(ctx, "limit"),
        ctx_game(ctx),
        ctx_format(ctx),
        ctx.get_bool("include-inactive"),
      )
    }),
  )
}

///|
fn run_learners(
  move_name : String,
  limit : Int,
  game : GameContext,
  format : @cli.OutputFormat,
  include_inactive : Bool,
) -> Unit {
  with_db(fn(db) {
    let r = @db.query_learners(db, move_name, game.version, include_inactive~)
    match r {
      Ok(results) => {
        let filtered = if game.regulation != "" {
          results.filter(fn(p) { @db.is_available(p.global_no, game.regulation) })
        } else {
          results
        }
        let limited = if limit > 0 && filtered.length() > limit {
          filtered[:limit].to_array()
        } else {
          filtered
        }
        println(@cli.format_search(limited, format))
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
  is_double : Bool,
  atk_stat : Int,
  def_stat : Int,
  def_hp : Int,
  atk_nature_str : String,
  def_nature_str : String,
  atk_rank : Int,
  def_rank : Int,
  fainted_count : Int,
) -> Unit {
  if atk_rank < -6 || atk_rank > 6 {
    println("Error: --atk-rank must be in [-6, 6]")
    return
  }
  if def_rank < -6 || def_rank > 6 {
    println("Error: --def-rank must be in [-6, 6]")
    return
  }
  let atk_nature : @model.Nature? = if atk_nature_str.length() == 0 {
    None
  } else {
    match @model.nature_from_ja(atk_nature_str) {
      Some(n) => Some(n)
      None => {
        println("Error: Unknown nature: " + atk_nature_str)
        return
      }
    }
  }
  let def_nature : @model.Nature? = if def_nature_str.length() == 0 {
    None
  } else {
    match @model.nature_from_ja(def_nature_str) {
      Some(n) => Some(n)
      None => {
        println("Error: Unknown nature: " + def_nature_str)
        return
      }
    }
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
      atk_nature,
      def_nature,
      atk_stat_override: atk_stat,
      def_stat_override: def_stat,
      def_hp_override: def_hp,
      atk_rank,
      def_rank,
      fainted_count,
      is_double,
      stat_system: if game.version == "champions" {
        @model.Champions
      } else {
        @model.Standard
      },
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
  let base = "box/teams/" + axis + "-build-" + date
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
  let is_champ = game.version == "champions"
  let nature = resolve_nature(nature_name, nature_up, nature_down)
  if is_champ {
    let sps = @cli.parse_csv_ints(evs_str, 0, 6)
    // Validate SP constraints
    let mut total = 0
    for i = 0; i < 6; i = i + 1 {
      if sps[i] < 0 || sps[i] > 32 {
        println("Error: SP values must be 0-32, got " + sps[i].to_string())
        return
      }
      total = total + sps[i]
    }
    if total > 66 {
      println("Error: Total SP must be ≤ 66, got " + total.to_string())
      return
    }
    with_db(fn(db) {
      match @db.query_pokemon(db, name, game.version) {
        Ok(pokemon) => {
          let stats = @damage.calc_all_stats_champions(pokemon, sps, nature)
          println(
            @cli.format_stat_calc(
              pokemon, stats, nature, sps, sps, format, is_champions=true,
            ),
          )
        }
        Err(e) => println("Error: " + e)
      }
    })
  } else {
    let evs = @cli.parse_csv_ints(evs_str, 0, 6)
    let ivs = @cli.parse_csv_ints(ivs_str, 31, 6)
    with_db(fn(db) {
      match @db.query_pokemon(db, name, game.version) {
        Ok(pokemon) => {
          let stats = @damage.calc_all_stats(pokemon, ivs, evs, nature)
          println(
            @cli.format_stat_calc(pokemon, stats, nature, ivs, evs, format),
          )
        }
        Err(e) => println("Error: " + e)
      }
    })
  }
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
  let is_champ = game.version == "champions"
  if stats_str.length() > 0 {
    // Pokemon mode
    let actual_stats = @cli.parse_csv_ints(stats_str, 0, 6)
    with_db(fn(db) {
      match @db.query_pokemon(db, target, game.version) {
        Ok(pokemon) => {
          if is_champ {
            let results = @damage.reverse_spread_champions(
              pokemon, actual_stats,
            )
            println(
              @cli.format_stat_reverse_pokemon(
                pokemon, actual_stats, results, format, is_champions=true,
              ),
            )
          } else {
            let results = @damage.reverse_spread(pokemon, actual_stats, iv)
            println(
              @cli.format_stat_reverse_pokemon(
                pokemon, actual_stats, results, format,
              ),
            )
          }
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
    if is_champ {
      if ev < 0 || ev > 32 {
        println(
          "Error: SP values must be 0-32, got " + ev.to_string(),
        )
        return
      }
      let base = @damage.reverse_base_from_stat_champions(
        actual, ev, is_hp, nature_num, nature_den,
      )
      println(
        @cli.format_stat_reverse_single(
          actual, base, 0, ev, is_hp, nature_mod, format, is_champions=true,
        ),
      )
    } else {
      let base = @damage.reverse_base_from_stat(
        actual, iv, ev, is_hp, nature_num, nature_den,
      )
      println(
        @cli.format_stat_reverse_single(
          actual, base, iv, ev, is_hp, nature_mod, format,
        ),
      )
    }
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
  let is_champ = game.version == "champions"
  let nature = resolve_nature(nature_name, nature_up, nature_down)
  let weights : @damage.HbdWeights = { phys: phys_weight, spec: spec_weight }
  if is_champ {
    // Champions: validate per-stat cap and total SP budget
    let mut fixed_total = 0
    for i = 0; i < 6; i = i + 1 {
      if fixed_ev[i] >= 0 {
        if fixed_ev[i] > 32 {
          println(
            "Error: SP values must be 0-32, got " + fixed_ev[i].to_string(),
          )
          return
        }
        fixed_total = fixed_total + fixed_ev[i]
      }
    }
    if fixed_total > 66 {
      println(
        "Error: total fixed SP (" +
        fixed_total.to_string() +
        ") exceeds Champions budget of 66",
      )
      return
    }
    with_db(fn(db) {
      match @db.query_pokemon(db, name, game.version) {
        Ok(pokemon) => {
          let result = if top <= 1 {
            @damage.optimize_hbd_champions(
              pokemon, fixed_ev, nature, snap, weights,
            )
          } else {
            @damage.optimize_hbd_topn_champions(
              pokemon, fixed_ev, nature, snap, weights, top,
            )
          }
          println(
            @cli.format_hbd(
              pokemon, nature, snap, weights, result, format, is_champions=true,
            ),
          )
        }
        Err(e) => println("Error: " + e)
      }
    })
  } else {
    let ivs = @cli.parse_csv_ints(ivs_str, 31, 6)
    with_db(fn(db) {
      match @db.query_pokemon(db, name, game.version) {
        Ok(pokemon) => {
          let result = if top <= 1 {
            @damage.optimize_hbd(
              pokemon, fixed_ev, ivs, nature, snap, weights,
            )
          } else {
            @damage.optimize_hbd_topn(
              pokemon, fixed_ev, ivs, nature, snap, weights, top,
            )
          }
          println(
            @cli.format_hbd(pokemon, nature, snap, weights, result, format),
          )
        }
        Err(e) => println("Error: " + e)
      }
    })
  }
}

///|
/// `pkdx nash` — Nash equilibrium solver. Reads a JSON payoff specification
/// from stdin and solves the zero-sum game. Accepts either an explicit
/// matrix or a monocycle character list; rejects inputs that provide both.
fn cmd_nash() -> @admiral.CommandDef {
  @admiral.command(
    name="nash",
    description="Solve a zero-sum Nash equilibrium or emit a DOT payoff graph",
    subcommands=[
      @admiral.command(
        name="solve",
        description="Solve the Nash equilibrium from a payoff JSON on stdin",
        run=Some(fn(_ctx) { run_nash_solve_cmd() }),
      ),
      @admiral.command(
        name="graph",
        description="Emit a Graphviz DOT representation of the payoff matrix",
        options=[
          @admiral.string(
            "threshold",
            description="Edge absolute-value threshold (default 0)",
            default=Some("0"),
          ),
        ],
        run=Some(fn(ctx) { run_nash_graph_cmd(ctx_str(ctx, "threshold")) }),
      ),
    ],
  )
}

///|
fn read_stdin_json() -> String {
  let raw = pkdx_read_stdin()
  if raw.length() == 0 {
    exit_error("No input from stdin")
  }
  raw
}

///|
fn run_nash_solve_cmd() -> Unit {
  let raw = read_stdin_json()
  let out = try @payoff.run_nash_solve(raw) catch {
    err => {
      exit_error(nash_cli_error_message(err))
      return
    }
  }
  println(out)
}

///|
fn parse_double(s : String, default : Double) -> Double {
  // Accept simple decimals like "0.5", "-1.25", "0" — delegate to strconv if
  // available; otherwise fall back to integer parsing via existing helper.
  let mut result = 0.0
  let mut i = 0
  let mut negative = false
  if i < s.length() && s[i] == '-' {
    negative = true
    i = i + 1
  }
  let mut has_digit = false
  let mut in_frac = false
  let mut frac_scale = 1.0
  while i < s.length() {
    let c = s[i].to_int()
    if c >= 0x30 && c <= 0x39 {
      let d = (c - 0x30).to_double()
      if in_frac {
        frac_scale = frac_scale * 0.1
        result = result + d * frac_scale
      } else {
        result = result * 10.0 + d
      }
      has_digit = true
    } else if c == 0x2E && not(in_frac) {
      in_frac = true
    } else {
      break
    }
    i = i + 1
  }
  if not(has_digit) {
    return default
  }
  if negative {
    -result
  } else {
    result
  }
}

///|
fn run_nash_graph_cmd(threshold_str : String) -> Unit {
  let raw = read_stdin_json()
  let threshold = parse_double(threshold_str, 0.0)
  let out = try @payoff.run_nash_graph(raw, threshold) catch {
    err => {
      exit_error(nash_cli_error_message(err))
      return
    }
  }
  println(out)
}

///|
/// Map a `NashCliError` to a human-readable message. Kept inline so we don't
/// need to add a Show impl that leaks internal field layout.
fn nash_cli_error_message(err : @payoff.NashCliError) -> String {
  match err {
    InvalidJson(msg) => "invalid JSON: " + msg
    MissingField(field) => "missing field: " + field
    ConflictingInputs => "both matrix and characters provided; pick one"
    NonSquareMatrix(r, c) =>
      "matrix is not square: " + r.to_string() + "x" + c.to_string()
    LabelCountMismatch(expected, got) =>
      "labels length mismatch: expected " +
      expected.to_string() +
      ", got " +
      got.to_string()
    InfeasibleGame => "game is infeasible"
    UnboundedGame => "game is unbounded"
    InnerError(msg) => "solver error: " + msg
  }
}

///|
/// `pkdx select` — selection-optimisation command. Reads a team/opponent JSON
/// bundle from stdin and outputs the mixed-strategy distribution over
/// k-selections.
fn cmd_select() -> @admiral.CommandDef {
  @admiral.command(
    name="select",
    description="Compute Nash-optimal selection distribution from team JSON on stdin",
    run=Some(fn(_ctx) { run_select_cmd() }),
  )
}

///|
fn run_select_cmd() -> Unit {
  let raw = read_stdin_json()
  let out = try @payoff.run_select(raw) catch {
    err => {
      exit_error(nash_cli_error_message(err))
      return
    }
  }
  println(out)
}

///|
/// `pkdx meta-divergence` — measure how far a usage distribution is from a
/// self-best-response equilibrium given a symmetric payoff matrix.
fn cmd_meta_divergence() -> @admiral.CommandDef {
  @admiral.command(
    name="meta-divergence",
    description="Report exploitability and per-index regret of a usage distribution",
    run=Some(fn(_ctx) { run_meta_divergence_cmd() }),
  )
}

///|
fn meta_cli_error_message(err : @payoff.MetaCliError) -> String {
  match err {
    InvalidJsonMeta(msg) => "invalid JSON: " + msg
    MissingFieldMeta(field) => "missing field: " + field
    UsageNotNormalised(total) =>
      "usage does not sum to 1 (got " + total.to_string() + ")"
    ShapeMismatch(n, m) =>
      "matrix / usage shape mismatch: " +
      n.to_string() +
      " vs " +
      m.to_string()
  }
}

///|
fn run_meta_divergence_cmd() -> Unit {
  let raw = read_stdin_json()
  let out = try @payoff.run_meta_divergence(raw) catch {
    err => {
      exit_error(meta_cli_error_message(err))
      return
    }
  }
  println(out)
}
