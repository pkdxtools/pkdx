///|
pub(all) struct DamageCalcInput {
  attacker : Pokemon
  defender : Pokemon
  move_ : Move
  atk_ability : String
  def_ability : String
  atk_item : String
  def_item : String
  weather : Weather
  field : Field
  tera_type : String
  critical : Bool
  // None = 攻撃stat特化相当 (+10% on offensive stat, legacy default).
  // Some(n) = n の性格補正に従う (物理技なら Atk、特殊技なら SpA、ボディプレスなら Def に対する
  // up/down を引く)。
  atk_nature : Nature?
  // None = 無補正 (legacy default)。Some(n) = n に従う。
  def_nature : Nature?
  atk_stat_override : Int
  def_stat_override : Int
  def_hp_override : Int
  atk_rank : Int
  def_rank : Int
  fainted_count : Int
  is_double : Bool
  stat_system : StatSystem
  // --- rev2 additions (defaults preserve legacy behavior) ---
  // 壁。既定 NoWall は従来挙動。
  wall : Wall
  // 技固有の screen 貫通 (かわらわり等)。ability 由来の貫通 (すりぬけ/
  // かたやぶり/ターボブレイズ/テラボルテージ) は engine 内で別経路検出。
  screen_pierce : Bool
  // 状態異常。たたりめの威力倍化判定に参照。BadPoison(n)/Sleep(n) のような
  // カウンタは無視し「None 以外か」だけで判定する。
  atk_status_condition : StatusCondition
  def_status_condition : StatusCondition
  // つけあがる / アシストパワー用。6 stat × 最大 6 = 36 まで物理的には伸び
  // うるが実戦で登場する範囲は 0-18 程度。
  atk_rank_up_count : Int
  def_rank_up_count : Int
  // やけっぱち: 自身 HP 比を整数 num/den で持つ (den > 0 前提)。2/2 = 満タン。
  atk_hp_num : Int
  atk_hp_den : Int
  // はたきおとす: 防御側が「剥がせる」持ち物を持っているか。既定 false で
  // 保守側 (= 倍率を掛けない)。
  def_item_removable : Bool
  // 連続技解決モード。Auto は Plan 通り中央値 3 で計算、Fixed(n) で明示。
  multi_hit_mode : MultiHit
  // ばけのかわ初撃フラグ。true のとき engine は damages=0 / disguise_blocked
  // を立てて早期 return する。
  disguise_active : Bool
} derive(Show)
