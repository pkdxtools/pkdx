///|
/// Runtime status condition carried by each team slot. `None` is the default
/// (no condition). `BadPoison(n)` counts how many end-of-turn ticks have
/// already elapsed: the next tick deals `min(n + 1, 15) / 16 * max_hp`.
/// `Sleep(n)` is the ねむり counter of a non-Rest sleep (ねむり技 / あくび).
/// Every move attempt by the sleeper decrements it (`per_side_attempt`):
/// - `n >= 2`: asleep for sure (Champions: "remain asleep on its first turn").
/// - `n == 1`: 1/3 wake up and act (subject to accuracy), 2/3 stay asleep
///   (Champions: "1-in-3 chance of being cured on its second turn").
/// - `n == 0`: wake up and act (subject to accuracy) — "cured on its third turn".
/// `RestSleep(n)` is the same counter for a sleep started by the move Rest.
/// It has no 1/3 check: asleep while `n >= 1`, wake and act at `n == 0`
/// (Champions: "has no chance of being cured until its third turn").
///
/// Counter semantics on switch:
/// - `BadPoison(n)` resets to `BadPoison(0)` (fresh 1/16 on the next tick).
/// - `Sleep(n)` / `RestSleep(n)` persist unchanged. The counter only moves on
///   a move attempt by the active sleeper, so a benched sleeper is frozen
///   (Showdown `slp` behaves the same; Champions text is silent on switching).
/// - `Paralyze` / `Burn` / `Poison` are stateless flags, unchanged by switch.
pub(all) enum StatusCondition {
  None
  Paralyze
  Burn
  Poison
  BadPoison(Int)
  Sleep(Int)
  // 技「ねむる」由来の眠り。カウンタの意味は Sleep と同じだが、2 ターン目の
  // 1/3 の目覚め抽選を持たない (Champions「ねむるは 3 ターン目まで回復しない」)。
  RestSleep(Int)
  // あくび専用: ねむり予告マーカー。N ターン後の EOT に Sleep(2) へ遷移する。
  // 初期値 `Drowsy(1)`: 付与ターンの EOT で `Drowsy(0)` に、次の EOT で
  // `Sleep(2)` に変わる (合計 1 ターン猶予 = 本家の遅延ねむり)。交代すると
  // `None` にリセットされる。
  Drowsy(Int)
} derive(Debug, Eq, Hash)

///|
pub extend StatusCondition with Debug::{to_repr}

///|
pub extend StatusCondition with Eq::{not_equal, equal}

///|
pub extend StatusCondition with Hash::{hash, hash_combine}

///|
/// Kind of status a move can inflict. Separate from `StatusCondition` because
/// moves declare "what they try to apply" as a kind (e.g. BadPoisonKind for
/// どくどく) while the actual condition the target ends up with carries
/// runtime counters (e.g. `BadPoison(0)`).
pub(all) enum StatusKind {
  ParalyzeKind
  BurnKind
  PoisonKind
  BadPoisonKind
  SleepKind
  // あくびが付与する予告状態。直接ねむりを与えず 1 ターン遅延させる。
  DrowsyKind
} derive(Debug, Eq, Hash)

///|
pub extend StatusKind with Debug::{to_repr}

///|
pub extend StatusKind with Eq::{not_equal, equal}

///|
pub extend StatusKind with Hash::{hash, hash_combine}

///|
/// Parse a Japanese status name into `StatusKind`. Accepts the canonical
/// pokedex ailment names used in move_meta patch data.
pub fn status_kind_from_jp(name : String) -> StatusKind? {
  match name {
    "まひ" => Some(ParalyzeKind)
    "やけど" => Some(BurnKind)
    "どく" => Some(PoisonKind)
    "もうどく" => Some(BadPoisonKind)
    "ねむり" => Some(SleepKind)
    "あくび" => Some(DrowsyKind)
    _ => None
  }
}

///|
/// Build the initial `StatusCondition` produced when a move of the given kind
/// lands. `Sleep` starts at counter 2 (Champions: the first move attempt after
/// falling asleep is a sure skip; see `StatusCondition`). `BadPoison` starts at
/// counter 0, so the first end-of-turn tick deals `1/16 * max_hp`.
pub fn inflict_status(kind : StatusKind) -> StatusCondition {
  match kind {
    ParalyzeKind => Paralyze
    BurnKind => Burn
    PoisonKind => Poison
    BadPoisonKind => BadPoison(0)
    SleepKind => Sleep(2)
    // あくび付与時は Drowsy(1)。最初の EOT で Drowsy(0)、次の EOT で Sleep(2)。
    DrowsyKind => Drowsy(1)
  }
}

///|
/// Return `true` if a Pokemon with types `(type1, type2)` cannot be inflicted
/// with `kind`. Ability-based immunity (じゅうなん, みずのベール, etc.) is
/// deferred to a separate pass; this helper only covers type immunity.
/// CLI parser that returns a ready-to-consume `StatusCondition` (not a
/// `StatusKind`). BadPoison starts with counter 0 and Sleep with 2 remaining
/// turns to match `inflict_status` semantics. Accepts both English and
/// Japanese canonical spellings; unknown input is `None`.
pub fn status_condition_from_cli_str(s : String) -> StatusCondition {
  match s {
    "" | "normal" | "none" => None
    "paralyze" | "paralysis" | "paralysed" | "まひ" => Paralyze
    "burn" | "burned" | "やけど" => Burn
    "poison" | "poisoned" | "どく" => Poison
    "badpoison" | "bad-poison" | "badly-poisoned" | "もうどく" =>
      BadPoison(0)
    "sleep" | "asleep" | "ねむり" => Sleep(2)
    "drowsy" | "あくび" => Drowsy(1)
    _ => None
  }
}

///|
pub fn immune_to_status(
  kind : StatusKind,
  type1 : String,
  type2 : String,
) -> Bool {
  match kind {
    ParalyzeKind => type1 == "でんき" || type2 == "でんき"
    BurnKind => type1 == "ほのお" || type2 == "ほのお"
    PoisonKind | BadPoisonKind =>
      type1 == "はがね" ||
      type2 == "はがね" ||
      type1 == "どく" ||
      type2 == "どく"
    SleepKind => false
    // あくびはタイプ免疫なし。ねむり粉系 (ねむりごな等) と異なり草タイプにも
    // 効く。特性免疫 (ふみん/やるき/スイートベール) は別タスクで対応。
    DrowsyKind => false
  }
}
