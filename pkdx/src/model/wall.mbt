///|
/// Reflect / Light Screen / Aurora Veil on the defender side.
/// The damage multiplier (1/2 in singles, 2/3 in doubles) is applied in the
/// engine's final-mod chain, after ability/item final modifiers. Critical
/// hits, screen-piercing moves (`screen_pierce`), and bypass abilities
/// (`すりぬけ` / `かたやぶり` / `ターボブレイズ` / `テラボルテージ`) skip the
/// reduction independently.
pub(all) enum Wall {
  NoWall
  Reflect
  LightScreen
  AuroraVeil
} derive(Show, Eq)

///|
/// CLI parser. Accepts empty string or a handful of canonical spellings.
/// Unknown values return NoWall (callers check before propagating to
/// CacheKeyInput if strict validation is needed).
pub fn wall_from_str(s : String) -> Wall {
  match s {
    "" | "none" | "no-wall" => NoWall
    "reflect" | "リフレクター" => Reflect
    "light-screen" | "light_screen" | "ひかりのかべ" => LightScreen
    "aurora-veil" | "aurora_veil" | "オーロラベール" => AuroraVeil
    _ => NoWall
  }
}
