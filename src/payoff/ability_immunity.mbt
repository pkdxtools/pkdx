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
/// Return `true` when the ability stops the defender from being frozen
/// (こおり). マグマのよろい: "The Pokémon cannot be frozen." (Champions
/// tokuseiinfo_syn.json:1348). Only the freeze rule is added: the other
/// status-immunity abilities (ふみん etc.) are not applied to the secondary
/// fanout in the model, so this is deliberately freeze-specific.
pub fn ability_blocks_freeze(ability : String) -> Bool {
  ability == "マグマのよろい"
}

///|
/// Return `true` when the defender's ability blocks the additional (secondary)
/// effects of an attacking damaging move. りんぷん (Shield Dust): "The
/// Pokémon is immune to additional effects from attacks." (Champions
/// tokuseiinfo_syn.json:606). Only the freeze secondary is modelled today, so
/// the caller applies it to freeze-carrying damaging moves.
pub fn ability_blocks_secondary(ability : String) -> Bool {
  ability == "りんぷん"
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
/// Return `true` when the ability blocks the crash HP loss of a crash move (崩れ
/// 技, `is_crash_move`). Mirrors Showdown `magicguard.onDamage`: any damage whose
/// effect is not a `Move` is cancelled, and the crash damage is applied with the
/// move as its effect's `Condition` wrapper (`dex.conditions.get('High Jump Kick')`),
/// so マジックガード cancels it. No other damage-blocking ability applies: Sturdy /
/// Disguise / Ice Face require `effectType === 'Move'`, and Rock Head only blocks
/// `recoil`.
pub fn ability_blocks_crash_damage(ability : String) -> Bool {
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

///|
/// Return the stat boost the holder gains when it absorbs a move aimed at it,
/// as `(stat, delta)` with `stat` the rank index (0 = Attack), or `None` for
/// every other holder. そうしょく (Sap Sipper) raises Attack by 1. Showdown runs
/// it as `onTryHit` (`this.boost({ atk: 1 })`), which precedes the accuracy roll
/// in Gen 9, so the boost does not depend on accuracy. At +6 the holder still
/// absorbs; only the boost is lost.
pub fn ability_absorb_boost(ability : String) -> (Int, Int)? {
  match ability {
    "そうしょく" => Some((0, 1))
    _ => None
  }
}

///|
/// Return `true` when the holder absorbs the move `move_name` (resolved type
/// `move_type`) that is aimed at it. An absorbed move does no damage and has no
/// secondary, status, or self effect, and the holder gets `ability_absorb_boost`.
/// Only holders with an absorb boost qualify, so the other immunity abilities
/// keep their existing path. Type matching is the damage engine's
/// `check_def_immunity` (single source of truth). Non-foe Grass moves
/// (`is_grass_non_foe_target_move`: ねをはる / グラスフィールド ...) never reach the
/// holder and are excluded.
pub fn ability_absorbs_move(
  ability : String,
  move_name : String,
  move_type : String,
) -> Bool {
  match ability_absorb_boost(ability) {
    Some(_) =>
      @damage.check_def_immunity(ability, move_type) &&
        !@damage.is_grass_non_foe_target_move(move_name)
    None => false
  }
}

///|
/// Return `true` when the holder's ranks are tracked over the real ±6 stage
/// range (see `clamp_rank_for`) rather than the payoff layer's reduced ±2:
/// まけんき / かちき (the reaction needs the true floor) and そうしょく (its +1 must
/// stop at +6, not at +2).
pub fn ability_tracks_full_stages(ability : String) -> Bool {
  if ability_boosts_on_opp_drop(ability) {
    return true
  }
  match ability_absorb_boost(ability) {
    Some(_) => true
    None => false
  }
}
