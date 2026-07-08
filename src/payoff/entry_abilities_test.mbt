///|
/// Black-box tests for `apply_intimidate_on_entry`. Rank arrays follow the
/// payoff-layer convention `[A, B, C, D, S]` (index 0 = Attack, 4 = Speed)
/// and stay clamped inside `[-2, +2]` via `clamp_rank`. Each test covers one
/// row of the target-ability dispatch table: plain drop, clamp at the floor,
/// ばんけん / ミラーアーマー / びびり / あまのじゃく redirections, the eight
/// blocking abilities, the non-いかく entrant no-op, and the mutual-いかく
/// case where the caller invokes the helper once per entrant.

///|
fn zero_ranks() -> Array[Int] {
  [0, 0, 0, 0, 0]
}

///|
test "intimidate_plain_target_drops_attack_by_one" {
  let target = zero_ranks()
  let entrant = zero_ranks()
  apply_intimidate_on_entry("いかく", "もうか", target, entrant)
  @debug.assert_eq(target, [-1, 0, 0, 0, 0])
  @debug.assert_eq(entrant, [0, 0, 0, 0, 0])
}

///|
test "intimidate_clamps_at_minus_two" {
  let target = [-2, 0, 0, 0, 0]
  let entrant = zero_ranks()
  apply_intimidate_on_entry("いかく", "", target, entrant)
  @debug.assert_eq(target, [-2, 0, 0, 0, 0])
}

///|
/// ばんけん (Guard Dog) raises Attack instead of dropping it.
test "intimidate_guard_dog_raises_attack" {
  let target = zero_ranks()
  let entrant = zero_ranks()
  apply_intimidate_on_entry("いかく", "ばんけん", target, entrant)
  @debug.assert_eq(target, [1, 0, 0, 0, 0])
  @debug.assert_eq(entrant, [0, 0, 0, 0, 0])
}

///|
/// ミラーアーマー (Mirror Armor) bounces the drop back onto the entrant;
/// the target itself stays untouched. No re-reflection: an Intimidate user
/// cannot simultaneously hold a blocking ability, so a plain -1 suffices.
test "intimidate_mirror_armor_bounces_onto_entrant" {
  let target = zero_ranks()
  let entrant = zero_ranks()
  apply_intimidate_on_entry(
    "いかく", "ミラーアーマー", target, entrant,
  )
  @debug.assert_eq(target, [0, 0, 0, 0, 0])
  @debug.assert_eq(entrant, [-1, 0, 0, 0, 0])
}

///|
/// びびり (Rattled) still takes the Attack drop but gains +1 Speed —
/// Gen8+ lets Intimidate trigger Rattled.
test "intimidate_rattled_drops_attack_and_raises_speed" {
  let target = zero_ranks()
  let entrant = zero_ranks()
  apply_intimidate_on_entry("いかく", "びびり", target, entrant)
  @debug.assert_eq(target, [-1, 0, 0, 0, 1])
  @debug.assert_eq(entrant, [0, 0, 0, 0, 0])
}

///|
/// あまのじゃく (Contrary) inverts the drop into +1 Attack.
test "intimidate_contrary_raises_attack" {
  let target = zero_ranks()
  let entrant = zero_ranks()
  apply_intimidate_on_entry("いかく", "あまのじゃく", target, entrant)
  @debug.assert_eq(target, [1, 0, 0, 0, 0])
  @debug.assert_eq(entrant, [0, 0, 0, 0, 0])
}

///|
/// All eight blocking abilities leave both rank arrays untouched.
test "intimidate_blocking_abilities_are_no_ops" {
  let blockers = [
    "どんかん", "マイペース", "せいしんりょく", "きもったま",
    "クリアボディ", "かいりきバサミ", "しろいけむり", "メタルプロテクト",
  ]
  for ability in blockers {
    let target = zero_ranks()
    let entrant = zero_ranks()
    apply_intimidate_on_entry("いかく", ability, target, entrant)
    @debug.assert_eq(target, [0, 0, 0, 0, 0])
    @debug.assert_eq(entrant, [0, 0, 0, 0, 0])
  }
}

///|
/// A non-いかく entrant triggers nothing regardless of the target's ability.
test "non_intimidate_entrant_is_a_no_op" {
  let target = zero_ranks()
  let entrant = zero_ranks()
  apply_intimidate_on_entry("もうか", "びびり", target, entrant)
  @debug.assert_eq(target, [0, 0, 0, 0, 0])
  @debug.assert_eq(entrant, [0, 0, 0, 0, 0])
  apply_intimidate_on_entry("", "", target, entrant)
  @debug.assert_eq(target, [0, 0, 0, 0, 0])
  @debug.assert_eq(entrant, [0, 0, 0, 0, 0])
}

///|
/// Two Intimidate users entering simultaneously: the caller invokes the
/// helper once per entrant, and both sides end at A-1 (いかく does not block
/// an incoming Intimidate).
test "mutual_intimidate_drops_both_attacks" {
  let a_ranks = zero_ranks()
  let b_ranks = zero_ranks()
  apply_intimidate_on_entry("いかく", "いかく", b_ranks, a_ranks)
  apply_intimidate_on_entry("いかく", "いかく", a_ranks, b_ranks)
  @debug.assert_eq(a_ranks, [-1, 0, 0, 0, 0])
  @debug.assert_eq(b_ranks, [-1, 0, 0, 0, 0])
}
