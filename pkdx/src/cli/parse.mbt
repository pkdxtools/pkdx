///|
pub enum OutputFormat {
  Json
  Table
} derive(Show)

///|
pub enum Command {
  Query(name~ : String, version~ : String, format~ : OutputFormat)
  Moves(target~ : String, version~ : String, format~ : OutputFormat)
  Search(
    type1~ : String,
    type2~ : String,
    min_speed~ : Int,
    version~ : String,
    format~ : OutputFormat
  )
  TypeChart(move_type~ : String, def_type1~ : String, def_type2~ : String)
  Coverage(types~ : Array[String])
  Damage(
    attacker~ : String,
    defender~ : String,
    move_name~ : String,
    version~ : String,
    format~ : OutputFormat,
    atk_ability~ : String,
    def_ability~ : String,
    atk_item~ : String,
    def_item~ : String,
    weather~ : String,
    field~ : String,
    tera_type~ : String,
    critical~ : Bool,
    atk_stat~ : Int,
    def_stat~ : Int,
    def_hp~ : Int
  )
  WriteTeams(date~ : String, axis~ : String)
  WritePokemon(name~ : String, file~ : String)
  StatCalc(
    name~ : String,
    evs~ : String,
    ivs~ : String,
    nature~ : String,
    nature_up~ : String,
    nature_down~ : String,
    version~ : String,
    format~ : OutputFormat
  )
  StatReverse(
    target~ : String,
    stats~ : String,
    iv~ : Int,
    ev~ : Int,
    nature_mod~ : String,
    is_hp~ : Bool,
    version~ : String,
    format~ : OutputFormat
  )
  InitCache(kind~ : CacheKind)
  Hbd(
    name~ : String,
    fixed_ev~ : String,
    ivs~ : String,
    nature~ : String,
    nature_up~ : String,
    nature_down~ : String,
    hp_snap~ : String,
    phys_weight~ : Int,
    spec_weight~ : Int,
    top~ : Int,
    version~ : String,
    format~ : OutputFormat
  )
  Help
  Version
} derive(Show)

///|
pub enum CacheKind {
  Team
  Pokemon
} derive(Show)

///|
/// Parse CLI arguments into a Command.
pub fn parse_args(args : Array[String]) -> Result[Command, String] {
  if args.length() < 2 {
    return Ok(Help)
  }
  let subcmd = args[1]
  match subcmd {
    "query" => parse_query(args)
    "moves" => parse_moves(args)
    "search" => parse_search(args)
    "type-chart" => parse_type_chart(args)
    "coverage" => parse_coverage(args)
    "damage" => parse_damage(args)
    "write" => parse_write(args)
    "stat-calc" => parse_stat_calc(args)
    "stat-reverse" => parse_stat_reverse(args)
    "init-cache" => parse_init_cache(args)
    "hbd" => parse_hbd(args)
    "help" | "--help" | "-h" => Ok(Help)
    "version" | "--version" | "-v" => Ok(Version)
    _ => Err("Unknown command: " + subcmd + ". Run 'pkdx help' for usage.")
  }
}

///|
fn parse_format(args : Array[String]) -> OutputFormat {
  for i = 0; i < args.length() - 1; i = i + 1 {
    if args[i] == "--format" {
      match args[i + 1] {
        "json" => return Json
        "table" => return Table
        _ => ()
      }
    }
  }
  Table
}

///|
fn get_flag(args : Array[String], flag : String, default : String) -> String {
  for i = 0; i < args.length() - 1; i = i + 1 {
    if args[i] == flag {
      return args[i + 1]
    }
  }
  default
}

///|
fn has_flag(args : Array[String], flag : String) -> Bool {
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == flag {
      return true
    }
  }
  false
}

///|
fn get_flag_int(args : Array[String], flag : String, default : Int) -> Int {
  let s = get_flag(args, flag, "")
  if s.length() == 0 {
    return default
  }
  parse_int_str(s, default)
}

///|
fn parse_int_str(s : String, default : Int) -> Int {
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
  if !has_digit {
    return default
  }
  if negative {
    -result
  } else {
    result
  }
}

