///|
/// Ability-based immunity layer used by the healing move pipeline.
///
/// The healing-move support introduces several distinct ability interactions
/// (sleep blockers refusing Rest / Drowsy, Magic Guard nullifying the
/// LeechSeed end-of-turn tick, Liquid Ooze reversing Drain into damage).
/// Centralising these checks in one file keeps the truth table reviewable
/// and avoids spreading ability string literals across `apply_healing` /
/// `apply_eot` / the team Monte Carlo rollout.
///
/// This layer intentionally only covers the abilities needed by healing
/// support. As later PRs surface more ability interactions (Flash Fire,
/// Storm Drain, etc.), additional helpers can be added here so all ability
/// dispatch stays in one place.

///|
/// Return `true` when the defender's ability prevents a status of `kind`
/// from being applied at all. Mirrors the mainline interaction where
/// Insomnia / Vital Spirit / Sweet Veil refuse both direct sleep and the
/// Drowsy → Sleep transition. Magic Guard is intentionally absent: it
/// suppresses residual damage, not the status application itself.
pub fn ability_blocks_status(
  ability : String,
  kind : @model.StatusKind,
) -> Bool {
  match (ability, kind) {
    ("ふみん", SleepKind) | ("ふみん", DrowsyKind) => true
    ("やるき", SleepKind) | ("やるき", DrowsyKind) => true
    ("スイートベール", SleepKind) | ("スイートベール", DrowsyKind) => true
    _ => false
  }
}

///|
/// Return `true` when the ability nullifies the LeechSeed end-of-turn tick.
/// The seed itself can still be planted on a Magic Guard target — mainline
/// distinguishes "planting" from "ticking" — so callers must apply this
/// check at EOT, not at move-use time.
pub fn ability_blocks_leech_seed(ability : String) -> Bool {
  ability == "マジックガード"
}

///|
/// Return `true` when the ability reverses a Drain move's heal into damage
/// against the attacker. Mirrors Liquid Ooze (ヘドロえき) on the defender.
pub fn ability_reverses_drain(ability : String) -> Bool {
  ability == "ヘドロえき"
}

///|
/// Return `true` when the ability suppresses sandstorm chip damage at EOT.
/// Mirrors the mainline immunity set: マジックガード (Magic Guard) blocks all
/// indirect damage including sandstorm; すなかき (Sand Rush) / すながくれ
/// (Sand Veil) / すなのちから (Sand Force) hold implicit sandstorm immunity;
/// ぼうじん (Overcoat) is the Gen6+ dust/sand blocker that also nullifies
/// sandstorm chip. すなおこし (Sand Stream) only *summons* sand — it grants
/// no chip immunity of its own, so it is intentionally absent here; its
/// canonical users are Rock / Ground and covered by the type check at the
/// call site. Type-based immunity (はがね / いわ / じめん) is handled at the
/// call site against the post-mega type pair returned by `effective_combatant`.
pub fn ability_blocks_sand_damage(ability : String) -> Bool {
  match ability {
    "マジックガード" => true
    "すなかき" => true
    "すながくれ" => true
    "すなのちから" => true
    "ぼうじん" => true
    _ => false
  }
}
