///|
/// Item / item_effect query layer (issue #94 — P2-C).
///
/// `query_item_effects(db, name)` returns the typed `Array[ItemEffect]`
/// describing how an item modifies the damage pipeline. The pipeline is
/// expressed as `effect_kind` × `apply_order` so callers (engine /
/// items_db) compose effects in the right order without knowing which
/// item names live in which slot.

///|
pub(all) enum ItemEffectKind {
  StatMod
  FinalMod
  ResistBerry
  TypeBoost
  PowerMod
  // P5 (#97): consume-on-hit triggered by a KO-level damage on a defender
  // at full HP — sets defender HP to 1 and marks item consumed.
  // Canonical exemplar: きあいのタスキ.
  ConsumeOnHit
  // P5 (#97): post-damage HP threshold heal — when post HP <= max * num/den,
  // restore HP by 1/3 of max (still hard-coded; healing fraction is not yet
  // surfaced through num/den because all four フィラ-class berries share +1/3).
  HpThreshold
  Unknown(String)
} derive(Show, Eq)

///|
pub(all) struct ItemEffect {
  item_name : String
  kind : ItemEffectKind
  apply_order : Int
  num : Int
  den : Int
  type_filter : String
  pokemon_filter : String
  is_physical : Int? // 1 = physical only, 0 = special only, None = either
  super_effective_only : Bool
} derive(Show, Eq)

///|
fn parse_effect_kind(s : String) -> ItemEffectKind {
  match s {
    "stat_mod" => StatMod
    "final_mod" => FinalMod
    "resist_berry" => ResistBerry
    "type_boost" => TypeBoost
    "power_mod" => PowerMod
    "consume_on_hit" => ConsumeOnHit
    "hp_threshold" => HpThreshold
    _ => Unknown(s)
  }
}

///|
/// Look up item_effect rows for one item. Caller must pass a `db` that
/// can see the `item_effect` table — pokedex.db with champions.db
/// attached as `champions` (production path) or champions.db opened
/// directly (test fixture).
///
/// `db_alias` selects the schema prefix:
///   ""          → `item_effect` (champions.db opened directly)
///   "champions" → `champions.item_effect` (pokedex.db with champions
///                 attached, the production CLI path)
pub fn query_item_effects(
  db : Db,
  item_name : String,
  db_alias~ : String = "",
) -> Result[Array[ItemEffect], String] {
  let prefix = if db_alias.length() > 0 { db_alias + "." } else { "" }
  let sql = "SELECT effect_kind, apply_order, COALESCE(num, 0), " +
    "COALESCE(den, 0), COALESCE(type_filter, ''), " +
    "COALESCE(pokemon_filter, ''), is_physical, " +
    "COALESCE(super_effective_only, 0) " +
    "FROM " +
    prefix +
    "item_effect WHERE item_name = ? ORDER BY apply_order"
  let rows = match query_binds(db, sql, [BindText(item_name)]) {
    Ok(rs) => rs
    Err(e) => return Err(e)
  }
  let out : Array[ItemEffect] = []
  for i = 0; i < rows.length(); i = i + 1 {
    let r = rows[i]
    let kind = parse_effect_kind(opt_string(r, 0))
    let apply_order = parse_int_or_zero(opt_string(r, 1))
    let num = parse_int_or_zero(opt_string(r, 2))
    let den = parse_int_or_zero(opt_string(r, 3))
    let type_filter = opt_string(r, 4)
    let pokemon_filter = opt_string(r, 5)
    let is_physical : Int? = match r.get(6) {
      Some(Some(s)) => Some(parse_int_or_zero(s))
      _ => None
    }
    let super_effective_only = parse_int_or_zero(opt_string(r, 7)) != 0
    out.push({
      item_name,
      kind,
      apply_order,
      num,
      den,
      type_filter,
      pokemon_filter,
      is_physical,
      super_effective_only,
    })
  }
  Ok(out)
}

///|
fn opt_string(r : Array[String?], idx : Int) -> String {
  match r.get(idx) {
    Some(Some(s)) => s
    _ => ""
  }
}

///|
fn parse_int_or_zero(s : String) -> Int {
  let mut n = 0
  let mut started = false
  let mut sign = 1
  let mut i = 0
  if s.length() > 0 && s.unsafe_get(0) == 0x2D {
    sign = -1
    i = 1
  }
  while i < s.length() {
    let c = s.unsafe_get(i).to_int()
    if c >= 0x30 && c <= 0x39 {
      n = n * 10 + (c - 0x30)
      started = true
    } else {
      break
    }
    i = i + 1
  }
  if started { n * sign } else { 0 }
}
