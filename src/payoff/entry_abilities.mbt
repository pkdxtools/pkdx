///|
/// Entry-time ability triggers applied to the payoff-layer rank arrays.
///
/// This file hosts abilities that fire when a combatant *enters* the field
/// (lead reveal, voluntary switch, replacement after a faint). Centralising
/// them keeps the trigger truth table next to `ability_immunity` and out of
/// the game-tree transition code. Currently only いかく (Intimidate) is
/// modelled; later entry triggers (weather setters already live in the
/// weather layer) can be added here.

///|
/// Apply いかく (Intimidate) at entry time, mutating the rank arrays in
/// place. Rank arrays follow the module convention `[A, B, C, D, S]`
/// (index 0 = Attack, 4 = Speed) and every write goes through `clamp_rank`
/// so ranks stay inside the payoff layer's reduced `[-2, +2]` range.
///
/// Call-site contract:
///
/// - "Entry" means *every* arrival on the field: the opening lead, a
///   voluntary switch, and a replacement sent out after a faint. The caller
///   invokes this helper on each such event.
/// - Mega Evolution does not re-trigger Intimidate — the caller only invokes
///   this at entry, never on mid-turn form changes.
/// - When both sides enter simultaneously (both leads, double switch), the
///   caller invokes the helper once per entrant; each invocation handles one
///   direction, so mutual いかく resolves as two independent calls.
///
/// Target-ability dispatch (a combatant holds exactly one ability, so the
/// arms are mutually exclusive):
///
/// - ばんけん (Guard Dog): the drop becomes a raise — target A +1.
/// - ミラーアーマー (Mirror Armor): the drop bounces back — entrant A -1,
///   target untouched. No re-reflection: an Intimidate entrant cannot also
///   hold a blocking ability, so a plain -1 is exact.
/// - びびり (Rattled): target A -1 *and* S +1 (Gen8+ lets Intimidate
///   trigger Rattled).
/// - あまのじゃく (Contrary): the drop inverts — target A +1.
/// - `ability_blocks_intimidate` abilities: no-op.
/// - Anything else: target A -1.
pub fn apply_intimidate_on_entry(
  entrant_ability : String,
  target_ability : String,
  target_ranks : Array[Int],
  entrant_ranks : Array[Int],
) -> Unit {
  if entrant_ability != "いかく" {
    return
  }
  match target_ability {
    "ばんけん" => target_ranks[0] = clamp_rank(target_ranks[0] + 1)
    "ミラーアーマー" =>
      entrant_ranks[0] = clamp_rank(entrant_ranks[0] - 1)
    "びびり" => {
      target_ranks[0] = clamp_rank(target_ranks[0] - 1)
      target_ranks[4] = clamp_rank(target_ranks[4] + 1)
    }
    ability if ability_reverses_stat_changes(ability) =>
      target_ranks[0] = clamp_rank(target_ranks[0] + 1)
    ability if ability_blocks_intimidate(ability) => ()
    _ => target_ranks[0] = clamp_rank(target_ranks[0] - 1)
  }
}
