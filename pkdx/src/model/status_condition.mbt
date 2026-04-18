///|
/// Runtime status condition carried by each team slot. `None` is the default
/// (no condition). `BadPoison(n)` counts how many end-of-turn ticks have
/// already elapsed: the next tick deals `min(n + 1, 15) / 16 * max_hp`.
/// `Sleep(n)` is the number of remaining unable-to-act turns — the switching-
/// game DP decrements it each turn and flips back to `None` when it reaches
/// zero.
///
/// Counter semantics on switch:
/// - `BadPoison(n)` resets to `BadPoison(0)` (fresh 1/16 on the next tick).
/// - `Sleep(n)` persists (switched-out sleeper keeps counting elsewhere).
/// - `Paralyze` / `Burn` / `Poison` are stateless flags, unchanged by switch.
pub(all) enum StatusCondition {
  None
  Paralyze
  Burn
  Poison
  BadPoison(Int)
  Sleep(Int)
  // あくび専用: ねむり予告マーカー。N ターン後の EOT に Sleep(2) へ遷移する。
  // 初期値 `Drowsy(1)`: 付与ターンの EOT で `Drowsy(0)` に、次の EOT で
  // `Sleep(2)` に変わる (合計 1 ターン猶予 = 本家の遅延ねむり)。交代すると
  // `None` にリセットされる。
  Drowsy(Int)
} derive(Show, Eq, Hash)

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
} derive(Show, Eq, Hash)

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
/// lands. `Sleep` starts with 2 remaining turns (fixed in MVP; gen-accurate
/// 1–3 randomisation is a future extension). `BadPoison` starts at counter 0,
/// so the first end-of-turn tick deals `1/16 * max_hp`.
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
pub fn immune_to_status(kind : StatusKind, type1 : String, type2 : String) -> Bool {
  match kind {
    ParalyzeKind => type1 == "でんき" || type2 == "でんき"
    BurnKind => type1 == "ほのお" || type2 == "ほのお"
    PoisonKind | BadPoisonKind =>
      type1 == "はがね" || type2 == "はがね" || type1 == "どく" || type2 == "どく"
    SleepKind => false
    // あくびはタイプ免疫なし。ねむり粉系 (ねむりごな等) と異なり草タイプにも
    // 効く。特性免疫 (ふみん/やるき/スイートベール) は別タスクで対応。
    DrowsyKind => false
  }
}
