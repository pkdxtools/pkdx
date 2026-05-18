fn resolve_damage_cache_path() -> String {
  match @sys.get_env_var(DAMAGE_CACHE_ENV_VAR) {
    Some(p) if p.length() > 0 => return p
    _ => ()
  }
  let anchors : Array[(String, String)] = [
    ("pokedex/pokedex.db", "."),
    ("../pokedex/pokedex.db", ".."),
  ]
  for i = 0; i < anchors.length(); i = i + 1 {
    let (marker, root) = anchors[i]
    if @db.file_exists(marker) {
      return root + "/" + DAMAGE_CACHE_REL_PATH
    }
  }
  DAMAGE_CACHE_REL_PATH
}

///|
///|
/// Rev2 CLI extensions bundled together so `run_damage`'s signature doesn't
/// bloat. Each field is populated from the corresponding CLI flag in
/// `cmd_damage`, with `*_str` variants kept alongside the parsed value for
/// stable cache-key encoding.
struct DamageRev2Opts {
  wall : @model.Wall
  wall_str : String
  screen_pierce : Bool
  atk_status : @model.StatusCondition
  atk_status_str : String
  def_status : @model.StatusCondition
  def_status_str : String
  atk_rank_up_count : Int
  def_rank_up_count : Int
  atk_hp_num : Int
  atk_hp_den : Int
  def_item_removable : Bool
  multi_hit : @model.MultiHit
  multi_hit_str : String
  disguise_active : Bool
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
  weather_str : String,
  field_str : String,
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
  no_cache : Bool,
  attach_team : String,
  attach_title : String,
  attach_note : String,
  rev2 : DamageRev2Opts,
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
  // Cache path: only active for JSON output because the cached value is
  // JSON-shaped and table rendering depends on the original DamageCalcInput.
  // `--attach-team` もバイパス — attach 処理は DamageCalcInput / Result が
  // 必要で、cached JSON からは復元できないため、毎回 fresh に計算する。
  let use_cache = match format {
    @cli.Json => !(no_cache) && attach_team.length() == 0
    _ => false
  }
  let cache_key_opt : String? = if use_cache {
    let key_input = @damage_cache.CacheKeyInput::{
      version: game.version.to_db_string(),
      regulation: game.regulation,
      attacker: attacker_name,
      defender: defender_name,
      move_name,
      atk_ability,
      def_ability,
      atk_item,
      def_item,
      weather: weather_str,
      field: field_str,
      tera_type,
      critical,
      is_double,
      atk_stat,
      def_stat,
      def_hp,
      atk_nature: atk_nature_str,
      def_nature: def_nature_str,
      atk_rank,
      def_rank,
      fainted_count,
      // rev2: populated from parsed CLI flags.
      wall: rev2.wall_str,
      screen_pierce: rev2.screen_pierce,
      atk_status: rev2.atk_status_str,
      def_status: rev2.def_status_str,
      atk_rank_up_count: rev2.atk_rank_up_count,
      def_rank_up_count: rev2.def_rank_up_count,
      atk_hp_num: rev2.atk_hp_num,
      atk_hp_den: rev2.atk_hp_den,
      def_item_removable: rev2.def_item_removable,
      multi_hit_mode: rev2.multi_hit_str,
      disguise_active: rev2.disguise_active,
    }
    match @damage_cache.build_cache_key(key_input) {
      Ok(k) => Some(k)
      Err(e) => {
        pkdx_eprintln(
          @db.to_c_bytes("damage_cache: key build failed, skipping cache: " + e),
        )
        None
      }
    }
  } else {
    None
  }
  let cache_opt : @damage_cache.DamageDiskCache? = match cache_key_opt {
    Some(_) =>
      match
        @damage_cache.open_or_init(resolve_damage_cache_path(), pkdx_version) {
        Ok(c) => Some(c)
        Err(e) => {
          pkdx_eprintln(
            @db.to_c_bytes("damage_cache: open failed, skipping cache: " + e),
          )
          None
        }
      }
    None => None
  }
  match (cache_opt, cache_key_opt) {
    (Some(cache), Some(key)) =>
      match @damage_cache.get(cache, key) {
        Some(value_json) => {
          @damage_cache.close(cache)
          println(value_json)
          return
        }
        None => ()
      }
    _ => ()
  }
  with_db(version=game.version, fn(db) {
    let atk_pokemon = match @db.query_pokemon(db, attacker_name, game.version) {
      Ok(p) => p
      Err(e) => {
        match cache_opt {
          Some(c) => @damage_cache.close(c)
          None => ()
        }
        println("Error: " + e)
        return
      }
    }
    let def_pokemon = match @db.query_pokemon(db, defender_name, game.version) {
      Ok(p) => p
      Err(e) => {
        match cache_opt {
          Some(c) => @damage_cache.close(c)
          None => ()
        }
        println("Error: " + e)
        return
      }
    }
    let move_ = match @db.query_move(db, move_name, game.version) {
      Ok(m) => m
      Err(e) => {
        match cache_opt {
          Some(c) => @damage_cache.close(c)
          None => ()
        }
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
      stat_system: game.version.to_stat_system(),
      // rev2: driven by CLI flags, defaults fall back to legacy behavior.
      wall: rev2.wall,
      screen_pierce: rev2.screen_pierce,
      atk_status_condition: rev2.atk_status,
      def_status_condition: rev2.def_status,
      atk_rank_up_count: rev2.atk_rank_up_count,
      def_rank_up_count: rev2.def_rank_up_count,
      atk_hp_num: rev2.atk_hp_num,
      atk_hp_den: rev2.atk_hp_den,
      def_item_removable: rev2.def_item_removable,
      multi_hit_mode: rev2.multi_hit,
      disguise_active: rev2.disguise_active,
    }
    let result = @damage.calc_damage(input)
    let output = @cli.format_damage(result, input, format)
    match (cache_opt, cache_key_opt) {
      (Some(cache), Some(key)) => {
        match @damage_cache.put(cache, key, output) {
          Ok(_) => ()
          Err(e) =>
            pkdx_eprintln(
              @db.to_c_bytes("damage_cache: put failed: " + e),
            )
        }
        @damage_cache.close(cache)
      }
      _ => ()
    }
    println(output)
    if attach_team.length() > 0 {
      attach_damage_calc_to_meta(
        attach_team,
        input,
        result,
        attach_title,
        attach_note,
      )
    }
  })
}

///|
/// `pkdx damage --attach-team <meta_path>` サポート。計算 JSON を
/// site/src/lib/team-meta.ts `DamageCalc` schema に整形して追記する。
/// 書き出しは file-level 冪等 — 同じ計算を複数回 attach すると単純に重複追加される
/// (skill 側で重複排除方針を決めるため、ここでは単純 append に留める)。
fn attach_damage_calc_to_meta(
  meta_path : String,
  input : @model.DamageCalcInput,
  result : @model.DamageCalcResult,
  title : String,
  note : String,
) -> Unit {
  match @writer.validate_attach_team_path(meta_path) {
    Ok(_) => ()
    Err(reason) => {
      exit_error("--attach-team: invalid path '" + meta_path + "' (" + reason + ")")
      return
    }
  }
  let existing = match @db.read_file(meta_path) {
    Some(s) => s
    None => {
      exit_error("--attach-team: meta.json not found at " + meta_path)
      return
    }
  }
  let meta_json = @json.parse(existing) catch {
    e => {
      exit_error("--attach-team: JSON parse error in " + meta_path + ": " + e.to_string())
      return
    }
  }
  let entry = @writer.build_damage_calc_entry(input, result, title, note)
  let updated = @writer.append_damage_calc(meta_json, entry)
  let rc = pkdx_write_file(
    @db.to_c_bytes(meta_path),
    @db.to_c_bytes(updated.stringify()),
  )
  if rc != 0 {
    exit_error("--attach-team: failed to write " + meta_path)
  } else {
    pkdx_eprintln(@db.to_c_bytes("Attached damage calc to " + meta_path))
  }
}

