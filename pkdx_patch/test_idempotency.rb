#!/usr/bin/env ruby
# frozen_string_literal: true

# pkdx_patch の冪等性テスト
# pokedex.db のコピーに対して apply.rb を2回実行し、結果が同一であることを検証する。

require 'fileutils'
require 'sqlite3'
require 'tmpdir'

REPO_ROOT = File.expand_path('..', __dir__)
ORIGINAL_DB = File.join(REPO_ROOT, 'pokedex', 'pokedex.db')
APPLY_RB = File.join(__dir__, 'apply.rb')

abort "Error: #{ORIGINAL_DB} not found." unless File.exist?(ORIGINAL_DB)

QUERIES = {
  'local_pokedex'        => "SELECT COUNT(*) FROM local_pokedex WHERE version='champions'",
  'local_pokedex_status'  => "SELECT COUNT(*) FROM local_pokedex_status WHERE version='champions'",
  'local_pokedex_type'    => "SELECT COUNT(*) FROM local_pokedex_type WHERE version='champions'",
  'local_pokedex_ability' => "SELECT COUNT(*) FROM local_pokedex_ability WHERE version='champions'",
  'local_waza'            => "SELECT COUNT(*) FROM local_waza WHERE version='Champions'",
  'local_waza_language'   => "SELECT COUNT(*) FROM local_waza_language WHERE version='Champions'",
  'local_pokedex_waza'    => "SELECT COUNT(*) FROM local_pokedex_waza WHERE version='Champions'",
  'pokedex (new megas)'   => "SELECT COUNT(*) FROM pokedex WHERE id IN ('0358_00000100_0_000_0','0623_00000100_0_000_0','0670_00000100_0_000_0','0678_00000100_0_000_0','0740_00000100_0_000_0','0952_00000100_0_000_0','0970_00000100_0_000_0')",
  'pkdx_migrations'       => "SELECT COUNT(*) FROM pkdx_migrations",
  'waza_duplicates'       => "SELECT COUNT(*) FROM (SELECT waza, COUNT(*) as c FROM local_waza WHERE version='Champions' GROUP BY waza HAVING c > 1)",
}.freeze

def snapshot(db_path)
  db = SQLite3::Database.new(db_path)
  result = {}
  QUERIES.each do |name, sql|
    result[name] = db.get_first_value(sql)
  end
  db.close
  result
end

def run_apply(db_path)
  env = { 'POKEDEX_DB' => db_path }
  # apply.rb は DB_PATH を REPO_ROOT/pokedex/pokedex.db から取得するため、
  # 一時DBへのシンボリックリンクで差し替える
  output = `ruby #{APPLY_RB} 2>&1`
  [$?.success?, output]
end

puts '=== pkdx_patch idempotency test ==='
puts ''

# --- テスト1: 既存DBに対する再適用（全パッチ適用済み） ---
puts '--- Test 1: Re-apply on already-patched DB ---'
snapshot_before = snapshot(ORIGINAL_DB)

# pkdx_migrations を削除して再適用するのではなく、
# 適用済み状態でもう一度 apply.rb を実行する
ok, output = run_apply(ORIGINAL_DB)
unless ok
  puts "  FAIL: apply.rb exited with error"
  puts output
  exit 1
end

snapshot_after = snapshot(ORIGINAL_DB)

all_pass = true
QUERIES.each_key do |name|
  before = snapshot_before[name]
  after = snapshot_after[name]
  if before == after
    puts "  PASS: #{name} (#{before} -> #{after})"
  else
    puts "  FAIL: #{name} (#{before} -> #{after})"
    all_pass = false
  end
end

# --- テスト2: 一時DBでフレッシュ適用を2回 ---
puts ''
puts '--- Test 2: Fresh DB - apply twice ---'

tmp_db = File.join(Dir.tmpdir, "pkdx_idempotency_test_#{$$}.db")
begin
  # パッチ未適用の素のDBを作成（pkdx_migrationsテーブルなし）
  FileUtils.cp(ORIGINAL_DB, tmp_db)
  tmp = SQLite3::Database.new(tmp_db)
  # パッチ適用状態をリセット
  tmp.execute('DROP TABLE IF EXISTS pkdx_migrations')
  # Champions データを削除
  tmp.execute("DELETE FROM local_pokedex WHERE version='champions'")
  tmp.execute("DELETE FROM local_pokedex_status WHERE version='champions'")
  tmp.execute("DELETE FROM local_pokedex_type WHERE version='champions'")
  tmp.execute("DELETE FROM local_pokedex_ability WHERE version='champions'")
  tmp.execute("DELETE FROM local_waza WHERE version='Champions'")
  tmp.execute("DELETE FROM local_waza_language WHERE version='Champions'")
  tmp.execute("DELETE FROM local_pokedex_waza WHERE version='Champions'")
  %w[0358 0623 0670 0678 0740 0952 0970].each do |gno|
    id = "#{gno}_00000100_0_000_0"
    tmp.execute('DELETE FROM pokedex WHERE id = ?', [id])
    tmp.execute('DELETE FROM pokedex_name WHERE id = ?', [id])
  end
  tmp.close

  # 本物のDBを一時的に退避して、一時DBで置き換え
  backup_db = ORIGINAL_DB + '.bak'
  FileUtils.mv(ORIGINAL_DB, backup_db)
  FileUtils.cp(tmp_db, ORIGINAL_DB)

  # 1回目の適用
  ok1, out1 = run_apply(ORIGINAL_DB)
  unless ok1
    puts "  FAIL: 1st apply failed"
    puts out1
    FileUtils.mv(backup_db, ORIGINAL_DB)
    exit 1
  end
  snapshot_1st = snapshot(ORIGINAL_DB)

  # 2回目の適用
  ok2, out2 = run_apply(ORIGINAL_DB)
  unless ok2
    puts "  FAIL: 2nd apply failed"
    puts out2
    FileUtils.mv(backup_db, ORIGINAL_DB)
    exit 1
  end
  snapshot_2nd = snapshot(ORIGINAL_DB)

  QUERIES.each_key do |name|
    v1 = snapshot_1st[name]
    v2 = snapshot_2nd[name]
    if v1 == v2
      puts "  PASS: #{name} (1st=#{v1}, 2nd=#{v2})"
    else
      puts "  FAIL: #{name} (1st=#{v1}, 2nd=#{v2})"
      all_pass = false
    end
  end

  # 元のDBを復元
  FileUtils.mv(backup_db, ORIGINAL_DB)
ensure
  FileUtils.rm_f(tmp_db)
  # バックアップが残っていたら復元
  if File.exist?(ORIGINAL_DB + '.bak')
    FileUtils.mv(ORIGINAL_DB + '.bak', ORIGINAL_DB)
  end
end

# --- テスト3: 重複チェック ---
puts ''
puts '--- Test 3: No duplicates ---'
dup_count = snapshot_before['waza_duplicates']
if dup_count == 0
  puts "  PASS: waza duplicates = 0"
else
  puts "  FAIL: waza duplicates = #{dup_count}"
  all_pass = false
end

puts ''
if all_pass
  puts 'All tests passed.'
else
  puts 'Some tests FAILED.'
  exit 1
end
