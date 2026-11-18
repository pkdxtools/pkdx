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
/// Return `true` when the holder's ability prevents a status of `kind` from
/// being applied. Existing sleep immunities are unchanged: ふみん / やるき /
/// スイートベール refuse both direct sleep and Drowsy. Magic Guard is
/// intentionally absent: it suppresses residual damage, not the status
/// application itself. マグマのよろい stays in `ability_blocks_freeze`.
///
/// Champions text (`champout` `50e7233`, `rom-txt/usa/tokuseiinfo_syn.json`,
/// LabelName line). Japanese names are `tokusei.json` of the same index.
/// - じゅうなん `TOKUSEI_007` / `TOKUSEIINFO_SYN_007:256`: "cannot be paralyzed."
/// - めんえき `TOKUSEI_017` / `:544`: "cannot be poisoned or badly poisoned."
/// - すいほう `TOKUSEI_199` / `:6396` and ねつこうかん `TOKUSEI_270` / `:7654`:
///   "cannot be burned." (Water Bubble's damage mods and Thermal Exchange's
///   Attack boost are outside this predicate.)
/// - きよめのしお `TOKUSEI_272` / `:7712`: "immune to status conditions."
/// - リーフガード `TOKUSEI_102` / `:3566`: "immune to status conditions in
///   harsh sunlight" (`weather == Sun` only).
/// - フラワーベール `TOKUSEI_166` / `:5468`: "Grass-type allies are immune to
///   status conditions". Singles has no other ally, so the holder is covered
///   only when it is Grass (`type1` / `type2`). `self_inflicted` (Rest) is not
///   blocked: Champions text states no self-exception; Showdown
///   `onAllySetStatus` requires `target !== source`.
///
/// "Status conditions" in `help_syn.json:25431` lists poison, bad poison, burn,
/// paralysis, freeze, and sleep. Yawn (DrowsyKind) is not in that list.
/// Showdown blocks the yawn volatile for Purifying Salt, Leaf Guard in sun,
/// and Flower Veil on Grass, so those abilities block every `StatusKind`,
/// including Drowsy. The predicate does not cure a status the holder already
/// has (Champions text is "cannot be" / 「ならない」, not a cure). マイペース
/// (`TOKUSEIINFO_SYN_020:628`) only stops confusion (unmodelled) and Intimidate
/// (already `ability_blocks_intimidate`), so it is absent here.
pub fn ability_blocks_status(
  ability : String,
  kind : @model.StatusKind,
  weather? : @model.Weather = @model.Weather::None,
  type1? : String = "",
  type2? : String = "",
  self_inflicted? : Bool = false,
) -> Bool {
  let specific = match (ability, kind) {
    ("ふみん", SleepKind) | ("ふみん", DrowsyKind) => true
    ("やるき", SleepKind) | ("やるき", DrowsyKind) => true
    ("スイートベール", SleepKind)
    | ("スイートベール", DrowsyKind) => true
    ("じゅうなん", ParalyzeKind) => true
    ("めんえき", PoisonKind) | ("めんえき", BadPoisonKind) => true
    ("すいほう", BurnKind) | ("ねつこうかん", BurnKind) => true
    _ => false
  }
  if specific {
    return true
  }
  // 全状態異常 (help の 6 種 + あくび)。あくびは Showdown fallback。
  if ability == "きよめのしお" {
    return true
  }
  if ability == "リーフガード" && weather == @model.Weather::Sun {
    return true
  }
  if ability == "フラワーベール" &&
    !self_inflicted &&
    (type1 == "くさ" || type2 == "くさ") {
    return true
  }
  false
}

///|
/// Return `true` when the ability stops the defender from being frozen
/// (こおり). マグマのよろい: "The Pokémon cannot be frozen." (Champions
/// tokuseiinfo_syn.json:1348). Freeze-only. All-status abilities that also
/// stop freeze (きよめのしお / リーフガード in sun / フラワーベール on Grass)
/// go through `ability_blocks_status`, not this predicate.
pub fn ability_blocks_freeze(ability : String) -> Bool {
  ability == "マグマのよろい"
}

