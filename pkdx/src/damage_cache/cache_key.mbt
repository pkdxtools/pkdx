///|
/// Encoded input to `build_cache_key`. Mirrors the CLI flags of
/// `pkdx damage`. Each `String` field is the raw CLI input (no normalization).
pub(all) struct CacheKeyInput {
  version : String
  regulation : String
  attacker : String
  defender : String
  move_name : String
  atk_ability : String
  def_ability : String
  atk_item : String
  def_item : String
  weather : String
  field : String
  tera_type : String
  critical : Bool
  is_double : Bool
  atk_stat : Int
  def_stat : Int
  def_hp : Int
  atk_nature : String
  def_nature : String
  atk_rank : Int
  def_rank : Int
  fainted_count : Int
  // rev2 additions. Empty string / 0 / false = legacy default, so legacy
  // baselines produce the same key suffix (v1 key layout extends at the end,
  // so pre-rev2 entries recomputed with default-filled inputs still hash to
  // a deterministic key).
  wall : String
  screen_pierce : Bool
  atk_status : String
  def_status : String
  atk_rank_up_count : Int
  def_rank_up_count : Int
  atk_hp_num : Int
  atk_hp_den : Int
  def_item_removable : Bool
  multi_hit_mode : String
  disguise_active : Bool
}

///|
/// UTF-16 code unit for the pipe separator.
const PIPE_CODE : UInt16 = 0x7C

///|
/// UTF-16 code unit for ASCII space. Fullwidth space (U+3000) is *not*
/// rejected because Pokemon names can legitimately include 中黒 etc.; ASCII
/// space is the only case where a stray leading/trailing byte indicates
/// accidental input instead of intentional content.
const SPACE_CODE : UInt16 = 0x20

///|
/// Validate a single field: no `|` and no leading/trailing ASCII space.
fn validate_field(name : String, value : String) -> Result[Unit, String] {
  let len = value.length()
  if len == 0 {
    return Ok(())
  }
  if value.unsafe_get(0) == SPACE_CODE {
    return Err(
      "field '" + name + "' has leading whitespace: '" + value + "'",
    )
  }
  if value.unsafe_get(len - 1) == SPACE_CODE {
    return Err(
      "field '" + name + "' has trailing whitespace: '" + value + "'",
    )
  }
  for i = 0; i < len; i = i + 1 {
    if value.unsafe_get(i) == PIPE_CODE {
      return Err(
        "field '" + name + "' contains reserved '|' character: '" + value + "'",
      )
    }
  }
  Ok(())
}

///|
/// Build a deterministic pipe-delimited v1 cache key.
///
/// Layout:
/// `v1|<version>|<regulation>|<attacker>|<defender>|<move>|<atk_ability>|`
/// `<def_ability>|<atk_item>|<def_item>|<weather>|<field>|<tera_type>|`
/// `<critical>|<double>|<atk_stat>|<def_stat>|<def_hp>|<atk_nature>|`
/// `<def_nature>|<atk_rank>|<def_rank>|<fainted_count>`
///
/// Returns `Err` if any string field contains `|` or leading/trailing
/// ASCII whitespace — those cases would either break the encoding or
/// produce cache-hit divergence between visually identical inputs.
pub fn build_cache_key(input : CacheKeyInput) -> Result[String, String] {
  let string_fields : Array[(String, String)] = [
    ("version", input.version),
    ("regulation", input.regulation),
    ("attacker", input.attacker),
    ("defender", input.defender),
    ("move", input.move_name),
    ("atk_ability", input.atk_ability),
    ("def_ability", input.def_ability),
    ("atk_item", input.atk_item),
    ("def_item", input.def_item),
    ("weather", input.weather),
    ("field", input.field),
    ("tera_type", input.tera_type),
    ("atk_nature", input.atk_nature),
    ("def_nature", input.def_nature),
    ("wall", input.wall),
    ("atk_status", input.atk_status),
    ("def_status", input.def_status),
    ("multi_hit_mode", input.multi_hit_mode),
  ]
  for i = 0; i < string_fields.length(); i = i + 1 {
    let (name, value) = string_fields[i]
    match validate_field(name, value) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  let critical_s = if input.critical { "1" } else { "0" }
  let double_s = if input.is_double { "1" } else { "0" }
  let screen_pierce_s = if input.screen_pierce { "1" } else { "0" }
  let def_item_removable_s = if input.def_item_removable { "1" } else { "0" }
  let disguise_active_s = if input.disguise_active { "1" } else { "0" }
  let parts : Array[String] = [
    "v2",
    input.version,
    input.regulation,
    input.attacker,
    input.defender,
    input.move_name,
    input.atk_ability,
    input.def_ability,
    input.atk_item,
    input.def_item,
    input.weather,
    input.field,
    input.tera_type,
    critical_s,
    double_s,
    input.atk_stat.to_string(),
    input.def_stat.to_string(),
    input.def_hp.to_string(),
    input.atk_nature,
    input.def_nature,
    input.atk_rank.to_string(),
    input.def_rank.to_string(),
    input.fainted_count.to_string(),
    // rev2 tail. Ordering is part of the key contract: appended sections are
    // semantically grouped (wall → status → rank counts → hp ratio → knock-off
    // → multi-hit → disguise).
    input.wall,
    screen_pierce_s,
    input.atk_status,
    input.def_status,
    input.atk_rank_up_count.to_string(),
    input.def_rank_up_count.to_string(),
    input.atk_hp_num.to_string(),
    input.atk_hp_den.to_string(),
    def_item_removable_s,
    input.multi_hit_mode,
    disguise_active_s,
  ]
  Ok(parts.join("|"))
}
