# 002_champions_pokemon — Champions ポケモンデータを pokedex.db にパッチ
#
# apply.rb から eval される。db (SQLite3::Database) と patch_dir が利用可能。

require 'json'

data = JSON.parse(File.read(File.join(patch_dir, 'data.json')))
version = 'champions'

data.each do |entry|
  id         = entry['id']
  no         = entry['no']
  global_no  = entry['globalNo']
  form       = entry['form'].to_s == '' ? nil : entry['form']
  region     = entry['region'].to_s == '' ? nil : entry['region']
  mega_evo   = entry['mega_evolution'].to_s == '' ? nil : entry['mega_evolution']
  gigantamax = entry['gigantamax'].to_s == '' ? nil : entry['gigantamax']
  pokedex    = entry['pokedex']

  # 新メガの pokedex + pokedex_name 登録
  if entry['new_pokedex_entry']
    db.execute(
      'INSERT OR IGNORE INTO pokedex (id, globalNo, form, region, mega_evolution, gigantamax, height, weight) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [id, global_no, form, region, mega_evo, gigantamax, '-', '-']
    )
    [['jpn', entry['new_pokedex_name_jpn']], ['eng', entry['new_pokedex_name_eng']]].each do |lang, name|
      if name
        db.execute(
          'INSERT OR IGNORE INTO pokedex_name (id, globalNo, form, region, mega_evolution, gigantamax, language, name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [id, global_no, form, region, mega_evo, gigantamax, lang, name]
        )
      end
    end
  end

  # local_pokedex
  db.execute(
    'INSERT OR REPLACE INTO local_pokedex (id, no, globalNo, form, region, mega_evolution, gigantamax, version, pokedex) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [id, no, global_no, form, region, mega_evo, gigantamax, version, pokedex]
  )

  # local_pokedex_status
  db.execute(
    'INSERT OR REPLACE INTO local_pokedex_status (id, globalNo, form, region, mega_evolution, gigantamax, version, hp, attack, defense, special_attack, special_defense, speed) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [id, global_no, form, region, mega_evo, gigantamax, version,
     entry['hp'], entry['attack'], entry['defense'],
     entry['special_attack'], entry['special_defense'], entry['speed']]
  )

  # local_pokedex_type
  type2 = entry['type2'].to_s == '' ? nil : entry['type2']
  db.execute(
    'INSERT OR REPLACE INTO local_pokedex_type (id, globalNo, form, region, mega_evolution, gigantamax, version, type1, type2) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [id, global_no, form, region, mega_evo, gigantamax, version, entry['type1'], type2]
  )

  # local_pokedex_ability
  ability1 = entry['ability1'].to_s == '' ? nil : entry['ability1']
  ability2 = entry['ability2'].to_s == '' ? nil : entry['ability2']
  dream    = entry['dream_ability'].to_s == '' ? nil : entry['dream_ability']
  db.execute(
    'INSERT OR REPLACE INTO local_pokedex_ability (id, globalNo, form, region, mega_evolution, gigantamax, version, ability1, ability2, dream_ability) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [id, global_no, form, region, mega_evo, gigantamax, version, ability1, ability2, dream]
  )
end

puts "    Inserted/replaced #{data.size} Champions pokemon entries"
