"""ポケモンダメージ計算エンジン (Gen9準拠)"""
import json
import sys
from fractions import Fraction

# --- 4096丸め (五捨五超入) ---
def round5(value, mult_4096):
    return (value * mult_4096 + 2047) // 4096

# --- 技フラグセット ---
PUNCH_MOVES = frozenset([
    "メガトンパンチ", "ほのおのパンチ", "れいとうパンチ", "かみなりパンチ",
    "ピヨピヨパンチ", "マッハパンチ", "きあいパンチ", "コメットパンチ",
    "シャドーパンチ", "スカイアッパー", "バレットパンチ", "ドレインパンチ",
    "アイスハンマー", "プラズマフィスト", "あんこくきょうだ", "すいりゅうれんだ",
    "ダブルパンツァー", "グロウパンチ", "ジェットパンチ", "アームハンマー",
    "ばくれつパンチ", "かみなりパンチ", "れんぞくパンチ", "きあいパンチ",
    "ぶちかまし", "アイアンフィスト", "ふんどのこぶし",
])

BITE_MOVES = frozenset([
    "かみつく", "かみくだく", "ほのおのキバ", "こおりのキバ", "かみなりのキバ",
    "どくどくのキバ", "サイコファング", "エラがみ", "くらいつく",
])

PULSE_MOVES = frozenset([
    "はどうだん", "あくのはどう", "みずのはどう", "りゅうのはどう",
    "だいちのはどう", "いやしのはどう", "こんげんのはどう", "てっていこうせん",
])

RECOIL_MOVES = frozenset([
    "すてみタックル", "とっしん", "ブレイブバード", "フレアドライブ",
    "ウッドハンマー", "ボルテッカー", "もろはのずつき", "じごくぐるま",
    "ワイルドボルト", "アフロブレイク", "もろはのやいば", "ウェーブタックル",
])

CONTACT_MOVES = frozenset([
    "たいあたり", "ひっかく", "つつく", "のしかかり", "しめつける",
    "たたきつける", "ずつき", "つのでつく", "みだれづき", "とっしん",
    "すてみタックル", "からてチョップ", "メガトンパンチ", "メガトンキック",
    "かみつく", "かみくだく", "でんこうせっか", "しんそく", "アクアジェット",
    "ふいうち", "マッハパンチ", "バレットパンチ", "アイスシャード",
    "かげうち", "フェイント", "グロウパンチ", "ドレインパンチ",
    "アームハンマー", "ばくれつパンチ", "スカイアッパー", "きあいパンチ",
    "インファイト", "ばかぢから", "とびひざげり", "とびげり",
    "ブレイブバード", "フレアドライブ", "ボルテッカー", "ワイルドボルト",
    "ウッドハンマー", "じゃれつく", "じしん", "じならし",
    "アイアンヘッド", "アイアンテール", "ドラゴンクロー", "げきりん",
    "ドラゴンダイブ", "シャドークロー", "かみなりパンチ", "ほのおのパンチ",
    "れいとうパンチ", "ほのおのキバ", "こおりのキバ", "かみなりのキバ",
    "たきのぼり", "アクアブレイク", "ウェーブタックル",
    "アクセルブレイク", "イナズマドライブ",
    "ジェットパンチ", "あんこくきょうだ", "すいりゅうれんだ",
    "サイコファング", "エラがみ", "もろはのずつき",
    "DDラリアット", "ぶちかまし", "ふんどのこぶし",
    "テラバースト",
])

