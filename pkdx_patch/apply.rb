#!/usr/bin/env ruby
# frozen_string_literal: true

# pkdx_patch — pokedex.db に対するパッチを番号順に適用する統合ランナー
#
# 各パッチは pkdx_patch/NNN_name/ ディレクトリに配置する:
#   migration.rb  — Ruby スクリプト（db, repo_root を引数に受け取る）
#   data.json     — オプション。migration.rb から読み込む実データ
#
# 冪等性: pkdx_migrations テーブルで適用済みパッチを管理。
# pokedex 対応時にディレクトリを削除すれば次回 apply 時にスキップされる。

require 'sqlite3'

REPO_ROOT = File.expand_path('..', __dir__)
DB_PATH = File.join(REPO_ROOT, 'pokedex', 'pokedex.db')
PATCH_DIR = File.expand_path(__dir__)

unless File.exist?(DB_PATH)
  abort "Error: #{DB_PATH} not found. Run ./setup.sh first."
end

db = SQLite3::Database.new(DB_PATH)

# 適用済み管理テーブルを作成（冪等）
db.execute <<~SQL
  CREATE TABLE IF NOT EXISTS pkdx_migrations (
    name TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
SQL

# 番号付きディレクトリを昇順で取得
patches = Dir.glob(File.join(PATCH_DIR, '[0-9][0-9][0-9]_*'))
              .select { |d| File.directory?(d) }
              .sort

if patches.empty?
  puts 'No patches found.'
  exit 0
end

applied = 0
skipped = 0

patches.each do |patch_dir|
  name = File.basename(patch_dir)
  migration_rb = File.join(patch_dir, 'migration.rb')

  unless File.exist?(migration_rb)
    puts "  SKIP #{name} (no migration.rb)"
    next
  end

  # 適用済みチェック
  row = db.get_first_value('SELECT 1 FROM pkdx_migrations WHERE name = ?', [name])
  if row
    skipped += 1
    next
  end

  puts "  Applying #{name}..."
  # Bind patch name to a separate local so that migration.rb scripts that
  # shadow `name` in their own `.each` loops (e.g. 006_move_meta iterating
  # over move data) cannot corrupt the pkdx_migrations bookkeeping insert
  # below. `patch_name` stays constant across the eval boundary.
  patch_name = name
  begin
    db.transaction do
      # migration.rb を実行。db と patch_dir をバインディングとして渡す。
      # Ruby 2.6 では Encoding.default_external がロケール依存 (LANG=C → US-ASCII)
      # で、Japanese を含む migration.rb を eval すると invalid multibyte char で
      # 落ちる。明示的に UTF-8 で読んでロケール非依存にする。
      patch_context = binding
      eval(File.read(migration_rb, encoding: 'UTF-8'), patch_context, migration_rb)

      db.execute('INSERT INTO pkdx_migrations (name) VALUES (?)', [patch_name])
    end
    applied += 1
  rescue StandardError => e
    abort "  FAILED #{patch_name}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
  end
end

puts "pkdx_patch: #{applied} applied, #{skipped} already applied (#{patches.size} total)"
