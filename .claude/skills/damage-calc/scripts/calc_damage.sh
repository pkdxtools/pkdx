#!/bin/bash
# calc_damage.sh - ダメージ計算（特化同士, Lv50）
# Usage: calc_damage.sh <attacker_name> <defender_name> <move_name> [version]
# Output: パイプ区切りテキスト（条件情報 + 16段階乱数テーブル + 確定数）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
DB_PATH="${POKEDEX_DB:-$REPO_ROOT/pokedex/pokedex.db}"
POKEDEX_DIR="$(dirname "$DB_PATH")"
TYPE_JSON="$POKEDEX_DIR/type/type.json"

if [ ! -f "$DB_PATH" ]; then
  echo "error|db_not_found|$DB_PATH" >&2
  exit 1
fi

ATTACKER_NAME="$1"
DEFENDER_NAME="$2"
MOVE_NAME="$3"
VERSION_LOWER="${4:-scarlet_violet}"

# wazaテーブル用にMixed Caseに変換
case "$VERSION_LOWER" in
  scarlet_violet) VERSION_WAZA="Scarlet_Violet" ;;
  legendsza)      VERSION_WAZA="LegendsZA" ;;
  sword_shield)   VERSION_WAZA="sword_shield" ;;
  *)              VERSION_WAZA="$VERSION_LOWER" ;;
esac

# SQLインジェクション対策: シングルクォートをエスケープ
escape_sql() {
  echo "$1" | sed "s/'/''/g"
}

ATK_NAME_ESC="$(escape_sql "$ATTACKER_NAME")"
DEF_NAME_ESC="$(escape_sql "$DEFENDER_NAME")"
MOVE_NAME_ESC="$(escape_sql "$MOVE_NAME")"

