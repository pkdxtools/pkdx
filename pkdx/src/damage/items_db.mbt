///|
/// DB-backed item resolution mirroring `damage/items.mbt`'s hardcoded
/// computations (issue #94 — P2-C). Functions accept the already-fetched
/// `Array[ItemEffect]` so the damage engine doesn't need a Db handle in
/// its hot loop — callers query once via `query_item_effects` and pass
/// the result through.
///
/// MVP scope: matches hardcode behaviour for the 3 seeded items shipped
/// by `m013_items` (こだわりハチマキ / いのちのたま / オッカのみ). Full
/// parity with the rest of `damage/items.mbt` is a follow-up; until
/// then the engine path falls back to the hardcode functions when the
/// effects array is empty.

///|
/// Apply attacker stat-mod effects (`apply_order = 2`). Multiplies the
/// attacker stat by `num/den` for matching `is_physical` polarity.
pub fn apply_atk_item_stat_db(
  effects : Array[@db.ItemEffect],
  is_physical : Bool,
  atk_stat : Int,
) -> Int {
  let mut s = atk_stat
  for i = 0; i < effects.length(); i = i + 1 {
    let e = effects[i]
    match e.kind {
      @db.StatMod =>
        if e.den != 0 && polarity_matches(e.is_physical, is_physical) {
          s = s * e.num / e.den
        }
      _ => ()
    }
  }
  s
}

///|
/// Apply final-mod effects (4096 base) collected from the items table.
/// Returns the modifier value (`num` when den == 4096) so the caller
/// can route through the engine's existing `round5(dmg, mod)` machinery.
/// `0` means no item-final modifier applies.
pub fn get_atk_item_final_db(
  effects : Array[@db.ItemEffect],
  is_physical : Bool,
  is_super_effective : Bool,
) -> Int {
  for i = 0; i < effects.length(); i = i + 1 {
    let e = effects[i]
    match e.kind {
      @db.FinalMod =>
        if polarity_matches(e.is_physical, is_physical) {
          if e.super_effective_only && not(is_super_effective) {
            // skip
          } else {
            return e.num
          }
        }
      _ => ()
    }
  }
  0
}

///|
/// Resist-berry inquiry. Returns the matching type (e.g. "ほのお" for
/// オッカのみ) when this item is a resist berry, else "". Callers
/// compare against the incoming move type and the SE flag to decide
/// whether to apply the 2048/4096 reduction.
pub fn get_resist_berry_type_db(effects : Array[@db.ItemEffect]) -> String {
  for i = 0; i < effects.length(); i = i + 1 {
    let e = effects[i]
    match e.kind {
      @db.ResistBerry => return e.type_filter
      _ => ()
    }
  }
  ""
}

///|
/// `is_physical : Int?` semantics — None ⇒ no polarity filter, Some(1)
/// ⇒ physical only, Some(0) ⇒ special only.
fn polarity_matches(filter : Int?, is_physical : Bool) -> Bool {
  match filter {
    None => true
    Some(1) => is_physical
    Some(0) => not(is_physical)
    Some(_) => true
  }
}