///|
fn parse_query(args : Array[String]) -> Result[Command, String] {
  if args.length() < 3 {
    return Err("Usage: pkdx query <name> [--version V] [--format json|table]")
  }
  Ok(
    Query(
      name=args[2],
      version=get_flag(args, "--version", "scarlet_violet"),
      format=parse_format(args),
    ),
  )
}

///|
fn parse_moves(args : Array[String]) -> Result[Command, String] {
  if args.length() < 3 {
    return Err(
      "Usage: pkdx moves <name|globalNo> [--version V] [--format json|table]",
    )
  }
  Ok(
    Moves(
      target=args[2],
      version=get_flag(args, "--version", "scarlet_violet"),
      format=parse_format(args),
    ),
  )
}

///|
fn parse_search(args : Array[String]) -> Result[Command, String] {
  let type1 = get_flag(args, "--type", "")
  if type1.length() == 0 {
    return Err(
      "Usage: pkdx search --type <type1> [--type2 <type2>] [--min-speed N] [--version V]",
    )
  }
  Ok(
    Search(
      type1~,
      type2=get_flag(args, "--type2", ""),
      min_speed=get_flag_int(args, "--min-speed", 0),
      version=get_flag(args, "--version", "scarlet_violet"),
      format=parse_format(args),
    ),
  )
}

///|
fn parse_type_chart(args : Array[String]) -> Result[Command, String] {
  if args.length() < 4 {
    return Err("Usage: pkdx type-chart <move_type> <def_type1> [def_type2]")
  }
  let def_type2 = if args.length() >= 5 { args[4] } else { "" }
  Ok(TypeChart(move_type=args[2], def_type1=args[3], def_type2~))
}

///|
fn parse_coverage(args : Array[String]) -> Result[Command, String] {
  if args.length() < 3 {
    return Err("Usage: pkdx coverage <type1,type2,...>")
  }
  let types = split_string(args[2], ',')
  Ok(Coverage(types~))
}

///|
fn parse_damage(args : Array[String]) -> Result[Command, String] {
  if args.length() < 5 {
    return Err(
      "Usage: pkdx damage <attacker> <defender> <move> [--atk-ability ...] [--def-ability ...] ...",
    )
  }
  Ok(
    Damage(
      attacker=args[2],
      defender=args[3],
      move_name=args[4],
      version=get_flag(args, "--version", "scarlet_violet"),
      format=parse_format(args),
      atk_ability=get_flag(args, "--atk-ability", ""),
      def_ability=get_flag(args, "--def-ability", ""),
      atk_item=get_flag(args, "--atk-item", ""),
      def_item=get_flag(args, "--def-item", ""),
      weather=get_flag(args, "--weather", ""),
      field=get_flag(args, "--field", ""),
      tera_type=get_flag(args, "--tera-type", ""),
      critical=has_flag(args, "--critical"),
      atk_stat=get_flag_int(args, "--atk-stat", 0),
      def_stat=get_flag_int(args, "--def-stat", 0),
      def_hp=get_flag_int(args, "--def-hp", 0),
    ),
  )
}

///|
fn parse_write(args : Array[String]) -> Result[Command, String] {
  if has_flag(args, "--teams") {
    let date = get_flag(args, "--date", "")
    let axis = get_flag(args, "--axis", "")
    if date.length() == 0 || axis.length() == 0 {
      return Err("Usage: pkdx write --teams --date YYYY-MM-DD --axis <name>")
    }
    Ok(WriteTeams(date~, axis~))
  } else if has_flag(args, "--pokemon") {
    let name = get_flag(args, "--name", "")
    let file = get_flag(args, "--file", "")
    if name.length() == 0 || file.length() == 0 {
      return Err("Usage: pkdx write --pokemon --name <name> --file <filename>")
    }
    Ok(WritePokemon(name~, file~))
  } else {
    Err("Usage: pkdx write --teams|--pokemon [options]")
  }
}

///|
fn parse_stat_calc(args : Array[String]) -> Result[Command, String] {
  if args.length() < 3 {
    return Err(
      "Usage: pkdx stat-calc <name> [--ev \"H,A,B,C,D,S\"] [--iv N] [--nature name] [--nature-up stat --nature-down stat]",
    )
  }
  Ok(
    StatCalc(
      name=args[2],
      evs=get_flag(args, "--ev", ""),
      ivs=get_flag(args, "--iv", ""),
      nature=get_flag(args, "--nature", ""),
      nature_up=get_flag(args, "--nature-up", ""),
      nature_down=get_flag(args, "--nature-down", ""),
      version=get_flag(args, "--version", "scarlet_violet"),
      format=parse_format(args),
    ),
  )
}