# --- 攻撃側クエリ ---
ATTACKER_DATA=$(sqlite3 -separator '|' "$DB_PATH" \
  "SELECT
    pn.globalNo, pn.name,
    t.type1, t.type2,
    s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed
  FROM pokedex_name pn
  JOIN local_pokedex_type t ON pn.globalNo = t.globalNo
    AND t.version = '${VERSION_LOWER}'
    AND COALESCE(t.form, '') = '' AND COALESCE(t.region, '') = ''
    AND COALESCE(t.mega_evolution, '') = '' AND COALESCE(t.gigantamax, '') = ''
  JOIN local_pokedex_status s ON pn.globalNo = s.globalNo
    AND s.version = '${VERSION_LOWER}'
    AND COALESCE(s.form, '') = '' AND COALESCE(s.region, '') = ''
    AND COALESCE(s.mega_evolution, '') = '' AND COALESCE(s.gigantamax, '') = ''
  WHERE COALESCE(pn.form, '') = ''
    AND COALESCE(pn.region, '') = ''
    AND COALESCE(pn.mega_evolution, '') = ''
    AND COALESCE(pn.gigantamax, '') = ''
    AND (
      (pn.language = 'jpn' AND pn.name = '${ATK_NAME_ESC}')
      OR (pn.language = 'eng' AND LOWER(pn.name) = LOWER('${ATK_NAME_ESC}'))
    )
  LIMIT 1;")

if [ -z "$ATTACKER_DATA" ]; then
  echo "error|attacker_not_found|${ATTACKER_NAME}"
  exit 1
fi

IFS='|' read -r ATK_GLOBALNO ATK_NAME_JA ATK_TYPE1 ATK_TYPE2 \
  ATK_HP ATK_ATK ATK_DEF ATK_SPA ATK_SPD ATK_SPE <<< "$ATTACKER_DATA"

# --- 防御側クエリ ---
DEFENDER_DATA=$(sqlite3 -separator '|' "$DB_PATH" \
  "SELECT
    pn.globalNo, pn.name,
    t.type1, t.type2,
    s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed
  FROM pokedex_name pn
  JOIN local_pokedex_type t ON pn.globalNo = t.globalNo
    AND t.version = '${VERSION_LOWER}'
    AND COALESCE(t.form, '') = '' AND COALESCE(t.region, '') = ''
    AND COALESCE(t.mega_evolution, '') = '' AND COALESCE(t.gigantamax, '') = ''
  JOIN local_pokedex_status s ON pn.globalNo = s.globalNo
    AND s.version = '${VERSION_LOWER}'
    AND COALESCE(s.form, '') = '' AND COALESCE(s.region, '') = ''
    AND COALESCE(s.mega_evolution, '') = '' AND COALESCE(s.gigantamax, '') = ''
  WHERE COALESCE(pn.form, '') = ''
    AND COALESCE(pn.region, '') = ''
    AND COALESCE(pn.mega_evolution, '') = ''
    AND COALESCE(pn.gigantamax, '') = ''
    AND (
      (pn.language = 'jpn' AND pn.name = '${DEF_NAME_ESC}')
      OR (pn.language = 'eng' AND LOWER(pn.name) = LOWER('${DEF_NAME_ESC}'))
    )
  LIMIT 1;")

if [ -z "$DEFENDER_DATA" ]; then
  echo "error|defender_not_found|${DEFENDER_NAME}"
  exit 1
fi

IFS='|' read -r DEF_GLOBALNO DEF_NAME_JA DEF_TYPE1 DEF_TYPE2 \
  DEF_HP DEF_ATK DEF_DEF DEF_SPA DEF_SPD DEF_SPE <<< "$DEFENDER_DATA"

# --- 技クエリ ---
MOVE_DATA=$(sqlite3 -separator '|' "$DB_PATH" \
  "SELECT w.type, w.category, w.power
  FROM local_waza_language wl
  JOIN local_waza w ON wl.waza = w.waza AND wl.version = w.version
  WHERE wl.version = '${VERSION_WAZA}'
    AND wl.language = 'jpn'
    AND wl.name = '${MOVE_NAME_ESC}'
  LIMIT 1;")

if [ -z "$MOVE_DATA" ]; then
  echo "error|move_not_found|${MOVE_NAME}"
  exit 1
fi

IFS='|' read -r MOVE_TYPE MOVE_CATEGORY MOVE_POWER <<< "$MOVE_DATA"

if [ "$MOVE_CATEGORY" = "変化" ]; then
  echo "error|status_move|${MOVE_NAME}"
  exit 1
fi

if [ "$MOVE_POWER" = "-" ] || [ -z "$MOVE_POWER" ]; then
  echo "error|variable_power|${MOVE_NAME}"
  exit 1
fi

# --- 物理/特殊判定 → 使用する種族値を決定 ---
if [ "$MOVE_CATEGORY" = "物理" ]; then
  ATK_BASE=$ATK_ATK
  DEF_BASE=$DEF_DEF
  ATK_STAT_NAME="こうげき"
  DEF_STAT_NAME="ぼうぎょ"
elif [ "$MOVE_CATEGORY" = "特殊" ]; then
  ATK_BASE=$ATK_SPA
  DEF_BASE=$DEF_SPD
  ATK_STAT_NAME="とくこう"
  DEF_STAT_NAME="とくぼう"
else
  echo "error|unknown_category|${MOVE_CATEGORY}"
  exit 1
fi

# --- Lv50 特化実数値計算 ---
# 攻撃実数値: floor((base + 52) * 1.1) → (base + 52) * 11 / 10
ATK_STAT=$(( (ATK_BASE + 52) * 11 / 10 ))

# 防御側HP: base + 107 (Lv50, IV31, EV252)
DEF_HP_ACTUAL=$(( DEF_HP + 107 ))

# 防御実数値: floor((base + 52) * 1.1) → (base + 52) * 11 / 10
DEF_STAT=$(( (DEF_BASE + 52) * 11 / 10 ))

# --- STAB判定 ---
HAS_STAB=0
if [ "$MOVE_TYPE" = "$ATK_TYPE1" ]; then
  HAS_STAB=1
elif [ -n "$ATK_TYPE2" ] && [ "$MOVE_TYPE" = "$ATK_TYPE2" ]; then
  HAS_STAB=1
fi

# --- タイプ相性取得 (python3) ---
TYPE_EFF_DATA=$(python3 -c "
import json
from fractions import Fraction
with open('${TYPE_JSON}') as f:
    data = json.load(f)
chart = next(e['type'] for e in data['type'] if 'scarlet_violet' in e['geme_version'])
move_type = '${MOVE_TYPE}'
def_type1 = '${DEF_TYPE1}'
def_type2 = '${DEF_TYPE2}'
eff1 = chart.get(move_type, {}).get(def_type1, 1)
eff2 = chart.get(move_type, {}).get(def_type2, 1) if def_type2 else 1
f1 = Fraction(eff1).limit_denominator(16)
f2 = Fraction(eff2).limit_denominator(16)
total_eff = eff1 * eff2
print(f'{f1.numerator} {f1.denominator} {f2.numerator} {f2.denominator} {total_eff}')
")

read -r EFF1_NUM EFF1_DEN EFF2_NUM EFF2_DEN TOTAL_EFF <<< "$TYPE_EFF_DATA"

# タイプ無効チェック
if [ "$EFF1_NUM" -eq 0 ] || [ "$EFF2_NUM" -eq 0 ]; then
  echo "error|immune|${MOVE_TYPE}→${DEF_TYPE1}/${DEF_TYPE2}"
  exit 1
fi

# --- 基礎ダメージ計算 ---
# floor(floor(22 * power * atk / def) / 50 + 2)
INNER=$(( 22 * MOVE_POWER * ATK_STAT / DEF_STAT ))
DAMAGE_BASE=$(( INNER / 50 + 2 ))

# --- タイプ表示用ヘルパー ---
format_types() {
  if [ -n "$2" ]; then
    echo "${1}/${2}"
  else
    echo "$1"
  fi
}

ATK_TYPES=$(format_types "$ATK_TYPE1" "$ATK_TYPE2")
DEF_TYPES=$(format_types "$DEF_TYPE1" "$DEF_TYPE2")

# --- メタデータ出力 ---
echo "=== DAMAGE CALC RESULT ==="
echo "attacker|${ATK_NAME_JA}|${ATK_TYPES}|${ATK_STAT_NAME}:${ATK_BASE}→${ATK_STAT}"
echo "defender|${DEF_NAME_JA}|${DEF_TYPES}|HP:${DEF_HP}→${DEF_HP_ACTUAL}|${DEF_STAT_NAME}:${DEF_BASE}→${DEF_STAT}"
echo "move|${MOVE_NAME}|${MOVE_TYPE}|${MOVE_CATEGORY}|${MOVE_POWER}"
if [ "$HAS_STAB" -eq 1 ]; then
  echo "stab|yes"
else
  echo "stab|no"
fi
echo "type_effectiveness|${TOTAL_EFF}x"

# --- 乱数16段階ダメージ計算 ---
DAMAGES=()
for RAND in $(seq 85 100); do
  DMG=$(( DAMAGE_BASE * RAND / 100 ))

  # STAB適用 (五捨五超入: +2047で整数除算)
  if [ "$HAS_STAB" -eq 1 ]; then
    DMG=$(( (DMG * 6144 + 2047) / 4096 ))
  fi

  # タイプ相性を順次適用 (各タイプごとにfloor)
  DMG=$(( DMG * EFF1_NUM / EFF1_DEN ))
  DMG=$(( DMG * EFF2_NUM / EFF2_DEN ))

  # 最低ダメージは1
  if [ "$DMG" -lt 1 ]; then
    DMG=1
  fi

  DAMAGES+=("$DMG")
done

# --- 乱数テーブル出力 (横軸=乱数値, 縦軸=ラベル) ---
DAMAGE_LIST=$(IFS=,; echo "${DAMAGES[*]}")
python3 -c "
hp = ${DEF_HP_ACTUAL}
damages = [${DAMAGE_LIST}]
rands = list(range(85, 101))
pcts = [d / hp * 100 for d in damages]
print('label|' + '|'.join(str(r) for r in rands))
print('damage|' + '|'.join(str(d) for d in damages))
print('percent|' + '|'.join(f'{p:.1f}%' for p in pcts))
"

# --- 確定数判定 ---
MIN_DMG=${DAMAGES[0]}
MAX_DMG=${DAMAGES[15]}

python3 -c "
min_d = ${MIN_DMG}
max_d = ${MAX_DMG}
hp = ${DEF_HP_ACTUAL}
damages = [${DAMAGE_LIST}]

min_pct = min_d / hp * 100
max_pct = max_d / hp * 100

print(f'summary|{min_d}~{max_d}|{min_pct:.1f}%~{max_pct:.1f}%')

for n in range(1, 5):
    ko_count = sum(1 for d in damages if d * n >= hp)
    if ko_count == 16:
        print(f'ko|確定{n}発')
        break
    elif ko_count > 0:
        print(f'ko|乱数{n}発({ko_count}/16)')
        break
else:
    print('ko|5発以上')
"