///|
/// Return `true` when the defender's ability blocks the additional (secondary)
/// effects of an attacking damaging move. りんぷん (Shield Dust): "The
/// Pokémon is immune to additional effects from attacks." (Champions
/// tokuseiinfo_syn.json:606). The caller applies it to every status secondary
/// of a damaging move (`power > 0`): こおり / やけど / まひ / どく / もうどく.
pub fn ability_blocks_secondary(ability : String) -> Bool {
  ability == "りんぷん"
}

///|
/// Return `true` when the attacker's ability removes the additional (secondary)
/// effects of its own damaging moves. ちからずく (Sheer Force): "The Pokémon's
/// moves lose their additional effects, but the power of those moves will be
/// boosted by 30%." (Champions tokuseiinfo_syn.json:4170, TOKUSEIINFO_SYN_125).
/// The fanouts (`secondary_gated_move` / `mc_try_apply_status` /
/// `mc_flinch_roll`) drop `status_effect` and `flinch_chance` on damaging
/// moves. The 1.3x boost is the same set: `move_has_sheer_force_effect`
/// (damage engine `get_atk_ability_final`). A move with neither is not boosted.
pub fn ability_strips_secondaries(ability : String) -> Bool {
  ability == "ちからずく"
}

///|
/// Return `true` when the ability stops the holder from flinching (ひるみ).
/// せいしんりょく (Inner Focus): "The Pokémon never flinches when attacked and is
/// unaffected by Intimidate." (Champions tokuseiinfo_syn.json:039). The Intimidate
/// half is `ability_blocks_intimidate`. Showdown refuses the flinch volatile itself
/// (`onTryAddVolatile`), so no flinch is applied and ふくつのこころ does not fire.
pub fn ability_blocks_flinch(ability : String) -> Bool {
  ability == "せいしんりょく"
}

