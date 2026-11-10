///|
/// Held item that resets negative stat stages: しろいハーブ (White Herb).
///
/// Showdown `items.ts` `whiteherb`: when the holder has at least one negative
/// stage, every negative stage is set to 0 and the item is consumed. The item
/// is single-use and stays consumed across switches (it is not returned to the
/// holder), so the per-slot consumption flag persists like the other held
/// items tracked by `my_item_consumed`.
///
/// Showdown checks the holder on switch-in (`onStart` / `onAnySwitchIn`), after
/// any move (`onAnyAfterMove`), after mega evolution (`onAnyAfterMega`) and at
/// residual (`onResidual`). pkdx calls `apply_held_item_stat_reset` at the same
/// four points, for both active slots:
///
/// - switch-in: after the entry いかく (and the Mirror Armor / Rattled
///   reflections it produces), before the turn's moves;
/// - after each move's effects: after `apply_stat_effects` (drops and the
///   まけんき / かちき reactions), so Defiant's boost is applied first and the
///   herb then clears only what is still negative;
/// - after mega evolution and at residual (`apply_eot`).
///
/// Negative stages can only be created by the entry いかく path and by
/// `apply_stat_effects`, and both are followed by a check, so the mega and
/// residual calls never find a negative stage in pkdx's own transitions.
/// They are kept so every Showdown check point has a counterpart here.
///
/// The consumed flag is the existing `my_item_consumed` / `opp_item_consumed`
/// slot array. It is written only for holders of this item, so a matchup
/// without it keeps every state byte-for-byte (same key, same state count).
/// A consumed item reads as itemless in the damage path (`damage_cache_layer`),
/// which matches Showdown; White Herb has no damage effect of its own.
///
/// Showdown does not run the holder's check when it has fainted (`getAllActive`
/// excludes fainted Pokemon), so `hp <= 0` is skipped here.

///|
/// Return `true` when the held item is しろいハーブ (White Herb), which resets
/// negative stat stages once. The DB name is the canonical spelling
/// (`champions.db` `items.name_ja`).
pub fn item_clears_negative_stages(item : String) -> Bool {
  item == "しろいハーブ"
}

///|
/// Return `true` when any stat stage of the rank array is negative.
fn has_negative_stage(ranks : Array[Int]) -> Bool {
  for r in ranks {
    if r < 0 {
      return true
    }
  }
  false
}

///|
/// Apply しろいハーブ to one side's active slot, mutating `ranks` and
/// `consumed` in place (the caller passes copies it owns).
///
/// `slot` is the side's active index; `hps` / `consumed` are the per-slot
/// arrays of the same side. Out-of-range slots are a no-op, which matches the
/// other per-slot helpers and legacy fixtures that size arrays short.
/// Triggers only when the slot holds the item, the flag is still unset, the
/// holder is alive, and at least one stage is negative. Every negative stage
/// is reset to 0 (positive stages, including a Defiant boost, are left alone).
pub fn apply_held_item_stat_reset(
  team : Array[Combatant],
  slot : Int,
  hps : Array[Int],
  ranks : Array[Int],
  consumed : Array[Bool],
) -> Unit {
  if slot < 0 || slot >= team.length() || slot >= hps.length() ||
    slot >= consumed.length() {
    return
  }
  if consumed[slot] || hps[slot] <= 0 || !has_negative_stage(ranks) {
    return
  }
  if !item_clears_negative_stages(team[slot].item) {
    return
  }
  for k in 0..<ranks.length() {
    if ranks[k] < 0 {
      ranks[k] = 0
    }
  }
  consumed[slot] = true
}

///|
/// The combatant the damage engine should read for `slot`: itemless once the
/// held item is consumed, the same swap `damage_cache_layer` applies on the DP
/// side. The MC rollout passes raw combatants, so without this a consumed
/// しろいハーブ would still count as held for Knock Off (はたきおとす), which
/// boosts only a target that still has a removable item.
pub fn consumed_item_view(
  team : Array[Combatant],
  slot : Int,
  consumed : Array[Bool],
) -> Combatant {
  let c = team[slot]
  if slot < consumed.length() && consumed[slot] && c.item != "" {
    { ..c, item: "" }
  } else {
    c
  }
}

///|
/// `apply_held_item_stat_reset` for both sides' active slots. Each side only
/// touches its own arrays, so the order of the two calls does not matter.
pub fn apply_held_item_stat_reset_pair(
  my_team : Array[Combatant],
  my_active : Int,
  my_hps : Array[Int],
  my_ranks : Array[Int],
  my_consumed : Array[Bool],
  opp_team : Array[Combatant],
  opp_active : Int,
  opp_hps : Array[Int],
  opp_ranks : Array[Int],
  opp_consumed : Array[Bool],
) -> Unit {
  apply_held_item_stat_reset(my_team, my_active, my_hps, my_ranks, my_consumed)
  apply_held_item_stat_reset(opp_team, opp_active, opp_hps, opp_ranks, opp_consumed)
}
