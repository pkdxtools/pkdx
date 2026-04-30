---
regulation: M-A
version: champions
generated: false
last_updated: 2026-04-30
sources:
  - https://github.com/pkdxtools/pkdx/blob/main/pkdx/src/db/regulation.mbt
  - https://www.pokemon-champions.com/
description: |
  Champions レギュレーション M-A の利用可能ポケモン・技プールの SSoT。
  ポケモン globalNo は `pkdx/src/db/regulation.mbt::ma_global_nos()` を出典とする。
  技プールは champions_learnset テーブルの実データ + 漏れ補完用に手動追加した連続技。
  本ファイルは Phase 0-B `pkdx audit champions-ma` および Phase 0-C `m014_champions_ma_completion`
  migration の入力として参照される。
---

# Champions M-A Regulation Pool

## Pokemons

186 entries. globalNo と日本語名 (base form)。各ポケモンの form 別 (メガ進化 / リージョンフォーム) は `local_pokedex` / `pokedex_name` から派生。

```yaml
pokemons:
  - { globalNo: "0003", name: "フシギバナ" }
  - { globalNo: "0006", name: "リザードン" }
  - { globalNo: "0009", name: "カメックス" }
  - { globalNo: "0015", name: "スピアー" }
  - { globalNo: "0018", name: "ピジョット" }
  - { globalNo: "0024", name: "アーボック" }
  - { globalNo: "0025", name: "ピカチュウ" }
  - { globalNo: "0026", name: "ライチュウ" }
  - { globalNo: "0036", name: "ピクシー" }
  - { globalNo: "0038", name: "キュウコン" }
  - { globalNo: "0059", name: "ウインディ" }
  - { globalNo: "0065", name: "フーディン" }
  - { globalNo: "0068", name: "カイリキー" }
  - { globalNo: "0071", name: "ウツボット" }
  - { globalNo: "0080", name: "ヤドラン" }
  - { globalNo: "0094", name: "ゲンガー" }
  - { globalNo: "0115", name: "ガルーラ" }
  - { globalNo: "0121", name: "スターミー" }
  - { globalNo: "0127", name: "カイロス" }
  - { globalNo: "0128", name: "ケンタロス" }
  - { globalNo: "0130", name: "ギャラドス" }
  - { globalNo: "0132", name: "メタモン" }
  - { globalNo: "0134", name: "シャワーズ" }
  - { globalNo: "0135", name: "サンダース" }
  - { globalNo: "0136", name: "ブースター" }
  - { globalNo: "0142", name: "プテラ" }
  - { globalNo: "0143", name: "カビゴン" }
  - { globalNo: "0149", name: "カイリュー" }
  - { globalNo: "0154", name: "メガニウム" }
  - { globalNo: "0157", name: "バクフーン" }
  - { globalNo: "0160", name: "オーダイル" }
  - { globalNo: "0168", name: "アリアドス" }
  - { globalNo: "0181", name: "デンリュウ" }
  - { globalNo: "0184", name: "マリルリ" }
  - { globalNo: "0186", name: "ニョロトノ" }
  - { globalNo: "0196", name: "エーフィ" }
  - { globalNo: "0197", name: "ブラッキー" }
  - { globalNo: "0199", name: "ヤドキング" }
  - { globalNo: "0205", name: "フォレトス" }
  - { globalNo: "0208", name: "ハガネール" }
  - { globalNo: "0212", name: "ハッサム" }
  - { globalNo: "0214", name: "ヘラクロス" }
  - { globalNo: "0227", name: "エアームド" }
  - { globalNo: "0229", name: "ヘルガー" }
  - { globalNo: "0248", name: "バンギラス" }
  - { globalNo: "0279", name: "ペリッパー" }
  - { globalNo: "0282", name: "サーナイト" }
  - { globalNo: "0302", name: "ヤミラミ" }
  - { globalNo: "0306", name: "ボスゴドラ" }
  - { globalNo: "0308", name: "チャーレム" }
  - { globalNo: "0310", name: "ライボルト" }
  - { globalNo: "0319", name: "サメハダー" }
  - { globalNo: "0323", name: "バクーダ" }
  - { globalNo: "0324", name: "コータス" }
  - { globalNo: "0334", name: "チルタリス" }
  - { globalNo: "0350", name: "ミロカロス" }
  - { globalNo: "0351", name: "ポワルン" }
  - { globalNo: "0354", name: "ジュペッタ" }
  - { globalNo: "0358", name: "チリーン" }
  - { globalNo: "0359", name: "アブソル" }
  - { globalNo: "0362", name: "オニゴーリ" }
  - { globalNo: "0389", name: "ドダイトス" }
  - { globalNo: "0392", name: "ゴウカザル" }
  - { globalNo: "0395", name: "エンペルト" }
  - { globalNo: "0405", name: "レントラー" }
  - { globalNo: "0407", name: "ロズレイド" }
  - { globalNo: "0409", name: "ラムパルド" }
  - { globalNo: "0411", name: "トリデプス" }
  - { globalNo: "0428", name: "ミミロップ" }
  - { globalNo: "0442", name: "ミカルゲ" }
  - { globalNo: "0445", name: "ガブリアス" }
  - { globalNo: "0448", name: "ルカリオ" }
  - { globalNo: "0450", name: "カバルドン" }
  - { globalNo: "0454", name: "ドクロッグ" }
  - { globalNo: "0460", name: "ユキノオー" }
  - { globalNo: "0461", name: "マニューラ" }
  - { globalNo: "0464", name: "ドサイドン" }
  - { globalNo: "0470", name: "リーフィア" }
  - { globalNo: "0471", name: "グレイシア" }
  - { globalNo: "0472", name: "グライオン" }
  - { globalNo: "0473", name: "マンムー" }
  - { globalNo: "0475", name: "エルレイド" }
  - { globalNo: "0478", name: "ユキメノコ" }
  - { globalNo: "0479", name: "ロトム" }
  - { globalNo: "0497", name: "ジャローダ" }
  - { globalNo: "0500", name: "エンブオー" }
  - { globalNo: "0503", name: "ダイケンキ" }
  - { globalNo: "0505", name: "ミルホッグ" }
  - { globalNo: "0510", name: "レパルダス" }
  - { globalNo: "0512", name: "ヤナッキー" }
  - { globalNo: "0514", name: "バオッキー" }
  - { globalNo: "0516", name: "ヒヤッキー" }
  - { globalNo: "0530", name: "ドリュウズ" }
  - { globalNo: "0531", name: "タブンネ" }
  - { globalNo: "0534", name: "ローブシン" }
  - { globalNo: "0547", name: "エルフーン" }
  - { globalNo: "0553", name: "ワルビアル" }
  - { globalNo: "0563", name: "デスカーン" }
  - { globalNo: "0569", name: "ダストダス" }
  - { globalNo: "0571", name: "ゾロアーク" }
  - { globalNo: "0579", name: "ランクルス" }
  - { globalNo: "0584", name: "バイバニラ" }
  - { globalNo: "0587", name: "エモンガ" }
  - { globalNo: "0609", name: "シャンデラ" }
  - { globalNo: "0614", name: "ツンベアー" }
  - { globalNo: "0618", name: "マッギョ" }
  - { globalNo: "0623", name: "ゴルーグ" }
  - { globalNo: "0635", name: "サザンドラ" }
  - { globalNo: "0637", name: "ウルガモス" }
  - { globalNo: "0652", name: "ブリガロン" }
  - { globalNo: "0655", name: "マフォクシー" }
  - { globalNo: "0658", name: "ゲッコウガ" }
  - { globalNo: "0660", name: "ホルード" }
  - { globalNo: "0663", name: "ファイアロー" }
  - { globalNo: "0666", name: "ビビヨン" }
  - { globalNo: "0670", name: "フラエッテ" }
  - { globalNo: "0671", name: "フラージェス" }
  - { globalNo: "0675", name: "ゴロンダ" }
  - { globalNo: "0676", name: "トリミアン" }
  - { globalNo: "0678", name: "ニャオニクス" }
  - { globalNo: "0681", name: "ギルガルド" }
  - { globalNo: "0683", name: "フレフワン" }
  - { globalNo: "0685", name: "ペロリーム" }
  - { globalNo: "0693", name: "ブロスター" }
  - { globalNo: "0695", name: "エレザード" }
  - { globalNo: "0697", name: "ガチゴラス" }
  - { globalNo: "0699", name: "アマルルガ" }
  - { globalNo: "0700", name: "ニンフィア" }
  - { globalNo: "0701", name: "ルチャブル" }
  - { globalNo: "0702", name: "デデンネ" }
  - { globalNo: "0706", name: "ヌメルゴン" }
  - { globalNo: "0707", name: "クレッフィ" }
  - { globalNo: "0709", name: "オーロット" }
  - { globalNo: "0711", name: "パンプジン" }
  - { globalNo: "0713", name: "クレベース" }
  - { globalNo: "0715", name: "オンバーン" }
  - { globalNo: "0724", name: "ジュナイパー" }
  - { globalNo: "0727", name: "ガオガエン" }
  - { globalNo: "0730", name: "アシレーヌ" }
  - { globalNo: "0733", name: "ドデカバシ" }
  - { globalNo: "0740", name: "ケケンカニ" }
  - { globalNo: "0745", name: "ルガルガン" }
  - { globalNo: "0748", name: "ドヒドイデ" }
  - { globalNo: "0750", name: "バンバドロ" }
  - { globalNo: "0752", name: "オニシズクモ" }
  - { globalNo: "0758", name: "エンニュート" }
  - { globalNo: "0763", name: "アマージョ" }
  - { globalNo: "0765", name: "ヤレユータン" }
  - { globalNo: "0766", name: "ナゲツケサル" }
  - { globalNo: "0778", name: "ミミッキュ" }
  - { globalNo: "0780", name: "ジジーロン" }
  - { globalNo: "0784", name: "ジャラランガ" }
  - { globalNo: "0823", name: "アーマーガア" }
  - { globalNo: "0841", name: "アップリュー" }
  - { globalNo: "0842", name: "タルップル" }
  - { globalNo: "0844", name: "サダイジャ" }
  - { globalNo: "0855", name: "ポットデス" }
  - { globalNo: "0858", name: "ブリムオン" }
  - { globalNo: "0866", name: "バリコオル" }
  - { globalNo: "0867", name: "デスバーン" }
  - { globalNo: "0869", name: "マホイップ" }
  - { globalNo: "0877", name: "モルペコ" }
  - { globalNo: "0887", name: "ドラパルト" }
  - { globalNo: "0899", name: "アヤシシ" }
  - { globalNo: "0900", name: "バサギリ" }
  - { globalNo: "0902", name: "イダイトウ" }
  - { globalNo: "0903", name: "オオニューラ" }
  - { globalNo: "0908", name: "マスカーニャ" }
  - { globalNo: "0911", name: "ラウドボーン" }
  - { globalNo: "0914", name: "ウェーニバル" }
  - { globalNo: "0925", name: "イッカネズミ" }
  - { globalNo: "0934", name: "キョジオーン" }
  - { globalNo: "0936", name: "グレンアルマ" }
  - { globalNo: "0937", name: "ソウブレイズ" }
  - { globalNo: "0939", name: "ハラバリー" }
  - { globalNo: "0952", name: "スコヴィラン" }
  - { globalNo: "0956", name: "クエスパトラ" }
  - { globalNo: "0959", name: "デカヌチャン" }
  - { globalNo: "0964", name: "イルカマン" }
  - { globalNo: "0968", name: "ミミズズ" }
  - { globalNo: "0970", name: "キラフロル" }
  - { globalNo: "0981", name: "リキキリン" }
  - { globalNo: "0983", name: "ドドゲザン" }
  - { globalNo: "1013", name: "ヤバソチャ" }
  - { globalNo: "1018", name: "ブリジュラス" }
  - { globalNo: "1019", name: "カミツオロチ" }
```