///|
/// Return `true` when the ability raises the holder's Speed by one stage each time
/// the holder flinches. ふくつのこころ (Steadfast): "When the Pokémon flinches, its
/// Speed stat is boosted by 1 stage." (Champions tokuseiinfo_syn.json:080). The DP and
/// MC fire it only when the flinch stops the holder's own action (see
/// `flinched_outcomes`), matching Showdown's `Flinch` event.
pub fn ability_flinch_speed_boost(ability : String) -> Bool {
  ability == "ふくつのこころ"
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
/// 粉技が受け手に効かない。champout `50e7233`:
/// - `help_syn.json` `help_11_15_01`: powder moves have no effect on the
///   Overcoat ability or Grass-type Pokémon.
/// - `help_10_03_00`: Grass types are immune to moves and abilities involving
///   powder.
/// - `TOKUSEIINFO_SYN_142` (ぼうじん): immune to moves and abilities involving
///   powder.
///
/// The move set is `@damage.is_powder_move` (waza classification 6).
/// ぼうじんゴーグル is not in Champions `itemname.json`, so items are not
/// consulted. ほうし (Effect Spore) is a powder ability, not a move, and stays
/// on the contact-proc path. Absorb (TryHit) is earlier than this predicate;
/// callers must return before it when the move is absorbed.
pub fn powder_move_blocked(
  move_name : String,
  type1 : String,
  type2 : String,
  ability : String,
) -> Bool {
  @damage.is_powder_move(move_name) &&
  (type1 == "くさ" || type2 == "くさ" || ability == "ぼうじん")
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
/// Champions `tokuseiinfo_syn.json` (`champout` `50e7233`), same gate as
/// Showdown `onTryBoost` (`target === source` is exempt, so self drops never
/// reach this predicate):
/// - クリアボディ `TOKUSEIINFO_SYN_029` and しろいけむり `TOKUSEIINFO_SYN_073`:
///   「相手の技や特性で能力を下げられない。」 Every modelled stat.
/// - かいりきバサミ `TOKUSEIINFO_SYN_052`: 「相手の技や特性で攻撃を下げられない。」
///   Attack (`stat = 0`) only.
/// - はとむね `TOKUSEIINFO_SYN_145`: 「相手の技や特性で防御を下げられない。」
///   Defense (`stat = 1`) only.
/// - フラワーベール `TOKUSEIINFO_SYN_166` (usa `:5470`, jpn `:5326`): 「味方のくさ
///   タイプのポケモンは能力が下がらず状態異常にもならない。」Singles has no other
///   ally, so every modelled stat is blocked only when the holder itself is
///   Grass (`type1` / `type2`). Callers that omit the types (default `""`) do
///   not block, which keeps a non-Grass holder — and every pre-existing call —
///   on the old path. Self drops never reach this predicate (`target = 0`).
///
/// するどいめ (`TOKUSEIINFO_SYN_051`) and はっこう (`TOKUSEIINFO_SYN_035`) say
/// accuracy cannot be lowered and evasion changes are ignored. The rank array
/// is only `[A, B, C, D, S]`, so those stats are not blocked here.
/// メタルプロテクト is not in Champions `tokusei.json`. The name is kept so an
/// explicit Full Metal Body string still blocks every stat (Showdown's shared
/// body). It does not appear on a Champions team.
///
/// The Intimidate-only blockers (どんかん / マイペース / せいしんりょく /
/// きもったま) are absent on purpose: Showdown gates them on
/// `effect.name === 'Intimidate'`, so a move's drop still lands. Guard Dog
/// (ばんけん) is likewise Intimidate-only and does not appear here. はとむね
/// does not block Intimidate: that drop is Attack, not Defense.
pub fn ability_blocks_opp_stat_drop(
  ability : String,
  stat : Int,
  type1? : String = "",
  type2? : String = "",
) -> Bool {
  match ability {
    "クリアボディ" => true
    "しろいけむり" => true
    "メタルプロテクト" => true
    "かいりきバサミ" => stat == 0
    "はとむね" => stat == 1
    // くさ以外は false。type を渡さない既存呼び出しもここには来ない
    // (フラワーベールは従来この関数の対象外だった)。
    "フラワーベール" => type1 == "くさ" || type2 == "くさ"
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
/// as `(stat, delta)` with `stat` the rank index (0 = Attack, 2 = SpA,
/// 4 = Speed), or `None` when the absorb has no stage change. Showdown runs
/// the boost in `onTryHit`, which precedes the accuracy roll, so it does not
/// depend on accuracy. At +6 the holder still absorbs; only the boost is lost.
///
/// Champions `tokuseiinfo_syn.json` (`champout` `50e7233`):
/// - そうしょく `TOKUSEIINFO_SYN_157`: Grass moves boost Attack by 1.
/// - でんきエンジン `TOKUSEIINFO_SYN_078`: Electric moves boost Speed by 1.
/// - ひらいしん `TOKUSEIINFO_SYN_031`: draws in Electric moves and boosts
///   Sp. Atk by 1. Singles has no second target, so this is immunity plus the
///   boost. Redirection is not modeled.
/// よびみず is not in Champions `tokusei.json`, so it is not given a boost.
pub fn ability_absorb_boost(ability : String) -> (Int, Int)? {
  match ability {
    "そうしょく" => Some((0, 1))
    "ひらいしん" => Some((2, 1))
    "でんきエンジン" => Some((4, 1))
    _ => None
  }
}

///|
/// Denominator of the max-HP heal applied when the holder absorbs a move, or
/// `None` when the absorb does not heal. Champions text (`50e7233`):
/// - ちくでん `TOKUSEIINFO_SYN_010`: Electric moves restore 1/4 max HP.
/// - ちょすい `TOKUSEIINFO_SYN_011`: Water moves restore 1/4 max HP.
/// - かんそうはだ `TOKUSEIINFO_SYN_087`: the Water sentence is the same 1/4.
///   The Fire 1.25× is `get_def_type_resist` (power only, not a second 5120
///   final). Rain / sun end-of-turn 1/8 is `apply_dry_skin_weather_active`,
///   not this absorb.
pub fn ability_absorb_heal_denom(ability : String) -> Int? {
  match ability {
    "ちくでん" | "ちょすい" | "かんそうはだ" => Some(4)
    _ => None
  }
}

///|
/// HP after an absorb heal, capped at `max_hp`. A fainted holder (`current_hp
/// <= 0`) is unchanged: Showdown does not run `onTryHit` on a fainted target.
/// A full holder still absorbs; the heal adds nothing. Integer division matches
/// Showdown `baseMaxhp / 4`.
pub fn absorb_healed_hp(
  ability : String,
  current_hp : Int,
  max_hp : Int,
) -> Int {
  if current_hp <= 0 {
    return current_hp
  }
  match ability_absorb_heal_denom(ability) {
    None => current_hp
    Some(den) => {
      if den <= 0 || max_hp <= 0 {
        return current_hp
      }
      let healed = current_hp + max_hp / den
      if healed > max_hp {
        max_hp
      } else {
        healed
      }
    }
  }
}

///|
/// `true` when `ability` nullifies a move of `move_type` aimed at the holder
/// (Showdown `onTryHit` returns null). ふゆう stays on the damaging-immunity
/// path (`check_def_immunity` / `is_grounded`): Champions gives it no heal or
/// boost, and the only available Ground status move is まきびし (foe side).
/// よびみず is not a Champions ability, so it is not an absorb either.
fn ability_absorb_type(ability : String, move_type : String) -> Bool {
  match ability {
    "そうしょく" => move_type == "くさ"
    "ちくでん" | "ひらいしん" | "でんきエンジン" => move_type == "でんき"
    "ちょすい" | "かんそうはだ" => move_type == "みず"
    // もらいび: ほのおを吸収し、もらいび状態を付ける (TOKUSEIINFO_SYN_018)。
    // 威力 1.5 は状態が立っているときだけ `attacker_for_flash_fire` が通す。
    "もらいび" => move_type == "ほのお"
    _ => false
  }
}

///|
/// Return `true` when the holder absorbs the move `move_name` (resolved type
/// `move_type`) that is aimed at it. An absorbed move does no damage and has no
/// secondary, status, or self effect. The holder then gets `ability_absorb_boost`
/// and `absorb_healed_hp`. Self, ally, field, and foe-side moves
/// (`is_absorb_non_foe_target_move`) never reach the holder.
pub fn ability_absorbs_move(
  ability : String,
  move_name : String,
  move_type : String,
) -> Bool {
  ability_absorb_type(ability, move_type) &&
  !@damage.is_absorb_non_foe_target_move(move_name)
}

///|
/// `true` when slot `slot` of `flags` is in the Flash Fire status.
/// A short array (untracked fixture) is not ignited.
pub fn flash_fire_lit(flags : Array[Bool], slot : Int) -> Bool {
  slot >= 0 && slot < flags.length() && flags[slot]
}

///|
/// Copy of `flags` with `slot` set. Already-lit slots return the same array.
/// A short array grows so a length-0 fixture still records the status.
pub fn with_flash_fire_lit(flags : Array[Bool], slot : Int) -> Array[Bool] {
  if slot < 0 {
    return flags
  }
  if slot < flags.length() {
    if flags[slot] {
      return flags
    }
    let out = flags.copy()
    out[slot] = true
    return out
  }
  let out = Array::make(slot + 1, false)
  for i in 0..<flags.length() {
    out[i] = flags[i]
  }
  out[slot] = true
  out
}

///|
/// Clear `slot` in place. Out of range is a no-op (same guard as leech seed).
pub fn clear_flash_fire_slot(flags : Array[Bool], slot : Int) -> Unit {
  if slot >= 0 && slot < flags.length() {
    flags[slot] = false
  }
}

///|
/// Attacker view for the damage engine. `apply_atk_ability_power` multiplies
/// Fire move power by 3/2 whenever the ability string is もらいび. That 1.5×
/// is the Flash Fire status (`BTR_STATE_SYN_121_02`), not the ability alone.
/// Until the status is lit, a Fire move is calculated as if the attacker had
/// no ability. Every other ability, and every non-Fire move, returns `atk`
/// unchanged so the calc input stays bit-identical.
pub fn attacker_for_flash_fire(
  atk : Combatant,
  mv : @model.Move,
  weather : @model.Weather,
  lit : Bool,
) -> Combatant {
  if lit || atk.ability != "もらいび" {
    return atk
  }
  let ty = @damage.resolve_effective_move_type(mv, weather, atk.ability)
  if ty != "ほのお" {
    return atk
  }
  { ..atk, ability: "" }
}

///|
/// A damaging move (`power > 0`) that the defender nullifies before the
/// accuracy roll. Showdown Gen 9 runs `TypeImmunity` and `TryImmunity` before
/// `Accuracy`, so there is no miss branch. Status moves stay on the accuracy
/// roll: the damage pipeline does not mark `power <= 0` as the immune
/// sentinel. Absorb abilities (そうしょく and the heal / boost set) nullify
/// their status moves in `ability_absorbs_move`, not this predicate. A status
/// move the foe is immune to is `status_move_fails_on_foe`, not this
/// predicate: `power <= 0` is not the immune sentinel, so でんじは would
/// otherwise paralyze じめん. ちくでん is in `check_def_immunity`, so a
/// damaging Electric move is also this sentinel (サンダーダイブ still crashes).
pub fn damaging_move_immune(
  ability : String,
  move_name : String,
  move_type : String,
  power : Int,
  def_type1 : String,
  def_type2 : String,
) -> Bool {
  if power <= 0 {
    return false
  }
  if @damage.check_def_immunity(ability, move_type) {
    return true
  }
  let (e1, e2) = @damage.move_effectiveness_slots_x4(
    move_name, move_type, def_type1, def_type2,
  )
  e1 == 0 || e2 == 0
}

///|
/// Return `true` when the holder's ranks are tracked over the real ±6 stage
/// range (see `clamp_rank_for`) rather than the payoff layer's reduced ±2:
/// まけんき / かちき (the reaction needs the true floor) and absorb boosts
/// (そうしょく / ひらいしん / でんきエンジン: the +1 must stop at +6, not at +2).
pub fn ability_tracks_full_stages(ability : String) -> Bool {
  if ability_boosts_on_opp_drop(ability) {
    return true
  }
  match ability_absorb_boost(ability) {
    Some(_) => true
    None => false
  }
}

///|
/// かたやぶり。Champions `tokusei.json` Index 104 / `TOKUSEIINFO_SYN_104`
/// （`champout` `50e7233`）: 「相手の特性に関係なく技を出すことができる。例外と
/// なる特性もある。」ターボブレイズとテラボルテージはその tokusei に無い。
/// すりぬけは壁だけを貫通し、特性は無視しない。
pub fn is_mold_breaker_ability(ability : String) -> Bool {
  ability == "かたやぶり"
}

///|
/// 技の解決中にかたやぶりが無視する、pkdx が既にモデルしている受け手特性。
/// Showdown の `flags.breakable`（`suppressingAbility` が ability ハンドラを
/// 落とす条件）に合わせる。登場時いかくとターン終了はここを通さない。
///
/// 無視しない実装済み特性: プリズムアーマー / メタルプロテクト（breakable で
/// ない）、マジックガード / ヘドロえき / まけんき / かちき / じきゅうりょく /
/// ふくつのこころ / 接触特性（ほのおのからだ等）/ ちからもち（攻撃側の倍率。
/// breakable でない）。どんかん / マイペースはいかく専用で、技の解決では
/// 読まれない。
pub fn ability_ignored_by_mold_breaker(ability : String) -> Bool {
  match ability {
    "ふゆう" | "ちょすい" | "よびみず" | "もらいび" | "ちくでん" | "ひらいしん"
    | "でんきエンジン" | "かんそうはだ" | "そうしょく" | "あついしぼう"
    | "たいねつ" | "すいほう" | "もふもふ" | "ファーコート" | "マルチスケイル"
    | "フィルター" | "ハードロック" | "こおりのりんぷん" | "クリアボディ"
    | "しろいけむり" | "かいりきバサミ" | "はとむね" | "フラワーベール"
    | "あまのじゃく" | "りんぷん" | "せいしんりょく" | "ぼうじん" | "ふみん"
    | "やるき" | "スイートベール" | "じゅうなん" | "めんえき" | "マグマのよろい"
    | "リーフガード" | "きよめのしお" | "ねつこうかん" | "ばけのかわ"
    | "てんねん" =>
      true
    _ => false
  }
}

///|
/// 技の解決で受け手の特性として見る文字列。攻撃側がかたやぶりで、受け手特性が
/// `ability_ignored_by_mold_breaker` のときだけ `""`。それ以外は `def_ability`
/// をそのまま返す（分岐の加算順を変えない）。
pub fn defender_ability_for_move(
  atk_ability : String,
  def_ability : String,
) -> String {
  if is_mold_breaker_ability(atk_ability) &&
    ability_ignored_by_mold_breaker(def_ability) {
    ""
  } else {
    def_ability
  }
}

///|
/// `defender_ability_for_move` を Combatant に載せた写し。無視しないときは
/// 引数そのものを返す。
pub fn defender_for_mold_breaker(atk : Combatant, def : Combatant) -> Combatant {
  let seen = defender_ability_for_move(atk.ability, def.ability)
  if seen == def.ability {
    def
  } else {
    { ..def, ability: seen }
  }
}
