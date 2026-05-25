///|
/// Stat-rank change produced by a move. `target` picks whose ranks get the
/// delta: `0` = self (attacker), `1` = opponent (defender). The `delta` is
/// added and clamped in `[-2, +2]` by the payoff layer (`clamp_rank`).
///
/// つるぎのまい — `[{stat:0, delta:2, target:0}]` (+2 Atk self)
/// あまえる     — `[{stat:0, delta:-2, target:1}]` (-2 Atk opp)
/// オーバーヒート — `[{stat:2, delta:-2, target:0}]` (-2 SpA self, post-hit)
pub(all) struct StatEffect {
  stat : Int
  delta : Int
  target : Int
} derive(Debug, Eq, Hash)

///|
/// HP-restoring effect carried by healing moves. The payoff layer applies
/// these in `with_post_hit_effects` (FixedFraction / WeatherDependent /
/// Drain / Rest / LeechSeed / PainSplit / Wish) and during EOT ticks
/// (Wish发动 / LeechSeed tick). All numerators / denominators are stored
/// as integers — the engine performs `max_hp * n / d` with integer
/// arithmetic to match mainline rounding.
///
/// - `FixedFraction(n, d)` — restore `max_hp * n / d` (じこさいせい = (1, 2))
/// - `WeatherDependent(default_n, default_d, sunny_n, sunny_d, harsh_n, harsh_d)` —
///   pick fraction by current weather (Sun → sunny, Rain/Sand/Snow → harsh,
///   None → default). つきのひかり / あさのひざし / シンセシス all share
///   the (1,2) / (2,3) / (1,4) triple.
/// - `Drain(n, d)` — restore `dmg_dealt * n / d` (ギガドレイン = (1, 2)).
///   `defender.ability == "ヘドロえき"` reverses the sign (attacker takes
///   damage instead) — handled by the payoff layer, not encoded here.
/// - `Rest` — full HP restore + self-Sleep(2). Fails (no HP / status change)
///   when the user is already at full HP, mirroring mainline behavior.
///   `Sleep` immunity abilities (ふみん / やるき / スイートベール) also
///   block the entire effect.
/// - `LeechSeed` — plant seed on defender; EOT tick drains 1/8 each turn.
/// - `PainSplit` — average both HP, clamped per side's max.
/// - `Wish` — slot-bound delayed heal: 2 EOT ticks later, restore
///   `max_hp / 2` on the Pokemon currently occupying the side's
///   active battle slot when the counter fires. `max_hp` is read off
///   the active slot's occupant at fire time, so Wish-and-switch is
///   correctly modelled — the replacement receives the heal, not the
///   original Wisher. Wish persists across switches (the counter is
///   side-scoped, not Pokemon-scoped) and re-uses overwrite the timer
///   to `2` (Gen9 later-wins semantics).
pub(all) enum HealingEffect {
  FixedFraction(Int, Int)
  WeatherDependent(Int, Int, Int, Int, Int, Int)
  Drain(Int, Int)
  Rest
  LeechSeed
  PainSplit
  Wish
} derive(Debug, Eq, Hash)

///|
/// A move (technique) usable by a Pokemon. Move metadata used by the payoff
/// layer (SwitchingGame / team_monte_carlo) travels inline on this struct:
///
/// - `priority ∈ [-7, +5]` — in-game action-order bucket. `0` for regular
///   moves, positive for priority moves (しんそく=+2, バレットパンチ=+1,
///   ねこだまし=+3, まもる=+4).
/// - `stat_effects` — list of `StatEffect` records applied on use. Both
///   self-target and opponent-target entries mix freely; the payoff layer
///   routes each entry by its `target` field. Empty for damaging-only moves
///   that have no rank side effects.
/// - `status_effect` — optional `(StatusKind, chance%)` pair for dedicated
///   status moves (鬼火 = `Some((BurnKind, 85))`, どくどく, ねむりごな等).
///   Secondary chances on damaging moves (ほのおのパンチ 10%やけど 等) are
///   not modelled in MVP — only dedicated status moves carry this field.
///
/// Post-hit side-effect fields are covered below. All payoff metadata fields
/// default to neutral values (`0` / `[]` / `None` / `false` / recoil `(0, 1)`)
/// so code constructing `Move` values without the new fields (legacy paths,
/// tests) keeps compiling with identical pre-refactor behaviour.
pub(all) struct Move {
  name : String
  type_ : String
  category : MoveCategory
  power : Int
  accuracy : Int
  pp : Int
  learn_method : String
  priority : Int
  stat_effects : Array[StatEffect]
  status_effect : (StatusKind, Int)?
  // Post-hit side effects used by the payoff layer.
  //
  // `recoil_num / recoil_den` — attacker HP loss as a fraction of damage
  // dealt this hit. `(0, 1)` means no recoil. When `recoil_num > 0` and
  // `dmg > 0`, the attacker loses `max(1, dmg * recoil_num / recoil_den)` HP
  // (minimum 1 HP enforced to match mainline behaviour). Immune / zero-damage
  // hits never apply recoil. Example: もろはのずつき `(1, 2)`, ブレイブバード `(1, 3)`.
  //
  // `self_ko` — attacker HP is forced to 0 after use regardless of damage
  // dealt (including type-immune 0-damage). Example: じばく, だいばくはつ.
  //
  // `recharge` — attacker must skip the turn after this one. The skip is
  // modelled on `SwitchingGameState.my_must_recharge` (or opp_) so major
  // status conditions (burn / paralysis / sleep) coexist with recharge.
  // Example: はかいこうせん, ギガインパクト.
  recoil_num : Int
  recoil_den : Int
  self_ko : Bool
  recharge : Bool
  // `healing` — optional HP-restoring effect carried by healing moves.
  // `None` for the vast majority of moves; populated from `move_meta` by
  // `parse_healing` when `heal_kind != ''`. See `HealingEffect` above for
  // the per-variant semantics. The payoff layer is responsible for
  // applying the effect; the DB / model layer just transports it.
  //
  // `weather_set` — for weather-setting moves (にほんばれ / あまごい /
  // すなあらし / ゆきげしき). `Some(weather)` indicates the move sets the
  // battlefield weather on use; `None` otherwise. Weather持続ターン数 (Gen9
  // base 5, weather rock 延長 8) は本 PR ではモデルしない — 後続 PR で
  // `Pokemon.item` を見て延長する。
  //
  // `field_set` — for field-setting (terrain) moves (エレキフィールド /
  // グラスフィールド / ミストフィールド / サイコフィールド).
  // `Some(field)` indicates the move sets the battlefield terrain on use;
  // `None` otherwise. Field 持続ターン数 (Gen9 base 5、Terrain Extender
  // による延長は別 PR) は本 PR ではモデルしない — Stage E 以降で SwitchingGame
  // 側に `field_turns_left` を持たせる。`Weather` と完全対称な構造。
  healing : HealingEffect?
  weather_set : Weather?
  field_set : Field?
} derive(Debug, Eq)