# --- 攻撃側特性 ---
ATK_ABILITIES = {
    "ちからもち":      {"stage": "stat", "stat": "atk", "mult": 2.0},
    "ヨガパワー":      {"stage": "stat", "stat": "atk", "mult": 2.0},
    "はりきり":        {"stage": "stat", "stat": "atk", "mult": 1.5, "cond": "physical"},
    "サンパワー":      {"stage": "stat", "stat": "spa", "mult": 1.5, "weather": "はれ"},
    "テクニシャン":    {"stage": "power", "mult": 1.5, "cond": "power_lte_60"},
    "てつのこぶし":    {"stage": "power", "mult": 1.2, "cond": "punch"},
    "がんじょうあご":  {"stage": "power", "mult": 1.5, "cond": "bite"},
    "メガランチャー":  {"stage": "power", "mult": 1.5, "cond": "pulse"},
    "すてみ":          {"stage": "power", "mult": 1.2, "cond": "recoil"},
    "すなのちから":    {"stage": "power", "mult": 1.3, "cond": "rock_ground_steel", "weather": "すなあらし"},
    "すいほう":        {"stage": "power", "mult": 2.0, "cond": "water_type"},
    "もらいび":        {"stage": "power", "mult": 1.5, "cond": "fire_type"},
    "てきおうりょく":  {"stage": "stab", "mult": 2.0},
    "フェアリースキン": {"stage": "skin", "to": "フェアリー"},
    "スカイスキン":     {"stage": "skin", "to": "ひこう"},
    "フリーズスキン":   {"stage": "skin", "to": "こおり"},
    "エレキスキン":     {"stage": "skin", "to": "でんき"},
    "こだいかっせい":   {"stage": "stat", "stat": "highest_atk", "mult": 1.3, "weather": "はれ"},
    "クォークチャージ": {"stage": "stat", "stat": "highest_atk", "mult": 1.3, "field": "エレキ"},
    "トランジスタ":     {"stage": "final", "mult_4096": 5325, "cond": "electric_type"},
    "りゅうのあぎと":   {"stage": "final", "mult_4096": 5325, "cond": "dragon_type"},
    "はがねのせいしん": {"stage": "final", "mult_4096": 5325, "cond": "steel_type"},
    "ちからずく":       {"stage": "final", "mult_4096": 5325},
    "アナライズ":       {"stage": "final", "mult_4096": 5325},
    "いろめがね":       {"stage": "tinted_lens"},
}

# --- 防御側特性 ---
DEF_ABILITIES = {
    "ちょすい":        {"stage": "immune", "types": ["みず"]},
    "よびみず":        {"stage": "immune", "types": ["みず"]},
    "もらいび":        {"stage": "immune", "types": ["ほのお"]},
    "ひらいしん":      {"stage": "immune", "types": ["でんき"]},
    "でんきエンジン":  {"stage": "immune", "types": ["でんき"]},
    "ふゆう":          {"stage": "immune", "types": ["じめん"]},
    "そうしょく":      {"stage": "immune", "types": ["くさ"]},
    "かんそうはだ":    {"stage": "compound", "effects": [
        {"stage": "immune", "types": ["みず"]},
        {"stage": "final", "mult_4096": 5120, "cond": "fire_type"},
    ]},
    "ファーコート":    {"stage": "stat", "stat": "def", "mult": 2.0},
    "マルチスケイル":  {"stage": "final", "mult_4096": 2048},
    "フィルター":      {"stage": "final", "mult_4096": 3072, "cond": "super_effective"},
    "ハードロック":    {"stage": "final", "mult_4096": 3072, "cond": "super_effective"},
    "こおりのりんぷん": {"stage": "final", "mult_4096": 2048, "cond": "special"},
    "あついしぼう":    {"stage": "type_resist", "types": ["ほのお", "こおり"], "mult": 0.5},
    "たいねつ":        {"stage": "type_resist", "types": ["ほのお"], "mult": 0.5},
    "もふもふ":        {"stage": "compound", "effects": [
        {"stage": "final", "mult_4096": 2048, "cond": "contact"},
        {"stage": "type_resist", "types": ["ほのお"], "mult": 2.0},
    ]},
    "すいほう":        {"stage": "type_resist", "types": ["ほのお"], "mult": 0.5},
}