///|
fn parse_stat_reverse(args : Array[String]) -> Result[Command, String] {
  if args.length() < 3 {
    return Err(
      "Usage: pkdx stat-reverse <value|name> [--stats \"H,A,B,C,D,S\"] [--iv N] [--ev N] [--nature up|down|neutral] [--hp]",
    )
  }
  Ok(
    StatReverse(
      target=args[2],
      stats=get_flag(args, "--stats", ""),
      iv=get_flag_int(args, "--iv", 31),
      ev=get_flag_int(args, "--ev", 0),
      nature_mod=get_flag(args, "--nature", "neutral"),
      is_hp=has_flag(args, "--hp"),
      version=get_flag(args, "--version", "scarlet_violet"),
      format=parse_format(args),
    ),
  )
}

///|
fn split_string(s : String, sep : Char) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let sep_int = sep.to_int()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == sep_int {
      if i > start {
        parts.push(s[start:i].to_string())
      }
      start = i + 1
    }
  }
  if start < s.length() {
    parts.push(s[start:].to_string())
  }
  parts
}

///|
/// Parse `--fixed-ev` value into six slots. `_` marks a slot as an optimization target
/// and is represented by -1 in the output array. Non-integer tokens return Err.
pub fn parse_fixed_ev(s : String) -> Result[FixedArray[Int], String] {
  let parts = split_string(s, ',')
  if parts.length() != 6 {
    return Err(
      "--fixed-ev must have 6 comma-separated values (H,A,B,C,D,S); got " +
      parts.length().to_string(),
    )
  }
  let out : FixedArray[Int] = FixedArray::make(6, 0)
  for i = 0; i < 6; i = i + 1 {
    let tok = parts[i]
    if tok == "_" {
      out[i] = -1
    } else {
      // parse_int_str returns default on parse failure — guard by scanning digits explicitly
      let mut all_digits = tok.length() > 0
      for j = 0; j < tok.length(); j = j + 1 {
        let c = tok[j].to_int()
        if c < 0x30 || c > 0x39 {
          all_digits = false
        }
      }
      if not(all_digits) {
        return Err("invalid --fixed-ev token: " + tok)
      }
      out[i] = parse_int_str(tok, 0)
    }
  }
  Ok(out)
}

///|
fn parse_hbd(args : Array[String]) -> Result[Command, String] {
  if args.length() < 3 {
    return Err(
      "Usage: pkdx hbd <name> [--fixed-ev \"H,A,B,C,D,S\"] [--nature name] [--hp-snap snap] [--phys-weight N] [--spec-weight N] [--top N]",
    )
  }
  Ok(
    Hbd(
      name=args[2],
      fixed_ev=get_flag(args, "--fixed-ev", ""),
      ivs=get_flag(args, "--iv", ""),
      nature=get_flag(args, "--nature", ""),
      nature_up=get_flag(args, "--nature-up", ""),
      nature_down=get_flag(args, "--nature-down", ""),
      hp_snap=get_flag(args, "--hp-snap", "none"),
      phys_weight=get_flag_int(args, "--phys-weight", 1),
      spec_weight=get_flag_int(args, "--spec-weight", 1),
      top=get_flag_int(args, "--top", 1),
      version=get_flag(args, "--version", "scarlet_violet"),
      format=parse_format(args),
    ),
  )
}

///|
fn parse_init_cache(args : Array[String]) -> Result[Command, String] {
  let has_team = has_flag(args, "--team")
  let has_pokemon = has_flag(args, "--pokemon")
  if has_team && has_pokemon {
    return Err("Usage: pkdx init-cache --team|--pokemon (choose one)")
  }
  if has_team {
    Ok(InitCache(kind=Team))
  } else if has_pokemon {
    Ok(InitCache(kind=Pokemon))
  } else {
    Err("Usage: pkdx init-cache --team|--pokemon")
  }
}
