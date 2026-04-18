# 010_move_meta_posthit — payoff 層の post-hit 副次効果 (相手ランクダウン・自己
# ランクダウン・反動・自爆・反動硬直) に必要なメタデータを move_meta に追加する。
#
# 追加カラム:
#   recoil_num   — 反動ダメージ分子 (0 = 反動なし)
#   recoil_den   — 反動ダメージ分母 (既定 1)
#   self_ko      — 1 = 使用後に攻撃者 HP が 0 (じばく・だいばくはつ)
#   recharge     — 1 = 次ターン行動不可 (はかいこうせん・ギガインパクト等)
#
# stat_effects_json のスキーマを 3 要素 [[stat, delta, target]] に拡張し、
# target=0 (自分) / target=1 (相手) を区別する。旧 2 要素 [[stat, delta]] は
# 下流のパーサが `target=0` 扱いで受理するため、この patch 以前のデータは
# 変更不要 (ここでは既存 006 のエントリも含め再 upsert する)。
#
# 冪等性: ALTER TABLE は既に列があるとエラーになるので pragma で検査。
# データは INSERT OR REPLACE なので複数回実行しても結果は不変。

require 'json'

existing_cols = db.execute('PRAGMA table_info(move_meta)').map { |r| r[1] }

unless existing_cols.include?('recoil_num')
  db.execute('ALTER TABLE move_meta ADD COLUMN recoil_num INTEGER NOT NULL DEFAULT 0')
end

unless existing_cols.include?('recoil_den')
  db.execute('ALTER TABLE move_meta ADD COLUMN recoil_den INTEGER NOT NULL DEFAULT 1')
end

unless existing_cols.include?('self_ko')
  db.execute('ALTER TABLE move_meta ADD COLUMN self_ko INTEGER NOT NULL DEFAULT 0')
end

unless existing_cols.include?('recharge')
  db.execute('ALTER TABLE move_meta ADD COLUMN recharge INTEGER NOT NULL DEFAULT 0')
end

data = JSON.parse(File.read(File.join(patch_dir, 'data.json')))

inserted = 0
updated = 0

data.each do |entry|
  move_name = entry['name']
  priority = entry['priority'] || 0
  effects = entry['stat_effects'] || []
  recoil_num = entry['recoil_num'] || 0
  recoil_den = entry['recoil_den'] || 1
  self_ko = entry['self_ko'] ? 1 : 0
  recharge = entry['recharge'] ? 1 : 0
  ailment_ja = entry['ailment_ja'] || ''
  ailment_chance = entry['ailment_chance'] || 100

  existing = db.get_first_value('SELECT 1 FROM move_meta WHERE name_ja = ?', [move_name])
  if existing
    db.execute(
      'UPDATE move_meta SET priority = ?, stat_effects_json = ?, ailment_ja = ?, ailment_chance = ?, recoil_num = ?, recoil_den = ?, self_ko = ?, recharge = ? WHERE name_ja = ?',
      [priority, JSON.generate(effects), ailment_ja, ailment_chance, recoil_num, recoil_den, self_ko, recharge, move_name]
    )
    updated += 1
  else
    db.execute(
      'INSERT INTO move_meta (name_ja, priority, stat_effects_json, ailment_ja, ailment_chance, recoil_num, recoil_den, self_ko, recharge) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [move_name, priority, JSON.generate(effects), ailment_ja, ailment_chance, recoil_num, recoil_den, self_ko, recharge]
    )
    inserted += 1
  end
end

puts "    post-hit columns added; #{updated} updated, #{inserted} inserted"
