# ヤーティ検証規則 (validation_rules)

Mode B (ヤーティ検証) が使用する機械的判定規則集。

**原則**: 本ルールは `doctrine.md` から蒸留したもので、`doctrine.md` の更新に追従する。source フィールドは `doctrine.md` の節番号のみを参照する（他所の文書を直接参照しない）。

---

## hard_rules（違反 → 論外）

```yaml
hard_rules:
  - id: R01
    desc: "性格は いじっぱり / ひかえめ / ゆうかん / れいせい のいずれか"
    check: pokemon.nature in ["いじっぱり", "ひかえめ", "ゆうかん", "れいせい"]
    source: "doctrine.md §2.1"

  - id: R02
    desc: "A または C に最大値投資（Champions: SP=32 / 従来: EV=252）"
    check_champions: max(pokemon.sp.A, pokemon.sp.C) == 32
    check_legacy: max(pokemon.ev.A, pokemon.ev.C) == 252
    source: "doctrine.md §2.2"
    note: "両刀（A・C 両方に極振り）は耐久が過度に下がるため不採用"

  - id: R03
    desc: "素早さ S に努力値を振らない（言い訳振り +4 まで許容）"
    check_champions: pokemon.sp.S <= 4
    check_legacy: pokemon.ev.S <= 4
    source: "doctrine.md §2.2"
    note: "Champions SP は 66 ぴったり配分可能なため言い訳振り自体が発生しない。歴史的例外（第五世代 S135 ヤティ等）を除く"

  - id: R04
    desc: "技構成に先制技（priority > 0）を含まない"
    check: all(move.priority <= 0 for move in pokemon.moves)
    source: "doctrine.md §2.3"
    note_exception: |
      例外: 先制技が「そのポケモンが覚える特定タイプの最大打点」になる場合のみ許容
      （例: であいがしらを最大打点として採用するケース）。ただし ふいうち は
      無償降臨を許すため絶対にありえない。

  - id: R05
    desc: "技構成に補助技（category == 変化）を含まない"
    check: all(move.category != "変化" for move in pokemon.moves)
    source: "doctrine.md §2.3"

  - id: R06
    desc: "タイプ一致の攻撃技を最低 1 つ以上含む"
    check: any(move.type in pokemon.types and move.category != "変化" for move in pokemon.moves)
    source: "doctrine.md §2.3"
    note: "とんぼがえり / ボルトチェンジ は一致でなくても許容される"

  - id: R07
    desc: "火力上昇アイテム、または専用アイテムを保持（ヤトリック向け基準）"
    allowed_items:
      - こだわりハチマキ
      - こだわりメガネ
      - いのちのたま
      - たつじんのおび
      - ちからのハチマキ
      - ものしりメガネ
      - 各タイププレート
      - こころのしずく     # ラティオス/ラティアス専用
      - ふといホネ         # アローラガラガラ専用
      - かまどのめん / いどのめん / いしずえのめん  # オーガポン専用
    check: pokemon.item in allowed_items
    source: "doctrine.md §2.4"
    note: "違反は hard ではなく soft_rules S06 で扱う。ここでは情報目的で列挙"

  - id: R08
    desc: "ふいうち は絶対に採用しない（ヤロテスタントでも NG）"
    check: "ふいうち" not in [m.name for m in pokemon.moves]
    source: "doctrine.md §2.3"
    note: "無償降臨を許すため、最大打点でも採用不可"
```

## soft_rules（違反 → ヤロテスタント判定）

```yaml
soft_rules:
  - id: S01
    desc: "連続技（タネマシンガン・ロックブラスト 等）の採用"
    check: any(move.is_multi_hit for move in pokemon.moves)
    source: "doctrine.md §3.2"
    note: "環境因子（身代わり・襷・マルチスケイル対策）として容認"

  - id: S02
    desc: "音技（はかいこうせん音版・りゅうのはどう 等）の採用"
    check: any(move.is_sound for move in pokemon.moves)
    source: "doctrine.md §3.2"

  - id: S03
    desc: "ねごと の採用"
    check: "ねごと" in [m.name for m in pokemon.moves]
    source: "doctrine.md §3.2"
    note: "催眠対策としてヤロテスタントで容認"

  - id: S04
    desc: "ゴツゴツメット を保持"
    check: pokemon.item == "ゴツゴツメット"
    source: "doctrine.md §2.4"
    note: "ヤトリックでは NG、ヤロテスタントで容認"

  - id: S05
    desc: "とつげきチョッキ を保持"
    check: pokemon.item == "とつげきチョッキ"
    source: "doctrine.md §2.4"
    note: |
      ヤトリックでは NG。ヤロテスタント内でも容認派と否定派で分裂。
      「チョッキヤケモン」（チョッキ込みでしか役割を持てないヤケモン）に限り
      一部で容認。超火力ヤケモンへの採用は不適。

  - id: S06
    desc: "火力上昇アイテムを持たない（R07 の逆）"
    check: pokemon.item not in R07.allowed_items
    source: "doctrine.md §2.4"
    note: "S04/S05 も満たす場合はそちらが優先して判定される"
```

## 判定フロー

```
1. 各メンバーに hard_rules (R01-R08) を順に適用
   - いずれか違反 → そのメンバーは「論外」、違反規則 ID を記録

2. hard_rules 全通過メンバーに soft_rules (S01-S06) を適用
   - すべて通過 → 「ヤトリック」
   - 一部違反 → 「ヤロテスタント」、違反 soft_rules ID を記録

3. チーム総合判定:
   - 全員がヤトリック → チーム「ヤトリック」
   - 論外 0 かつ 1 体以上ヤロテスタント → チーム「ヤロテスタント」
   - 論外 1 体以上 → チーム「論外」
```

## 修正提案テンプレート

| 違反規則 | 修正提案テンプレート |
|---------|---------------------|
| R01 | `性格を いじっぱり/ひかえめ/ゆうかん/れいせい のいずれかに変更（現: {nature}）` |
| R02 | `A または C に最大値投資（現: A={A}, C={C} 最大値={max}）` |
| R03 | `S への努力値/SP を 4 以下に抑え、余剰を HBD に振り直す（現: S={S}）` |
| R04 | `先制技 {move.name} を攻撃技に差し替え（priority={move.priority}）` |
| R05 | `補助技 {move.name} を攻撃技に差し替え` |
| R06 | `タイプ一致攻撃技を最低 1 つ採用（現ポケモンタイプ: {types}）` |
| R07 | `持ち物を火力上昇アイテムへ変更（現: {item}）` |
| R08 | `ふいうち は絶対に採用しない。別の技に差し替え` |
| S01 | `連続技 {move.name} はヤロテスタント扱い。環境因子がなければ一致最大火力技推奨` |
| S02 | `音技 {move.name} はヤロテスタント扱い` |
| S03 | `ねごと はヤロテスタント扱い（催眠対策として容認）` |
| S04 | `ゴツゴツメット はヤロテスタント扱い` |
| S05 | `とつげきチョッキ はヤロテスタント扱い（チョッキヤケモン限定で容認、超火力ヤケモンには不適）` |
| S06 | `火力上昇アイテムへの変更を推奨。現状 {item} はヤロテスタント扱い` |

---

## 内部参照

- `doctrine.md` — 本規則の原典。違反時の説教・根拠はここを参照する。
- `logical_grammar.md` — 違反通告を Mode A (ロジカル語法) で返す際の文体規範。