# --- 攻撃側持ち物 ---
ATK_ITEMS = {
    "こだわりハチマキ": {"stage": "stat", "stat": "atk", "mult": 1.5},
    "こだわりメガネ":   {"stage": "stat", "stat": "spa", "mult": 1.5},
    "ふといホネ":       {"stage": "stat", "stat": "atk", "mult": 2.0, "pokemon": ["0104", "0105"]},
    "でんきだま":       {"stage": "stat", "stat": "both_atk", "mult": 2.0, "pokemon": ["0025"]},
    "いのちのたま":     {"stage": "final", "mult_4096": 5324},
    "たつじんのおび":   {"stage": "final", "mult_4096": 4915, "cond": "super_effective"},
    "ちからのハチマキ": {"stage": "final", "mult_4096": 4505, "cond": "physical"},
    "ものしりメガネ":   {"stage": "final", "mult_4096": 4505, "cond": "special"},
}

# --- 防御側持ち物 ---
DEF_ITEMS = {
    "しんかのきせき":   {"stage": "stat", "stat": "both_def", "mult": 1.5},
    "とつげきチョッキ": {"stage": "stat", "stat": "spd", "mult": 1.5},
}

# 半減きのみ
RESIST_BERRIES = {
    "オッカのみ": "ほのお", "イトケのみ": "みず", "リンドのみ": "くさ",
    "ヤチェのみ": "こおり", "ヨプのみ": "かくとう", "ビアーのみ": "どく",
    "シュカのみ": "じめん", "バコウのみ": "ひこう", "ウタンのみ": "エスパー",
    "タンガのみ": "むし", "ヨロギのみ": "いわ", "カシブのみ": "ゴースト",
    "ハバンのみ": "ドラゴン", "ナモのみ": "あく", "リリバのみ": "はがね",
    "ロゼルのみ": "フェアリー", "ホズのみ": "ノーマル",
}

# タイプ強化アイテム（プレート・おこう系）
TYPE_BOOST_ITEMS = {
    "もえさかるプレート": "ほのお", "しずくプレート": "みず", "みどりのプレート": "くさ",
    "つららのプレート": "こおり", "こぶしのプレート": "かくとう", "もうどくプレート": "どく",
    "だいちのプレート": "じめん", "あおぞらプレート": "ひこう", "ふしぎのプレート": "エスパー",
    "たまむしプレート": "むし", "がんせきプレート": "いわ", "もののけプレート": "ゴースト",
    "りゅうのプレート": "ドラゴン", "こわもてプレート": "あく", "こうてつプレート": "はがね",
    "せいれいプレート": "フェアリー",
    "シルクのスカーフ": "ノーマル", "もくたん": "ほのお", "しんぴのしずく": "みず",
    "きせきのタネ": "くさ", "じしゃく": "でんき", "とけないこおり": "こおり",
    "くろおび": "かくとう", "どくバリ": "どく", "やわらかいすな": "じめん",
    "するどいくちばし": "ひこう", "まがったスプーン": "エスパー", "ぎんのこな": "むし",
    "かたいいし": "いわ", "のろいのおふだ": "ゴースト", "りゅうのキバ": "ドラゴン",
    "くろいメガネ": "あく", "メタルコート": "はがね",
}

# --- 天候 ---
WEATHER_DATA = {
    "はれ":       {"fire": 6144, "water": 2048},
    "あめ":       {"water": 6144, "fire": 2048},
    "すなあらし": {"rock_spd": 1.5},
    "ゆき":       {"ice_def": 1.5},
}

# --- フィールド ---
FIELD_DATA = {
    "エレキ":   {"type": "でんき",   "mult_4096": 5325},
    "グラス":   {"type": "くさ",     "mult_4096": 5325},
    "サイコ":   {"type": "エスパー", "mult_4096": 5325},
    "ミスト":   {"type": "ドラゴン", "mult_4096": 2048},
}

# --- タイプ→日本語マッピング ---
TYPE_TO_FIRE = {"ほのお"}
TYPE_TO_WATER = {"みず"}
TYPE_TO_ELECTRIC = {"でんき"}
TYPE_TO_ROCK_GROUND_STEEL = {"いわ", "じめん", "はがね"}


def calc_stat(base, is_hp=False, nature_boost=True, custom=None):
    """Lv50実数値計算"""
    if custom is not None:
        return int(custom)
    if is_hp:
        return base + 107
    stat = base + 52
    if nature_boost:
        stat = stat * 11 // 10
    return stat


