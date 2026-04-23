///|
/// Whitebox tests for `avg_damage`. Covers:
///   - standard mean over the 16-roll array
///   - immune matchups short-circuit to 0
///   - disguise_blocked adds the fixed 1/8 max-HP chip to the mean
///
/// `avg_damage` is package-private, so the test lives next to it.

///|
fn mk_result(
  damages : FixedArray[Int],
  def_hp : Int,
  is_immune~ : Bool = false,
  disguise_blocked~ : Bool = false,
) -> @model.DamageCalcResult {
  let percents : FixedArray[Double] = FixedArray::make(16, 0.0)
  for i = 0; i < 16; i = i + 1 {
    percents[i] = damages[i].to_double() / def_hp.to_double() * 100.0
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
    disguise_blocked,
    hits_dealt: if disguise_blocked { 0 } else { 1 },
  }
}

///|
test "avg_damage: standard mean over 16 rolls" {
  // Uniform 48 damage → mean 48.
  let d : FixedArray[Int] = FixedArray::make(16, 48)
  let r = mk_result(d, 160)
  let avg = avg_damage(r)
  // Double equality on integers is safe here.
  inspect(avg, content="48")
}

///|
test "avg_damage: immune matchup returns 0" {
  let d : FixedArray[Int] = FixedArray::make(16, 0)
  let r = mk_result(d, 160, is_immune=true)
  inspect(avg_damage(r), content="0")
}

///|
test "avg_damage: disguise_blocked adds 1/8 defender HP chip to zero mean" {
  // engine returns damages=0 on the disguise-blocked initial hit; avg_damage
  // folds in the 1/8 max-HP chip so payoff sees the true cost of the turn.
  let d : FixedArray[Int] = FixedArray::make(16, 0)
  let r = mk_result(d, 160, disguise_blocked=true)
  // 160 / 8 = 20
  inspect(avg_damage(r), content="20")
}

///|
test "avg_damage: disguise_blocked with fractional HP keeps double precision" {
  // HP=163 → 163/8 = 20.375. Verifies the chip is a Double divide, not int.
  let d : FixedArray[Int] = FixedArray::make(16, 0)
  let r = mk_result(d, 163, disguise_blocked=true)
  inspect(avg_damage(r), content="20.375")
}
