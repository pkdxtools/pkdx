# 006_move_meta — payoff (SwitchingGame / MonteCarloSim) が参照する
# 技メタ (priority, stat_effects) を pokedex.db に載せる
#
# apply.rb から eval される。db (SQLite3::Database) と patch_dir が利用可能。
#
# `local_waza` に priority カラムが無いため、正規化済みメタを独立テーブル
# `move_meta` に格納する。日本語技名 (wl.name) を PK として、pkdx 側が
# `query_move_meta(db, names)` で一括取得できるよう設計されている。
#
# 追加 / 更新 / 削除はすべて data.json を編集するだけで完結し、コード変更は
# 不要（payoff 層のフォールバック curated table が保険として残る）。

require 'json'

data = JSON.parse(File.read(File.join(patch_dir, 'data.json')))

db.execute(<<~SQL)
  CREATE TABLE IF NOT EXISTS move_meta (
    name_ja TEXT PRIMARY KEY,
    priority INTEGER NOT NULL DEFAULT 0,
    stat_effects_json TEXT NOT NULL DEFAULT '[]'
  )
SQL

data.each do |entry|
  name = entry['name']
  priority = entry['priority'] || 0
  effects = entry['stat_effects'] || []
  db.execute(
    'INSERT OR REPLACE INTO move_meta (name_ja, priority, stat_effects_json) VALUES (?, ?, ?)',
    [name, priority, JSON.generate(effects)]
  )
end

puts "    Inserted/replaced #{data.size} move_meta entries"
