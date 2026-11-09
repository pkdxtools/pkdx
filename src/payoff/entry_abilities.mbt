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
/// (index 0 = Attack, 4 = Speed). Writes go through `clamp_rank` (the
/// payoff layer's reduced `[-2, +2]`), except on a drop target that is
/// まけんき / かちき: its ranks are tracked over `[-6, +6]` (`clamp_rank_for`).
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
/// - まけんき / かちき and anything else: target A -1 through
///   `apply_opp_stat_drop`, then `apply_opp_drop_reaction` once. まけんき
///   (A +2) / かちき (SpA +2) react only when the drop actually landed.
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
    _ => {
      if apply_opp_stat_drop(target_ability, target_ranks, 0, -1) {
        apply_opp_drop_reaction(target_ability, target_ranks)
      }
    }
  }
}

///|
/// Apply one opponent-inflicted stat drop (`delta` < 0 on `stat`) to the rank
/// array of its holder (`owner_ability`). The caller has already resolved
/// blocking, reflection and reversal, so this is a drop that reached the
/// holder. It is shared by the entry path (いかく) and the post-hit path
/// (`apply_stat_effects` with `target = 1`), so both paths clamp identically.
///
/// Returns `true` when the drop actually changed the rank. A holder already at
/// the floor (-6 for まけんき / かちき) does not move, so the drop did not land.
/// The reaction is not run here: the caller runs `apply_opp_drop_reaction` once
/// per stat that landed (one いかく entry, or the stats of one move's
/// `stat_effects`, after all of the move's drops).
pub fn apply_opp_stat_drop(
  owner_ability : String,
  ranks : Array[Int],
  stat : Int,
  delta : Int,
) -> Bool {
  let before = ranks[stat]
  ranks[stat] = clamp_rank_for(owner_ability, before + delta)
  ranks[stat] != before
}

///|
/// The まけんき / かちき reaction to one opponent-inflicted stat drop that
/// landed (`apply_opp_stat_drop` returned `true`). Call it once per lowered
/// stat, not once per stage:
///
/// - まけんき (Defiant): Attack (index 0) +2.
/// - かちき (Competitive): Special Attack (index 2) +2.
///
/// The reaction is capped by `clamp_rank_for` at +6. A move that lowers two
/// stats (くすぐる / なみだめ) reacts twice. Ordinary holders are a no-op.
pub fn apply_opp_drop_reaction(owner_ability : String, ranks : Array[Int]) -> Unit {
  match owner_ability {
    "まけんき" => ranks[0] = clamp_rank_for(owner_ability, ranks[0] + 2)
    "かちき" => ranks[2] = clamp_rank_for(owner_ability, ranks[2] + 2)
    _ => ()
  }
}
