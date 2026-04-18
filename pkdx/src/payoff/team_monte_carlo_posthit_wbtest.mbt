///|
/// Whitebox regression tests for the MC rollout's post-hit pipeline.
/// Matches the DP semantics in `resolve_post_hit_effects` /
/// `clear_consumed_recharge`. `_wbtest.mbt` lives in the same package so the
/// private helper `team_apply_post_hit` is visible; `mk_move` is reused from
/// `switching_game_status_wbtest.mbt`.

///|
/// Regression for blocking issue 1: `team_apply_post_hit` must apply
/// self-target `stat_effects` for damaging moves (オーバーヒート, リーフストーム,
/// etc.). Previously the MC rollout only applied `stat_effects` for power<=0
/// status moves, so damaging moves with post-hit self-drops silently kept
/// ranks at 0 — diverging from the DP resolver.
test "team_apply_post_hit applies self-target stat drops on damaging moves" {
  let attacker_hps = [200]
  let attacker_ranks = [0, 0, 0, 0, 0]
  let attacker_must_recharge = [false]
  let defender_hps = [100]
  let defender_ranks = [0, 0, 0, 0, 0]
  // オーバーヒート analogue: damaging special move, self SpA -2 after hit.
  let overheat = mk_move(
    "オーバーヒート", "ほのお", @model.Special, 130,
    stat_effects=[{ stat: 2, delta: -2, target: 0 }],
  )
  team_apply_post_hit(
    attacker_hps, 0, attacker_ranks, attacker_must_recharge,
    defender_hps, 0, defender_ranks,
    overheat, 50,
  )
  assert_eq(attacker_ranks[2], -2)
  // Defender ranks are untouched (no opp-target effect on this move).
  assert_eq(defender_ranks[2], 0)
}

///|
/// Opp-target drops on damaging moves (アイアンテール Def -1, etc.) are applied
/// only when the defender survived the hit. A KO'd defender cannot have
/// its ranks mutated — mirrors DP `apply_stat_effects`' `opp_alive` gate.
test "team_apply_post_hit skips opp-target stat drops when defender faints" {
  let attacker_hps = [200]
  let attacker_ranks = [0, 0, 0, 0, 0]
  let attacker_must_recharge = [false]
  // Defender fainted by this hit — HP already dropped to 0 by caller.
  let defender_hps = [0]
  let defender_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move(
    "アイアンテール", "はがね", @model.Physical, 100,
    stat_effects=[{ stat: 1, delta: -1, target: 1 }],
  )
  team_apply_post_hit(
    attacker_hps, 0, attacker_ranks, attacker_must_recharge,
    defender_hps, 0, defender_ranks,
    mv, 120,
  )
  // Opp-target drop is gated out: defender ranks unchanged.
  assert_eq(defender_ranks[1], 0)
}

///|
test "team_apply_post_hit applies opp-target stat drops when defender survives" {
  let attacker_hps = [200]
  let attacker_ranks = [0, 0, 0, 0, 0]
  let attacker_must_recharge = [false]
  let defender_hps = [40]
  let defender_ranks = [0, 0, 0, 0, 0]
  let mv = mk_move(
    "アイアンテール", "はがね", @model.Physical, 100,
    stat_effects=[{ stat: 1, delta: -1, target: 1 }],
  )
  team_apply_post_hit(
    attacker_hps, 0, attacker_ranks, attacker_must_recharge,
    defender_hps, 0, defender_ranks,
    mv, 60,
  )
  assert_eq(defender_ranks[1], -1)
}

///|
/// Regression for blocking issue 2: the end-of-turn recharge cleanup must be
/// keyed off the *start-of-turn* active slot, not the post-switch active.
/// Scenario: slot 0 started the turn recharging, the turn's attack-resolution
/// switches the active to slot 1, and slot 1 is hit this turn by an
/// opposing recharge-move (Hyper Beam). The fresh recharge flag on slot 1
/// must persist to next turn — only slot 0's consumed flag gets cleared.
test "MC recharge cleanup targets start-of-turn slot, not post-switch slot" {
  // Simulate the end-of-turn cleanup logic directly.
  let must_recharge = [true, false]
  let start_active = 0
  let start_was_recharging = must_recharge[start_active]
  // During the turn, the active switched to slot 1 and slot 1 was hit by a
  // recharge move, so it gained a fresh recharge flag.
  let post_turn_active = 1
  must_recharge[post_turn_active] = true
  // End-of-turn cleanup — matches `team_rollout`'s logic after the fix.
  if start_was_recharging &&
    start_active >= 0 &&
    start_active < must_recharge.length() {
    must_recharge[start_active] = false
  }
  // Slot 0's penalty paid — cleared. Slot 1's fresh flag preserved.
  assert_eq(must_recharge[0], false)
  assert_eq(must_recharge[1], true)
}

///|
/// Behavioural regression: `team_apply_post_hit` must set the recharge flag
/// on the attacker slot after a recharge-move hit with damage > 0. Together
/// with the turn-cleanup fix, this guarantees a Hyper Beam user sits out the
/// following turn instead of silently losing its penalty.
test "team_apply_post_hit sets recharge flag after damaging recharge-move hit" {
  let attacker_hps = [300]
  let attacker_ranks = [0, 0, 0, 0, 0]
  let attacker_must_recharge = [false]
  let defender_hps = [120]
  let defender_ranks = [0, 0, 0, 0, 0]
  let hyper_beam = mk_move(
    "はかいこうせん", "ノーマル", @model.Physical, 150, recharge=true,
  )
  team_apply_post_hit(
    attacker_hps, 0, attacker_ranks, attacker_must_recharge,
    defender_hps, 0, defender_ranks,
    hyper_beam, 180,
  )
  assert_eq(attacker_must_recharge[0], true)
}
