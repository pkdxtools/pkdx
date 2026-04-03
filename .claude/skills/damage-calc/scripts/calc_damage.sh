#!/bin/bash
# calc_damage.sh - ダメージ計算（Lv50, 特性・持ち物・天候対応）
# Usage: calc_damage.sh <attacker> <defender> <move> [options]
#   --version <ver>       (default: scarlet_violet)
#   --atk-ability <name>  攻撃側特性
#   --def-ability <name>  防御側特性
#   --atk-item <name>     攻撃側持ち物
#   --def-item <name>     防御側持ち物
#   --weather <type>      天候
#   --field <type>        フィールド
#   --tera-type <type>    テラスタイプ
#   --critical            急所
#   --atk-stat <value>    攻撃実数値 (省略: 特化)
#   --def-stat <value>    防御実数値 (省略: 特化)
#   --def-hp <value>      HP実数値 (省略: H252)
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

# --- 引数パース ---
ATTACKER_NAME="$1"; DEFENDER_NAME="$2"; MOVE_NAME="$3"; shift 3

VERSION_LOWER="scarlet_violet"
ATK_ABILITY="" DEF_ABILITY=""
ATK_ITEM="" DEF_ITEM=""
WEATHER="" FIELD="" TERA_TYPE=""
CRITICAL=false
ATK_STAT_OVERRIDE="特化" DEF_STAT_OVERRIDE="特化" DEF_HP_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version)     VERSION_LOWER="$2"; shift 2 ;;
    --atk-ability) ATK_ABILITY="$2"; shift 2 ;;
    --def-ability) DEF_ABILITY="$2"; shift 2 ;;
    --atk-item)    ATK_ITEM="$2"; shift 2 ;;
    --def-item)    DEF_ITEM="$2"; shift 2 ;;
    --weather)     WEATHER="$2"; shift 2 ;;
    --field)       FIELD="$2"; shift 2 ;;
    --tera-type)   TERA_TYPE="$2"; shift 2 ;;
    --critical)    CRITICAL=true; shift ;;
    --atk-stat)    ATK_STAT_OVERRIDE="$2"; shift 2 ;;
    --def-stat)    DEF_STAT_OVERRIDE="$2"; shift 2 ;;
    --def-hp)      DEF_HP_OVERRIDE="$2"; shift 2 ;;
    *) VERSION_LOWER="$1"; shift ;;  # 後方互換: 4番目の位置引数=version
  esac
done

# wazaテーブル用にMixed Caseに変換
case "$VERSION_LOWER" in
  scarlet_violet) VERSION_WAZA="Scarlet_Violet" ;;
  legendsza)      VERSION_WAZA="LegendsZA" ;;
  sword_shield)   VERSION_WAZA="sword_shield" ;;
  *)              VERSION_WAZA="$VERSION_LOWER" ;;
esac

# SQLインジェクション対策
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

# --- JSON安全生成 → damage_engine.py にパイプ ---
export ATK_NAME="$ATK_NAME_JA" ATK_GNO="$ATK_GLOBALNO"
export ATK_T1="$ATK_TYPE1" ATK_T2="${ATK_TYPE2:-}"
export ATK_HP ATK_ATK ATK_DEF ATK_SPA ATK_SPD ATK_SPE
export DEF_NAME="$DEF_NAME_JA" DEF_GNO="$DEF_GLOBALNO"
export DEF_T1="$DEF_TYPE1" DEF_T2="${DEF_TYPE2:-}"
export DEF_HP DEF_ATK DEF_DEF DEF_SPA DEF_SPD DEF_SPE
export MOVE_NAME MOVE_TYPE="$MOVE_TYPE" MOVE_CAT="$MOVE_CATEGORY" MOVE_PWR="$MOVE_POWER"
export TYPE_JSON
export M_ATK_ABILITY="$ATK_ABILITY" M_DEF_ABILITY="$DEF_ABILITY"
export M_ATK_ITEM="$ATK_ITEM" M_DEF_ITEM="$DEF_ITEM"
export M_WEATHER="$WEATHER" M_FIELD="$FIELD" M_TERA_TYPE="$TERA_TYPE"
export M_CRITICAL="$CRITICAL"
export M_ATK_STAT="$ATK_STAT_OVERRIDE" M_DEF_STAT="$DEF_STAT_OVERRIDE" M_DEF_HP="${DEF_HP_OVERRIDE:-}"

python3 -c "
import json, os
print(json.dumps({
    'attacker': {
        'name': os.environ['ATK_NAME'], 'globalNo': os.environ['ATK_GNO'],
        'types': [os.environ['ATK_T1'], os.environ.get('ATK_T2', '')],
        'base': {
            'hp': int(os.environ['ATK_HP']), 'atk': int(os.environ['ATK_ATK']),
            'def': int(os.environ['ATK_DEF']), 'spa': int(os.environ['ATK_SPA']),
            'spd': int(os.environ['ATK_SPD']), 'spe': int(os.environ['ATK_SPE'])
        }
    },
    'defender': {
        'name': os.environ['DEF_NAME'], 'globalNo': os.environ['DEF_GNO'],
        'types': [os.environ['DEF_T1'], os.environ.get('DEF_T2', '')],
        'base': {
            'hp': int(os.environ['DEF_HP']), 'atk': int(os.environ['DEF_ATK']),
            'def': int(os.environ['DEF_DEF']), 'spa': int(os.environ['DEF_SPA']),
            'spd': int(os.environ['DEF_SPD']), 'spe': int(os.environ['DEF_SPE'])
        }
    },
    'move': {
        'name': os.environ['MOVE_NAME'], 'type': os.environ['MOVE_TYPE'],
        'category': os.environ['MOVE_CAT'], 'power': os.environ['MOVE_PWR']
    },
    'type_chart_path': os.environ['TYPE_JSON'],
    'modifiers': {
        'atk_ability': os.environ.get('M_ATK_ABILITY', ''),
        'def_ability': os.environ.get('M_DEF_ABILITY', ''),
        'atk_item': os.environ.get('M_ATK_ITEM', ''),
        'def_item': os.environ.get('M_DEF_ITEM', ''),
        'weather': os.environ.get('M_WEATHER', ''),
        'field': os.environ.get('M_FIELD', ''),
        'tera_type': os.environ.get('M_TERA_TYPE', ''),
        'critical': os.environ.get('M_CRITICAL', '') == 'true',
        'atk_stat': os.environ.get('M_ATK_STAT', '特化'),
        'def_stat': os.environ.get('M_DEF_STAT', '特化'),
        'def_hp': os.environ.get('M_DEF_HP', '')
    }
}, ensure_ascii=False))
" | python3 "$SCRIPT_DIR/damage_engine.py"
