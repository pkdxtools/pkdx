# 001_mega_legendsza — LegendsZA JSON からメガシンカデータを pokedex.db にパッチ
#
# apply.rb から eval される。db (SQLite3::Database) と patch_dir が利用可能。

require 'json'

za_json = File.join(REPO_ROOT, 'pokedex', 'pokedex', 'LegendsZA', 'LegendsZA.json')
unless File.exist?(za_json)
  abort "Error: #{za_json} not found. Run 'git submodule update --init'."
end

data = JSON.parse(File.read(za_json))
pokedex = data['pokedex']
version = 'legendsza'

megas = []
pokedex.each do |_region_name, entries|
  entries.each do |_no, forms|
    forms.each do |_form_id, info|
      next unless info['mega_evolution'] && info['mega_evolution'] != ''
      megas << info
    end
  end
end

if megas.empty?
  puts '    No mega evolution data found in JSON.'
else

patched = 0

megas.each do |mega|
  id = mega['id']
  mega_name = mega['mega_evolution']

  db.execute(
    'UPDATE local_pokedex SET mega_evolution = ? WHERE id = ? AND version = ?',
    [mega_name, id, version]
  )

  db.execute(
    'UPDATE local_pokedex_status SET mega_evolution = ?, hp = ?, attack = ?, defense = ?, special_attack = ?, special_defense = ?, speed = ? WHERE id = ? AND version = ?',
    [mega_name, mega['hp'], mega['attack'], mega['defense'], mega['special_attack'], mega['special_defense'], mega['speed'], id, version]
  )

  type2 = mega['type2']
  type2 = nil if type2 == ''
  db.execute(
    'UPDATE local_pokedex_type SET mega_evolution = ?, type1 = ?, type2 = ? WHERE id = ? AND version = ?',
    [mega_name, mega['type1'], type2, id, version]
  )

  ability2 = mega['ability2']
  ability2 = nil if ability2 == ''
  dream = mega['dream_ability']
  dream = nil if dream == ''
  db.execute(
    'UPDATE local_pokedex_ability SET mega_evolution = ?, ability1 = ?, ability2 = ?, dream_ability = ? WHERE id = ? AND version = ?',
    [mega_name, mega['ability1'], ability2, dream, id, version]
  )

  names = mega['name'] || {}
  if names['jpn']
    db.execute(
      'UPDATE pokedex_name SET mega_evolution = ?, name = ? WHERE id = ? AND language = ?',
      [mega_name, names['jpn'], id, 'jpn']
    )
  end
  if names['eng']
    db.execute(
      'UPDATE pokedex_name SET mega_evolution = ?, name = ? WHERE id = ? AND language = ?',
      [mega_name, names['eng'], id, 'eng']
    )
  end

  patched += 1
end

puts "    Patched #{patched} mega evolution entries"
end
