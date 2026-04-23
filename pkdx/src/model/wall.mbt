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
