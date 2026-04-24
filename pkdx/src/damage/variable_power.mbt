///|
/// Move-specific power and type overrides extracted out of `engine.mbt`.
///
/// Two entry points:
///
/// - `resolve_move_type_override` — called **before** Skin ability / STAB
///   setup. Currently only Weather Ball rewrites (power, move_type). Skin
///   abilities see the new type and correctly decline to apply because the
///   move is no longer Normal.
///
/// - `resolve_variable_power` — called at the existing power-calculation slot
///   in `engine.mbt`. Picks up the move's base power after the type override
///   and returns the effective base power that subsequent modifiers
///   (Technician / items / type resist) operate on.

///|
/// Rewrite (power, move_type) for the handful of moves whose type depends on
/// runtime state rather than the move's declared type. Only Weather Ball
/// currently qualifies.
pub fn resolve_move_type_override(
  mv : @model.Move,
  input : @model.DamageCalcInput,
) -> (Int, String) {
  match mv.name {
    "ウェザーボール" =>
      match input.weather {
        @model.Weather::Sun => (100, "ほのお")
        @model.Weather::Rain => (100, "みず")
        @model.Weather::Sand => (100, "いわ")
        @model.Weather::Snow => (100, "こおり")
        _ => (mv.power, mv.type_)
      }
    _ => (mv.power, mv.type_)
  }
}

///|
/// Compute the base power after move-name-driven overrides. Both the existing
/// weight-ratio moves (けたぐり, くさむすび, ヘビーボンバー, ヒートスタンプ)
/// and おはかまいり are moved in here from `engine.mbt`; new moves added in
/// PR-B are:
/// - つけあがる: 20 + 20 × opponent's total stat raises
/// - アシストパワー: 20 + 20 × own raises, capped at 860
/// - やけっぱち: base × 2 when current HP ≤ max/2
/// - はたきおとす: base × 3/2 when the target carries a removable item
/// - たたりめ: base × 2 when the target is statused
/// - からげんき: base × 2 when the attacker itself is statused
///   (まひ / やけど / どく / もうどく のいずれか。ねむりは行動不能なので
///   対象外 — Gen9 本家挙動に合わせる。あくびは発症前なのでこれも対象外)
pub fn resolve_variable_power(
  base_power : Int,
  mv : @model.Move,
  input : @model.DamageCalcInput,
  dfn : @model.Pokemon,
  atk : @model.Pokemon,
  atk_ability : String,
  def_ability : String,
) -> Int {
  match mv.name {
    "おはかまいり" => {
      let count = if input.fainted_count > 100 {
        100
      } else {
        input.fainted_count
      }
      50 + count * 50
    }
    "けたぐり" | "くさむすび" => {
      let dw = effective_weight(dfn.weight, def_ability)
      weight_based_power(dw)
    }
    "ヘビーボンバー" | "ヒートスタンプ" => {
      let aw = effective_weight(atk.weight, atk_ability)
      let dw = effective_weight(dfn.weight, def_ability)
      weight_ratio_power(aw, dw)
    }
    "つけあがる" => 20 + 20 * input.def_rank_up_count
    "アシストパワー" => {
      let p = 20 + 20 * input.atk_rank_up_count
      if p > 860 {
        860
      } else {
        p
      }
    }
    "やけっぱち" =>
      // HP fraction num/den. 2x when num * 2 <= den (i.e. current HP ≤ half).
      if input.atk_hp_num * 2 <= input.atk_hp_den {
        base_power * 2
      } else {
        base_power
      }
    "はたきおとす" =>
      // 65 * 3 / 2 = 97 (integer truncation, matches Showdown Gen9).
      if input.def_item_removable {
        base_power * 3 / 2
      } else {
        base_power
      }
    "たたりめ" =>
      if input.def_status_condition != @model.StatusCondition::None {
        base_power * 2
      } else {
        base_power
      }
    "からげんき" =>
      // まひ / やけど / どく / もうどく のいずれかで 2x。ねむり・あくびは
      // 行動/発症前なので対象外 (本家挙動)。BadPoison(n) のカウンタは無視。
      match input.atk_status_condition {
        @model.StatusCondition::Paralyze
        | @model.StatusCondition::Burn
        | @model.StatusCondition::Poison
        | @model.StatusCondition::BadPoison(_) => base_power * 2
        _ => base_power
      }
    _ => base_power
  }
}
