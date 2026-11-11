// `normalize_status_effect_chance` (DB 経路の status_effect 正規化) の単体テスト。
//
// move_meta.ailment_chance は pure status 技 (変化) では命中率と同値 (おにび 85 / 命中 85)。
// 命中は move.accuracy で既に抽選されるので、DB 由来の status_effect は確率 100 に正規化して
// 二重抽選 (命中 × 確率) を防ぐ。ダメージ技の二次効果は ailment_chance が追加効果の確率なので
// そのまま残る。

test "status normalize: a pure status move's chance becomes 100 (accuracy carries the roll)" {
  @debug.assert_eq(
    @db.normalize_status_effect_chance(
      @model.Status,
      Some((@model.BurnKind, 85)),
    ),
    Some((@model.BurnKind, 100)),
  )
  @debug.assert_eq(
    @db.normalize_status_effect_chance(
      @model.Status,
      Some((@model.PoisonKind, 90)),
    ),
    Some((@model.PoisonKind, 100)),
  )
}

test "status normalize: a damaging move's secondary chance is kept" {
  @debug.assert_eq(
    @db.normalize_status_effect_chance(
      @model.Physical,
      Some((@model.BurnKind, 10)),
    ),
    Some((@model.BurnKind, 10)),
  )
  @debug.assert_eq(
    @db.normalize_status_effect_chance(
      @model.Special,
      Some((@model.BadPoisonKind, 50)),
    ),
    Some((@model.BadPoisonKind, 50)),
  )
}

test "status normalize: no status_effect stays None" {
  @debug.assert_eq(
    @db.normalize_status_effect_chance(@model.Status, None),
    None,
  )
  @debug.assert_eq(
    @db.normalize_status_effect_chance(@model.Physical, None),
    None,
  )
}
