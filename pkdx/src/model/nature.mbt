///|
pub(all) enum StatIndex {
  HP
  Atk
  Def
  SpA
  SpD
  Spe
} derive(Show, Eq)

///|
pub(all) struct Nature {
  name_ja : String
  name_en : String
  up : StatIndex?
  down : StatIndex?
} derive(Show, Eq)

///|
pub fn all_natures() -> Array[Nature] {
  [
    // Neutral (5)
    { name_ja: "がんばりや", name_en: "Hardy", up: None, down: None },
    { name_ja: "すなお", name_en: "Docile", up: None, down: None },
    { name_ja: "てれや", name_en: "Bashful", up: None, down: None },
    { name_ja: "きまぐれ", name_en: "Quirky", up: None, down: None },
    { name_ja: "まじめ", name_en: "Serious", up: None, down: None },
    // Atk+ (4)
    { name_ja: "さみしがり", name_en: "Lonely", up: Some(Atk), down: Some(Def) },
    {
      name_ja: "いじっぱり",
      name_en: "Adamant",
      up: Some(Atk),
      down: Some(SpA),
    },
    {
      name_ja: "やんちゃ",
      name_en: "Naughty",
      up: Some(Atk),
      down: Some(SpD),
    },
    { name_ja: "ゆうかん", name_en: "Brave", up: Some(Atk), down: Some(Spe) },
    // Def+ (4)
    { name_ja: "ずぶとい", name_en: "Bold", up: Some(Def), down: Some(Atk) },
    {
      name_ja: "わ���ぱく",
      name_en: "Impish",
      up: Some(Def),
      down: Some(SpA),
    },
    { name_ja: "のうてんき", name_en: "Lax", up: Some(Def), down: Some(SpD) },
    {
      name_ja: "のんき",
      name_en: "Relaxed",
      up: Some(Def),
      down: Some(Spe),
    },
    // SpA+ (4)
    {
      name_ja: "ひかえめ",
      name_en: "Modest",
      up: Some(SpA),
      down: Some(Atk),
    },
    { name_ja: "おっとり", name_en: "Mild", up: Some(SpA), down: Some(Def) },
    { name_ja: "うっかりや", name_en: "Rash", up: Some(SpA), down: Some(SpD) },
    { name_ja: "れいせい", name_en: "Quiet", up: Some(SpA), down: Some(Spe) },
    // SpD+ (4)
    { name_ja: "おだやか", name_en: "Calm", up: Some(SpD), down: Some(Atk) },
    {
      name_ja: "おとなしい",
      name_en: "Gentle",
      up: Some(SpD),
      down: Some(Def),
    },
    {
      name_ja: "しんちょう",
      name_en: "Careful",
      up: Some(SpD),
      down: Some(SpA),
    },
    { name_ja: "なまいき", name_en: "Sassy", up: Some(SpD), down: Some(Spe) },
    // Spe+ (4)
    {
      name_ja: "おくびょう",
      name_en: "Timid",
      up: Some(Spe),
      down: Some(Atk),
    },
    { name_ja: "せっかち", name_en: "Hasty", up: Some(Spe), down: Some(Def) },
    { name_ja: "ようき", name_en: "Jolly", up: Some(Spe), down: Some(SpA) },
    { name_ja: "むじゃき", name_en: "Naive", up: Some(Spe), down: Some(SpD) },
  ]
}

///|
pub fn nature_from_ja(name : String) -> Nature? {
  let natures = all_natures()
  for i = 0; i < natures.length(); i = i + 1 {
    if natures[i].name_ja == name {
      return Some(natures[i])
    }
  }
  None
}

///|
/// Returns (numerator, denominator) for nature modifier on a given stat.
/// (11, 10) for boosted, (9, 10) for reduced, (1, 1) for neutral.
pub fn nature_mult_int(nature : Nature, stat : StatIndex) -> (Int, Int) {
  match (nature.up, nature.down) {
    (Some(up), Some(down)) =>
      if stat == up {
        (11, 10)
      } else if stat == down {
        (9, 10)
      } else {
        (1, 1)
      }
    _ => (1, 1)
  }
}

///|
pub fn stat_index_from_str(s : String) -> StatIndex? {
  match s {
    "hp" => Some(HP)
    "atk" => Some(Atk)
    "def" => Some(Def)
    "spa" => Some(SpA)
    "spd" => Some(SpD)
    "spe" => Some(Spe)
    _ => None
  }
}
