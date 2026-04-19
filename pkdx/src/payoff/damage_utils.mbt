///|
/// Shared damage-calculation helpers used by the payoff layer
/// (`switching_game`, `team_monte_carlo`, `monte_carlo`). Hosts the 16-roll
/// mean-damage reduction and the canonical `DamageCalcInput` builder.

///|
/// Mean damage over the 16-roll table. Zero for immune matchups.
fn avg_damage(r : @model.DamageCalcResult) -> Double {
  if r.is_immune {
    return 0.0
  }
  let mut s = 0
  for i in 0..<16 {
    s += r.damages[i]
  }
  s.to_double() / 16.0
}

///|
/// Effective Lv50 max-HP realized from a combatant's base HP plus its
/// `stat_system`. Payoff helpers that need a denominator for damage ratios
/// (e.g. `pkdx nash graph` team-form fast path) go through here instead of
/// reading `c.pokemon.hp` directly, which carries the base stat.
///
/// `actual_stats` が与えられていればユーザ指定の HP 実数値を優先する。
/// そうでなければ stat_system のデフォルト (Champions: SP=32, Standard:
/// EV252/IV31) で算出する。damage engine の def_hp_override と整合するため、
/// ratio 計算で使う分母をここで揃えておく。
fn effective_hp(c : Combatant) -> Int {
  match c.actual_stats {
    Some(arr) => arr[0]
    None =>
      match c.stat_system {
        @model.Champions => @damage.calc_stat_champions(c.pokemon.hp, is_hp=true)
        @model.Standard => @damage.calc_stat(c.pokemon.hp, is_hp=true)
      }
  }
}

///|
/// `actual_stats` は `[H, A, B, C, D, Spe]` 順の HABCDS 配列。engine.mbt の
/// `is_body_press` / `is_physical` 分岐と対応する stat index を返す:
///   - ボディプレス → 攻撃側 Def (index 2)
///   - 物理技       → 攻撃側 Atk (1)、防御側 Def (2)
///   - 特殊技       → 攻撃側 SpA (3)、防御側 SpD (4)
fn attack_defense_stat_indices(mv : @model.Move) -> (Int, Int) {
  let is_physical = mv.category == @model.Physical
  let is_body_press = mv.name == "ボディプレス"
  let atk_idx = if is_body_press {
    2
  } else if is_physical {
    1
  } else {
    3
  }
  let def_idx = if is_physical { 2 } else { 4 }
  (atk_idx, def_idx)
}

///|
/// Build a `DamageCalcInput` with the combatants' abilities/items/tera, the
/// given attacker/defender ranks, and no weather/field. Used as the canonical
/// reference input for payoff computation.
///
/// Combatant が `nature` / `actual_stats` を保持しているとき、対応する
/// engine フィールドへ流し込む。欠損時は engine の legacy default
/// (攻撃側 max SP+性格 / 防御側 無投資) にフォールバックする。
fn build_input_with_ranks(
  atk : Combatant,
  dfn : Combatant,
  mv : @model.Move,
  atk_rank : Int,
  def_rank : Int,
) -> @model.DamageCalcInput {
  let (atk_idx, def_idx) = attack_defense_stat_indices(mv)
  let atk_stat_override = match atk.actual_stats {
    Some(arr) => arr[atk_idx]
    None => 0
  }
  let def_stat_override = match dfn.actual_stats {
    Some(arr) => arr[def_idx]
    None => 0
  }
  let def_hp_override = match dfn.actual_stats {
    Some(arr) => arr[0]
    None => 0
  }
  {
    attacker: atk.pokemon,
    defender: dfn.pokemon,
    move_: mv,
    atk_ability: atk.ability,
    def_ability: dfn.ability,
    atk_item: atk.item,
    def_item: dfn.item,
    weather: @model.Weather::None,
    field: @model.Field::None,
    tera_type: atk.tera_type,
    critical: false,
    atk_nature: atk.nature,
    def_nature: dfn.nature,
    atk_stat_override,
    def_stat_override,
    def_hp_override,
    atk_rank,
    def_rank,
    fainted_count: 0,
    is_double: false,
    stat_system: atk.stat_system,
  }
}
