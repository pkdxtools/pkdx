///|
/// Whitebox tests for `avg_damage`. Covers:
///   - standard mean over the 16-roll array
///   - immune matchups short-circuit to 0
///
/// payoff レイヤは build_input_with_ranks で disguise_active=false 固定なので
/// disguise_blocked 経路はそもそも発生しない。仮に立っても engine が chip を
/// total_damages に加算済みなので avg_damage は通常パスでそのまま正しい値を
/// 返す。
///
/// `avg_damage` is package-private, so the test lives next to it.

///|
fn mk_result(
  damages : FixedArray[Int],
  def_hp : Int,
  is_immune~ : Bool = false,
) -> @model.DamageCalcResult {
  let percents : FixedArray[Double] = FixedArray::make(16, 0.0)
  for i = 0; i < 16; i = i + 1 {
    percents[i] = damages[i].to_double() / def_hp.to_double() * 100.0
  }
  // Synthesize a single chance-node entry so `expected_damage_variants`
  // (called by the new `avg_damage` delegate) sees the same 16-roll table.
  let single_variant : @model.DamageVariant = {
    probability: 1.0,
    hits: [],
    hits_count: 1,
    total_damages: damages,
    min: damages[0],
    max: damages[15],
    ko_text: "",
  }
  {
    damages,
    percents,
    min_damage: damages[0],
    max_damage: damages[15],
    min_percent: percents[0],
    max_percent: percents[15],
    ko_text: "",
    defender_hp: def_hp,
    is_immune,
    disguise_blocked: false,
    disguise_chip: 0,
    hits_dealt: 1,
    variants: [single_variant],
  }
}

///|
test "avg_damage: standard mean over 16 rolls" {
  // Uniform 48 damage → mean 48.
  let d : FixedArray[Int] = FixedArray::make(16, 48)
  let r = mk_result(d, 160)
  let avg = avg_damage(r)
  // Double equality on integers is safe here.
  @debug.debug_inspect(avg, content="48")
}

///|
test "avg_damage: immune matchup returns 0" {
  let d : FixedArray[Int] = FixedArray::make(16, 0)
  let r = mk_result(d, 160, is_immune=true)
  @debug.debug_inspect(avg_damage(r), content="0")
}
