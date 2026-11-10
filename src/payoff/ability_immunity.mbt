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
    ("スイートベール", SleepKind)
    | ("スイートベール", DrowsyKind) => true
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

///|
/// Return `true` when the ability nullifies Intimidate's Attack drop on the
/// holder. Two mainline groups collapse into this truth table: the Gen8+
/// Intimidate-specific blockers どんかん (Oblivious) / マイペース (Own Tempo)
/// / せいしんりょく (Inner Focus) / きもったま (Scrappy), and the general
/// stat-drop blockers クリアボディ (Clear Body) / かいりきバサミ (Hyper
/// Cutter) / しろいけむり (White Smoke) / メタルプロテクト (Full Metal
/// Body — note: no long vowel mark, matches the DB canonical spelling).
/// Redirecting abilities (ばんけん / ミラーアーマー / びびり / あまのじゃく)
/// are intentionally absent: they transform the drop rather than block it
/// and are dispatched in `apply_intimidate_on_entry`.
pub fn ability_blocks_intimidate(ability : String) -> Bool {
  match ability {
    "どんかん" => true
    "マイペース" => true
    "せいしんりょく" => true
    "きもったま" => true
    "クリアボディ" => true
    "かいりきバサミ" => true
    "しろいけむり" => true
    "メタルプロテクト" => true
    _ => false
  }
}

///|
/// Return `true` when the holder's ability nullifies one stat drop that an
/// opponent's move inflicts on it: a post-hit `stat_effects` entry with
/// `target = 1` and a negative delta (after the あまのじゃく flip).
/// `stat` is the rank index (0 = Attack ... 4 = Speed).
///
/// Mirrors Showdown's `onTryBoost` for the generic blockers. Clear Body
/// (クリアボディ), White Smoke (しろいけむり) and Full Metal Body (メタルプロテクト)
/// share one body: every negative boost from another source is deleted. Hyper
/// Cutter (かいりきバサミ) deletes only an Attack drop, so it blocks `stat = 0`
/// alone. Self-inflicted drops (`target = 0`) never reach this predicate, since
/// Showdown skips the check when `target === source`.
///
/// The Intimidate-only blockers (どんかん / マイペース / せいしんりょく /
/// きもったま) are absent on purpose: Showdown gates them on
/// `effect.name === 'Intimidate'`, so a move's drop still lands. Guard Dog
/// (ばんけん) is likewise Intimidate-only and does not appear here.
pub fn ability_blocks_opp_stat_drop(ability : String, stat : Int) -> Bool {
  match ability {
    "クリアボディ" => true
    "しろいけむり" => true
    "メタルプロテクト" => true
    "かいりきバサミ" => stat == 0
    _ => false
  }
}

///|
/// Return `true` when the ability inverts every stat stage change applied to
/// the holder. Mirrors あまのじゃく (Contrary): drops become raises and vice
/// versa. Callers flip the sign of the delta before clamping.
pub fn ability_reverses_stat_changes(ability : String) -> Bool {
  ability == "あまのじゃく"
}

///|
/// Return `true` when the ability reacts to a stat drop inflicted by the
/// opponent. まけんき (Defiant) raises Attack by 2, かちき (Competitive) raises
/// Special Attack by 2, once per opponent-lowered stat that actually landed
/// (`apply_opp_drop_reaction`). Holders are tracked over the real ±6 stage range
/// (see `clamp_rank_for`).
pub fn ability_boosts_on_opp_drop(ability : String) -> Bool {
  ability == "まけんき" || ability == "かちき"
}