def check_power_condition(cond, move_name, move_type, move_power):
    if cond == "power_lte_60":
        return move_power <= 60
    if cond == "punch":
        return move_name in PUNCH_MOVES
    if cond == "bite":
        return move_name in BITE_MOVES
    if cond == "pulse":
        return move_name in PULSE_MOVES
    if cond == "recoil":
        return move_name in RECOIL_MOVES
    if cond == "water_type":
        return move_type == "みず"
    if cond == "fire_type":
        return move_type == "ほのお"
    if cond == "rock_ground_steel":
        return move_type in TYPE_TO_ROCK_GROUND_STEEL
    return False


def get_type_chart(path):
    with open(path) as f:
        data = json.load(f)
    return next(e["type"] for e in data["type"] if "scarlet_violet" in e["geme_version"])


def calc_type_effectiveness(chart, move_type, def_types):
    eff1 = chart.get(move_type, {}).get(def_types[0], 1)
    eff2 = chart.get(move_type, {}).get(def_types[1], 1) if def_types[1] else 1
    return eff1, eff2, eff1 * eff2


def main():
    data = json.load(sys.stdin)
    atk = data["attacker"]
    dfn = data["defender"]
    move = data["move"]
    mods = data["modifiers"]

    chart = get_type_chart(data["type_chart_path"])

    move_name = move["name"]
    move_type = move["type"]
    move_category = move["category"]
    move_power = int(move["power"])
    atk_types = [t for t in atk["types"] if t]
    def_types = [dfn["types"][0], dfn["types"][1] if len(dfn["types"]) > 1 else None]

    weather = mods.get("weather") or None
    field = mods.get("field") or None
    tera_type = mods.get("tera_type") or None
    is_critical = mods.get("critical", False)
    atk_ability = mods.get("atk_ability") or None
    def_ability = mods.get("def_ability") or None
    atk_item = mods.get("atk_item") or None
    def_item = mods.get("def_item") or None
    custom_atk_stat = mods.get("atk_stat") or None
    custom_def_stat = mods.get("def_stat") or None
    custom_def_hp = mods.get("def_hp") or None

    if custom_atk_stat == "特化":
        custom_atk_stat = None
    if custom_def_stat == "特化":
        custom_def_stat = None

    is_physical = move_category == "物理"
    is_special = move_category == "特殊"

    # --- 1. スキン特性 ---
    skin_bonus = False
    if atk_ability and atk_ability in ATK_ABILITIES:
        ab = ATK_ABILITIES[atk_ability]
        if ab.get("stage") == "skin" and move_type == "ノーマル":
            move_type = ab["to"]
            skin_bonus = True

    # --- テラスタル ---
    stab_types = list(atk_types)
    tera_stab_bonus = False
    if tera_type:
        stab_types.append(tera_type)
        if tera_type in atk_types and move_type == tera_type:
            tera_stab_bonus = True  # 元タイプ+テラスタイプ一致 → 2.0x

    # --- 2. 実数値計算 ---
    atk_base_stat = atk["base"]["atk"] if is_physical else atk["base"]["spa"]
    def_base_hp = dfn["base"]["hp"]
    def_base_stat = dfn["base"]["def"] if is_physical else dfn["base"]["spd"]

    atk_stat_name = "こうげき" if is_physical else "とくこう"
    def_stat_name = "ぼうぎょ" if is_physical else "とくぼう"

    atk_stat = calc_stat(atk_base_stat, custom=custom_atk_stat)
    def_hp = calc_stat(def_base_hp, is_hp=True, custom=custom_def_hp)
    def_stat = calc_stat(def_base_stat, custom=custom_def_stat)

    # 2b. 特性ステータス補正
    if atk_ability and atk_ability in ATK_ABILITIES:
        ab = ATK_ABILITIES[atk_ability]
        if ab.get("stage") == "stat":
            should_apply = True
            if ab.get("cond") == "physical" and not is_physical:
                should_apply = False
            if ab.get("weather") and weather != ab["weather"]:
                should_apply = False
            if ab.get("field") and field != ab["field"]:
                should_apply = False
            if should_apply:
                target = ab["stat"]
                if target == "atk" and is_physical:
                    atk_stat = int(atk_stat * ab["mult"])
                elif target == "spa" and is_special:
                    atk_stat = int(atk_stat * ab["mult"])
                elif target == "highest_atk":
                    atk_stat = int(atk_stat * ab["mult"])
                elif target == "both_atk":
                    atk_stat = int(atk_stat * ab["mult"])

    if def_ability and def_ability in DEF_ABILITIES:
        ab = DEF_ABILITIES[def_ability]
        if ab.get("stage") == "stat":
            if ab["stat"] == "def" and is_physical:
                def_stat = int(def_stat * ab["mult"])
            elif ab["stat"] == "spd" and is_special:
                def_stat = int(def_stat * ab["mult"])
        elif ab.get("stage") == "compound":
            for eff in ab["effects"]:
                if eff.get("stage") == "stat":
                    if eff["stat"] == "def" and is_physical:
                        def_stat = int(def_stat * eff["mult"])

    # 2c. 持ち物ステータス補正
    if atk_item and atk_item in ATK_ITEMS:
        it = ATK_ITEMS[atk_item]
        if it.get("stage") == "stat":
            if it.get("pokemon") and atk["globalNo"] not in it["pokemon"]:
                pass
            else:
                target = it["stat"]
                if target == "atk" and is_physical:
                    atk_stat = int(atk_stat * it["mult"])
                elif target == "spa" and is_special:
                    atk_stat = int(atk_stat * it["mult"])
                elif target == "both_atk":
                    atk_stat = int(atk_stat * it["mult"])

    if def_item and def_item in DEF_ITEMS:
        it = DEF_ITEMS[def_item]
        if it.get("stage") == "stat":
            target = it["stat"]
            if target == "spd" and is_special:
                def_stat = int(def_stat * it["mult"])
            elif target == "both_def":
                def_stat = int(def_stat * it["mult"])

    # 2d. 天候ステータス補正
    if weather and weather in WEATHER_DATA:
        w = WEATHER_DATA[weather]
        if "rock_spd" in w and "いわ" in [dfn["types"][0], dfn["types"][1] if len(dfn["types"]) > 1 else None] and is_special:
            def_stat = int(def_stat * w["rock_spd"])
        if "ice_def" in w and "こおり" in [dfn["types"][0], dfn["types"][1] if len(dfn["types"]) > 1 else None] and is_physical:
            def_stat = int(def_stat * w["ice_def"])

    # --- 防御側特性: 免疫チェック ---
    if def_ability and def_ability in DEF_ABILITIES:
        ab = DEF_ABILITIES[def_ability]
        if ab.get("stage") == "immune" and move_type in ab["types"]:
            print(f"error|immune|{move_type}→{def_ability}")
            return
        if ab.get("stage") == "compound":
            for eff in ab["effects"]:
                if eff.get("stage") == "immune" and move_type in eff["types"]:
                    print(f"error|immune|{move_type}→{def_ability}")
                    return

    # --- 防御側特性: タイプ耐性 (あついしぼう等) ---
    type_resist_mult = 1.0
    if def_ability and def_ability in DEF_ABILITIES:
        ab = DEF_ABILITIES[def_ability]
        if ab.get("stage") == "type_resist" and move_type in ab["types"]:
            type_resist_mult *= ab["mult"]
        elif ab.get("stage") == "compound":
            for eff in ab["effects"]:
                if eff.get("stage") == "type_resist" and move_type in eff["types"]:
                    type_resist_mult *= eff["mult"]

    # --- 3. 威力計算 ---
    effective_power = move_power

    # 3b. 特性威力補正
    if atk_ability and atk_ability in ATK_ABILITIES:
        ab = ATK_ABILITIES[atk_ability]
        if ab.get("stage") == "power":
            should_apply = True
            if ab.get("weather") and weather != ab["weather"]:
                should_apply = False
            if ab.get("cond") and not check_power_condition(ab["cond"], move_name, move_type, effective_power):
                should_apply = False
            if should_apply:
                effective_power = int(effective_power * ab["mult"])

    # 3c. 持ち物威力補正 (タイプ強化)
    if atk_item and atk_item in TYPE_BOOST_ITEMS:
        if TYPE_BOOST_ITEMS[atk_item] == move_type:
            effective_power = round5(effective_power * 4096, 4915) // 4096 if effective_power > 0 else effective_power
            # 簡易: 1.2倍
            effective_power = int(move_power * 1.2) if atk_item in TYPE_BOOST_ITEMS and TYPE_BOOST_ITEMS[atk_item] == move_type else effective_power

    # あついしぼう等のタイプ耐性を威力に反映
    if type_resist_mult != 1.0:
        effective_power = max(1, int(effective_power * type_resist_mult))

    # --- 4. 基礎ダメージ ---
    inner = 22 * effective_power * atk_stat // def_stat
    damage_base = inner // 50 + 2

    # --- タイプ相性 ---
    eff1, eff2, total_eff = calc_type_effectiveness(chart, move_type, def_types)
    if total_eff == 0:
        print(f"error|immune|{move_type}→{'/'.join(t for t in def_types if t)}")
        return

    is_super_effective = total_eff > 1
    is_not_very_effective = total_eff < 1

    eff1_frac = Fraction(eff1).limit_denominator(16)
    eff2_frac = Fraction(eff2).limit_denominator(16) if def_types[1] else Fraction(1)

    # --- STAB判定 ---
    has_stab = move_type in stab_types
    stab_mult = 6144  # 1.5x
    if atk_ability == "てきおうりょく" and has_stab:
        stab_mult = 8192  # 2.0x
    elif tera_stab_bonus:
        stab_mult = 8192  # 2.0x

    # --- 5-16. 乱数ダメージ計算 ---
    damages = []
    for rand in range(85, 101):
        dmg = damage_base

        # 5. 天候ダメージ補正
        if weather and weather in WEATHER_DATA:
            w = WEATHER_DATA[weather]
            type_map = {"ほのお": "fire", "みず": "water"}
            weather_key = type_map.get(move_type)
            if weather_key and weather_key in w:
                dmg = round5(dmg, w[weather_key])

        # 6. フィールド補正
        if field and field in FIELD_DATA:
            fd = FIELD_DATA[field]
            if fd["type"] == move_type:
                dmg = round5(dmg, fd["mult_4096"])
            elif field == "ミスト" and move_type == "ドラゴン":
                dmg = round5(dmg, fd["mult_4096"])

        # 7. 急所
        if is_critical:
            dmg = round5(dmg, 6144)

        # 8. 乱数
        dmg = dmg * rand // 100

        # 9. STAB
        if has_stab:
            dmg = round5(dmg, stab_mult)

        # スキンボーナス (最終補正段階, 4915/4096)
        if skin_bonus:
            dmg = round5(dmg, 4915)

        # 10. タイプ相性
        dmg = dmg * eff1_frac.numerator // eff1_frac.denominator
        dmg = dmg * eff2_frac.numerator // eff2_frac.denominator

        # 12. 防御側特性最終補正
        if def_ability and def_ability in DEF_ABILITIES:
            ab = DEF_ABILITIES[def_ability]
            applied = False
            if ab.get("stage") == "final":
                should_apply = True
                cond = ab.get("cond")
                if cond == "super_effective" and not is_super_effective:
                    should_apply = False
                if cond == "special" and not is_special:
                    should_apply = False
                if cond == "contact" and move_name not in CONTACT_MOVES:
                    should_apply = False
                if should_apply:
                    dmg = round5(dmg, ab["mult_4096"])
                    applied = True
            elif ab.get("stage") == "compound" and not applied:
                for eff in ab["effects"]:
                    if eff.get("stage") == "final":
                        should_apply = True
                        cond = eff.get("cond")
                        if cond == "super_effective" and not is_super_effective:
                            should_apply = False
                        if cond == "special" and not is_special:
                            should_apply = False
                        if cond == "contact" and move_name not in CONTACT_MOVES:
                            should_apply = False
                        if cond == "fire_type" and move_type != "ほのお":
                            should_apply = False
                        if should_apply:
                            dmg = round5(dmg, eff["mult_4096"])

        # 13. 攻撃側特性最終補正
        if atk_ability and atk_ability in ATK_ABILITIES:
            ab = ATK_ABILITIES[atk_ability]
            if ab.get("stage") == "final":
                should_apply = True
                cond = ab.get("cond")
                if cond == "electric_type" and move_type != "でんき":
                    should_apply = False
                if cond == "dragon_type" and move_type != "ドラゴン":
                    should_apply = False
                if cond == "steel_type" and move_type != "はがね":
                    should_apply = False
                if should_apply:
                    dmg = round5(dmg, ab["mult_4096"])

        # 14. いろめがね
        if atk_ability == "いろめがね" and is_not_very_effective:
            dmg = dmg * 2

        # 15. 持ち物最終補正
        if atk_item and atk_item in ATK_ITEMS:
            it = ATK_ITEMS[atk_item]
            if it.get("stage") == "final":
                should_apply = True
                cond = it.get("cond")
                if cond == "super_effective" and not is_super_effective:
                    should_apply = False
                if cond == "physical" and not is_physical:
                    should_apply = False
                if cond == "special" and not is_special:
                    should_apply = False
                if should_apply:
                    dmg = round5(dmg, it["mult_4096"])

        # 半減きのみ
        if def_item and def_item in RESIST_BERRIES:
            berry_type = RESIST_BERRIES[def_item]
            if berry_type == move_type:
                if def_item == "ホズのみ" or is_super_effective:
                    dmg = round5(dmg, 2048)

        # 16. 最低1ダメージ
        if dmg < 1:
            dmg = 1

        damages.append(dmg)

    # --- 出力 ---
    def fmt_types(types):
        return "/".join(t for t in types if t)

    atk_types_str = fmt_types(atk["types"])
    def_types_str = fmt_types([t for t in dfn["types"] if t])

    print("=== DAMAGE CALC RESULT ===")
    print(f"attacker|{atk['name']}|{atk_types_str}|{atk_stat_name}:{atk_base_stat}→{atk_stat}")
    print(f"defender|{dfn['name']}|{def_types_str}|HP:{def_base_hp}→{def_hp}|{def_stat_name}:{def_base_stat}→{def_stat}")
    print(f"move|{move_name}|{move_type}|{move_category}|{move_power}")

    mod_parts = []
    if atk_ability: mod_parts.append(f"atk_ability:{atk_ability}")
    if def_ability: mod_parts.append(f"def_ability:{def_ability}")
    if atk_item: mod_parts.append(f"atk_item:{atk_item}")
    if def_item: mod_parts.append(f"def_item:{def_item}")
    if weather: mod_parts.append(f"weather:{weather}")
    if field: mod_parts.append(f"field:{field}")
    if tera_type: mod_parts.append(f"tera:{tera_type}")
    if is_critical: mod_parts.append("critical:yes")
    if mod_parts:
        print(f"modifiers|{'|'.join(mod_parts)}")

    stab_label = f"yes|{stab_mult/4096:.1f}x" if has_stab else "no"
    print(f"stab|{stab_label}")
    print(f"type_effectiveness|{total_eff}x")

    rands = list(range(85, 101))
    pcts = [d / def_hp * 100 for d in damages]
    print("label|" + "|".join(str(r) for r in rands))
    print("damage|" + "|".join(str(d) for d in damages))
    print("percent|" + "|".join(f"{p:.1f}%" for p in pcts))

    min_d, max_d = damages[0], damages[15]
    min_pct = min_d / def_hp * 100
    max_pct = max_d / def_hp * 100
    print(f"summary|{min_d}~{max_d}|{min_pct:.1f}%~{max_pct:.1f}%")

    for n in range(1, 5):
        ko_count = sum(1 for d in damages if d * n >= def_hp)
        if ko_count == 16:
            print(f"ko|確定{n}発")
            break
        elif ko_count > 0:
            print(f"ko|乱数{n}発({ko_count}/16)")
            break
    else:
        print("ko|5発以上")


if __name__ == "__main__":
    main()
