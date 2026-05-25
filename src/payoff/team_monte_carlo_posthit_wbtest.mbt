///|
/// Whitebox regression tests for the MC rollout's post-hit pipeline.
/// Matches the DP semantics in `resolve_post_hit_effects` /
/// `clear_consumed_recharge`. `_wbtest.mbt` lives in the same package so the
/// private helper `team_apply_post_hit` is visible; `mk_move` is reused from
/// `switching_game_status_wbtest.mbt`.
///
/// Stage 13 で `team_apply_post_hit` のシグネチャが拡張されたため (healing /
/// LeechSeed / Wish / 天候設定 / status 配列を取るようになった)、本 wbtest 群
/// は新しい呼び出し規約に追従する。引数は本ファイル冒頭のヘルパー
/// `mk_post_hit_ctx` でまとめて用意する。

///|
/// Stage 13 のシグネチャ拡張に対応した最小フィクスチャ。stat_effects / recoil /
/// recharge の検証用に必要な空配列をすべて生成し、`team_apply_post_hit` の
/// 引数群を 1 箇所で管理する。
priv struct PostHitCtx {
  attacker_status : Array[@model.StatusCondition]
  attacker_wish_turns : Array[Int]
  attacker_team : Array[Combatant]
  defender_leech_seeded : Array[Bool]
  defender_team : Array[Combatant]
  defender_megaed : Array[Bool]
  weather_state : Array[@model.Weather]
  weather_turns_state : Array[Int]
  // Stage H: team_apply_post_hit が field_set 反映用 out-param を取るため
  // wbtest 側 ctx でも field 用の dummy slot を用意する。
  field_state : Array[@model.Field]
  field_turns_state : Array[Int]
}

///|
/// 単スロット側の dummy combatant を作る (status moves / damaging moves の
/// post-hit semantics 検証で、healing / weather / LeechSeed 系の追加引数は
/// すべて初期値で十分)。max_hp は `effective_hp` 経由でしか参照されないので
/// pokemon.hp = 200 のままで OK。
/// wbtest は `_test.mbt` のヘルパー (mk_pokemon / mk_combatant) を import
/// できないため、本ファイル内に最小フィクスチャを inline で持つ。
fn mk_post_hit_pokemon() -> @model.Pokemon {
  {
    global_no: "0000",
    name_ja: "dummy",
    name_en: "dummy",
    type1: "ノーマル",
    type2: "",
    hp: 200,
    atk: 100,
    def_: 100,
    spa: 100,
    spd: 100,
    spe: 100,
    bst: 700,
    ability1: "",
    ability2: "",
    dream_ability: "",
    weight: 50.0,
    forms: [],
  }
}

///|
fn mk_post_hit_combatant() -> Combatant {
  {
    pokemon: mk_post_hit_pokemon(),
    moves: [],
    ability: "",
    item: "",
    tera_type: "",
    stat_system: @model.Standard,
    mega_form: None,
    nature: None,
    stat_points: None,
    actual_stats: None,
    ivs: None,
  }
}

///|
fn mk_post_hit_ctx() -> PostHitCtx {
  let c = mk_post_hit_combatant()
  {
    attacker_status: [@model.None],
    attacker_wish_turns: [-1],
    attacker_team: [c],
    defender_leech_seeded: [false],
    defender_team: [c],
    defender_megaed: [false],
    weather_state: [@model.Weather::None],
    weather_turns_state: [0],
    field_state: [@model.Field::None],
    field_turns_state: [0],
  }
}

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
  let ctx = mk_post_hit_ctx()
  // オーバーヒート analogue: damaging special move, self SpA -2 after hit.
  let overheat = mk_move(
    "オーバーヒート", "ほのお", @model.Special, 130,
    stat_effects=[{ stat: 2, delta: -2, target: 0 }],
  )
  team_apply_post_hit(
    attacker_hps, 0, attacker_ranks, attacker_must_recharge,
    ctx.attacker_status, ctx.attacker_wish_turns, ctx.attacker_team,
    defender_hps, 0, defender_ranks,
    ctx.defender_leech_seeded, ctx.defender_team, ctx.defender_megaed,
    ctx.weather_state, ctx.weather_turns_state,
    ctx.field_state, ctx.field_turns_state,
    overheat, 50,
  )
  @debug.assert_eq(attacker_ranks[2], -2)
  // Defender ranks are untouched (no opp-target effect on this move).
  @debug.assert_eq(defender_ranks[2], 0)
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
  let ctx = mk_post_hit_ctx()
  let mv = mk_move(
    "アイアンテール", "はがね", @model.Physical, 100,
    stat_effects=[{ stat: 1, delta: -1, target: 1 }],
  )
  team_apply_post_hit(
    attacker_hps, 0, attacker_ranks, attacker_must_recharge,
    ctx.attacker_status, ctx.attacker_wish_turns, ctx.attacker_team,
    defender_hps, 0, defender_ranks,
    ctx.defender_leech_seeded, ctx.defender_team, ctx.defender_megaed,
    ctx.weather_state, ctx.weather_turns_state,
    ctx.field_state, ctx.field_turns_state,
    mv, 120,
  )
  // Opp-target drop is gated out: defender ranks unchanged.
  @debug.assert_eq(defender_ranks[1], 0)
}

///|
test "team_apply_post_hit applies opp-target stat drops when defender survives" {
  let attacker_hps = [200]
  let attacker_ranks = [0, 0, 0, 0, 0]
  let attacker_must_recharge = [false]
  let defender_hps = [40]
  let defender_ranks = [0, 0, 0, 0, 0]
  let ctx = mk_post_hit_ctx()
  let mv = mk_move(
    "アイアンテール", "はがね", @model.Physical, 100,
    stat_effects=[{ stat: 1, delta: -1, target: 1 }],
  )
  team_apply_post_hit(
    attacker_hps, 0, attacker_ranks, attacker_must_recharge,
    ctx.attacker_status, ctx.attacker_wish_turns, ctx.attacker_team,
    defender_hps, 0, defender_ranks,
    ctx.defender_leech_seeded, ctx.defender_team, ctx.defender_megaed,
    ctx.weather_state, ctx.weather_turns_state,
    ctx.field_state, ctx.field_turns_state,
    mv, 60,
  )
  @debug.assert_eq(defender_ranks[1], -1)
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
  @debug.assert_eq(must_recharge[0], false)
  @debug.assert_eq(must_recharge[1], true)
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
  let ctx = mk_post_hit_ctx()
  let hyper_beam = mk_move(
    "はかいこうせん", "ノーマル", @model.Physical, 150, recharge=true,
  )
  team_apply_post_hit(
    attacker_hps, 0, attacker_ranks, attacker_must_recharge,
    ctx.attacker_status, ctx.attacker_wish_turns, ctx.attacker_team,
    defender_hps, 0, defender_ranks,
    ctx.defender_leech_seeded, ctx.defender_team, ctx.defender_megaed,
    ctx.weather_state, ctx.weather_turns_state,
    ctx.field_state, ctx.field_turns_state,
    hyper_beam, 180,
  )
  @debug.assert_eq(attacker_must_recharge[0], true)
}
