#!/usr/bin/env bash
# pkdx_patch idempotency test (MoonBit 移植後)
#
# 1. テスト用 DB をコピーして pkdx_migrations と Champions データを除去
# 2. pkdx migrate を 1 回目実行 → フル適用
# 3. もう 1 回実行 → 全スキップ
# 4. 主要テーブルのカウントが安定していることを確認
#
# 失敗時は exit 1、成功時は exit 0。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKDX_BIN="$REPO_ROOT/bin/pkdx"
SRC_DB="$REPO_ROOT/pokedex/pokedex.db"

if [ ! -f "$SRC_DB" ]; then
  echo "Error: $SRC_DB not found. Run ./setup.sh first." >&2
  exit 1
fi

TMP_DB="$(mktemp -t pkdx_idempotency.db.XXXXXX)"
trap 'rm -f "$TMP_DB"' EXIT

cp "$SRC_DB" "$TMP_DB"

# Simulate a fresh install: drop patch bookkeeping and anything migrations add.
sqlite3 "$TMP_DB" <<'EOF'
DROP TABLE IF EXISTS pkdx_migrations;
DROP TABLE IF EXISTS move_meta;
DROP TABLE IF EXISTS champions_learnset;
DELETE FROM local_pokedex        WHERE version='champions';
DELETE FROM local_pokedex_status WHERE version='champions';
DELETE FROM local_pokedex_type   WHERE version='champions';
DELETE FROM local_pokedex_ability WHERE version='champions';
DELETE FROM local_waza           WHERE version='Champions';
DELETE FROM local_waza_language  WHERE version='Champions';
DELETE FROM local_pokedex_waza   WHERE version='Champions';
EOF

queries=(
  "local_pokedex|SELECT COUNT(*) FROM local_pokedex WHERE version='champions'"
  "local_pokedex_status|SELECT COUNT(*) FROM local_pokedex_status WHERE version='champions'"
  "local_pokedex_type|SELECT COUNT(*) FROM local_pokedex_type WHERE version='champions'"
  "local_pokedex_ability|SELECT COUNT(*) FROM local_pokedex_ability WHERE version='champions'"
  "local_waza|SELECT COUNT(*) FROM local_waza WHERE version='Champions'"
  "local_waza_language|SELECT COUNT(*) FROM local_waza_language WHERE version='Champions'"
  "local_pokedex_waza|SELECT COUNT(*) FROM local_pokedex_waza WHERE version='Champions'"
  "champions_learnset_total|SELECT COUNT(*) FROM champions_learnset"
  "champions_learnset_active|SELECT COUNT(*) FROM champions_learnset WHERE state='active'"
  "champions_learnset_inactive|SELECT COUNT(*) FROM champions_learnset WHERE state='inactive'"
  "move_meta|SELECT COUNT(*) FROM move_meta"
  "pkdx_migrations|SELECT COUNT(*) FROM pkdx_migrations"
  "waza_duplicates|SELECT COUNT(*) FROM (SELECT waza, COUNT(*) AS c FROM local_waza WHERE version='Champions' GROUP BY waza HAVING c > 1)"
)

snapshot() {
  local db="$1"
  for q in "${queries[@]}"; do
    local name="${q%%|*}"
    local sql="${q#*|}"
    printf "%s=%s\n" "$name" "$(sqlite3 "$db" "$sql")"
  done
}

run_migrate() {
  POKEDEX_DB="$TMP_DB" "$PKDX_BIN" migrate --repo-root "$REPO_ROOT" > /dev/null
}

echo "=== pkdx_patch idempotency test (MoonBit) ==="

echo "--- 1st apply ---"
run_migrate
SNAP1="$(snapshot "$TMP_DB")"

echo "--- 2nd apply (should skip all) ---"
run_migrate
SNAP2="$(snapshot "$TMP_DB")"

echo
if [ "$SNAP1" = "$SNAP2" ]; then
  echo "Idempotency: OK"
else
  echo "Idempotency: FAIL"
  diff <(printf '%s\n' "$SNAP1") <(printf '%s\n' "$SNAP2") || true
  exit 1
fi

# waza_duplicates=0 is the primary data-integrity assertion.
dup_count="$(echo "$SNAP1" | awk -F= '$1=="waza_duplicates"{print $2}')"
if [ "$dup_count" != "0" ]; then
  echo "Data integrity: FAIL (waza_duplicates=$dup_count)"
  exit 1
fi
echo "Data integrity: OK (waza_duplicates=0)"

echo
echo "--- Final snapshot ---"
printf '%s\n' "$SNAP1"
