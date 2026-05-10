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
} derive(Show, Eq, Hash)

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
} derive(Show, Eq)