## Multi-hit Moves (Special Interest for Issue #91)

これらは payoff の chance-node leaf 展開に直接影響する技。M-A プール内のポケモンが習得可能。

```yaml
multi_hit_moves:
  - name: "ネズミざん"
    type: "PopulationBomb"
    hits: "1..10"
    move_accuracy: 90
    per_hit_continuation: 90
    learners: ["イッカネズミ"]
  - name: "トリプルアクセル"
    type: "TripleVariant"
    hits: "1..3 (per-hit 90%)"
    move_accuracy: 90
    learners: ["オオニューラ", "マニューラ", "オニゴーリ"]
  - name: "トリプルキック"
    type: "TripleVariant"
    hits: "1..3 (per-hit 90%)"
    move_accuracy: 90
    learners: ["カイリキー", "ヘラクロス"]
  - name: "ロックブラスト"
    type: "Random2to5"
    hits: "2..5 / 5 (Skill Link)"
    move_accuracy: 90
  - name: "つららばり"
    type: "Random2to5"
    hits: "2..5 / 5 (Skill Link)"
    move_accuracy: 100
  - name: "ボーンラッシュ"
    type: "Random2to5"
    hits: "2..5"
    move_accuracy: 90
  - name: "タネマシンガン"
    type: "Random2to5"
    hits: "2..5"
    move_accuracy: 100
  - name: "みだれづき"
    type: "Random2to5"
    hits: "2..5"
    move_accuracy: 85
  - name: "みずしゅりけん"
    type: "Random2to5"
    hits: "2..5"
    move_accuracy: 100
  - name: "つっぱり"
    type: "Random2to5"
    hits: "2..5"
    move_accuracy: 100
  - name: "スケイルショット"
    type: "Random2to5"
    hits: "2..5"
    move_accuracy: 90
  - name: "ミサイルばり"
    type: "Random2to5"
    hits: "2..5"
    move_accuracy: 95
  - name: "ダブルアタック"
    type: "FixedHit2"
    hits: "2"
    move_accuracy: 90
  - name: "ダブルウイング"
    type: "FixedHit2"
    hits: "2"
    move_accuracy: 90
  - name: "ドラゴンアロー"
    type: "FixedHit2"
    hits: "2"
    move_accuracy: 100
  - name: "ツインビーム"
    type: "FixedHit2"
    hits: "2"
    move_accuracy: 100
  - name: "にどげり"
    type: "FixedHit2"
    hits: "2"
    move_accuracy: 100
  - name: "すいりゅうれんだ"
    type: "FixedHit3"
    hits: "3"
    move_accuracy: 100
  - name: "トリプルダイブ"
    type: "FixedHit3"
    hits: "3"
    move_accuracy: 95
```

## Abilities

各 M-A プールポケモンが持つ特性は `local_pokedex_ability` から派生。M-A レギュ専用の制限は現時点で記録されていないため、本 SSoT は明示的なリストを保持せず DB の実データを正とする。

## Items

Champions レギュレーションで利用可能な持ち物は `champions.db::items` テーブル (m013_items 適用済) を出典とする。本 SSoT は明示的なリストを保持しない。

## Notes

- 本 SSoT は `pkdx audit champions-ma --json` の入力として使用される。
- 実装は `pkdx/src/cli/champions_audit.mbt` で SSoT yaml を parse し、`local_pokedex(version=champions)` / `champions_learnset` と突合して欠落を JSON 出力する。
- 修正は `pkdx_patch/014_champions_ma_completion/data.json` + `pkdx/src/migrate/m014_champions_ma_completion.mbt` で適用する (冪等)。
- 公式情報の URL が確定したら `frontmatter.sources` に追記する。
- 自動生成スクリプト (`scripts/generate_ma_pool.sh`) は follow-up issue として切り出し済 (frontmatter `generated: false` で明示)。
