# メタ上位指定フォーマット

`y matrix` サブコマンドで使用する、想定メタ上位ポケモンの記述フォーマット。

## YAML 形式（推奨）

```yaml
regulation: champions_M-A      # pkdx の --version / --regulation に渡す値
meta:
  - name: "ハバタクカミ"
    ability: "こだいかっせい"
    item: "ブーストエナジー"
    tera: "フェアリー"
    nature: "おくびょう"
    moves:
      - "ムーンフォース"
      - "シャドーボール"
      - "10まんボルト"
      - "みちづれ"
    ev_or_sp: { H: 4, C: 32, S: 32 }   # Champions は SP、従来版は EV

  - name: "カイリュー"
    ability: "マルチスケイル"
    item: "こだわりハチマキ"
    tera: "ノーマル"
    nature: "いじっぱり"
    moves:
      - "しんそく"
      - "じしん"
      - "げきりん"
      - "アイアンヘッド"
    ev_or_sp: { H: 32, A: 32, S: 2 }
```

## 簡易形式（最小）

レギュレーションとメタ相手の名前・想定技のみでも動作する。詳細が省略された場合はデフォルト（最大投資・特性未指定）で計算する。

```yaml
regulation: champions_M-A
meta:
  - name: "ハバタクカミ"
    moves: ["ムーンフォース", "シャドーボール", "10まんボルト", "みちづれ"]
  - name: "カイリュー"
    moves: ["しんそく", "じしん", "げきりん", "アイアンヘッド"]
```

## 注意

- **メタ上位の情報は本ツール側で自動取得しない**。ユーザーが環境を反映したリストを指定する。
- レギュレーション外のポケモンが含まれる場合、pkdx 側でエラーとなる（フォーマットチェック）。
- `ev_or_sp` が未指定の場合、Champions では SP=32 特化、従来では EV=252/IV=31 を仮定する。
- `tera` 未指定なら非テラス計算。

## pkdx 側での利用

このテンプレートから読み取った各フィールドは `pkdx damage` のオプションに直接マップされる:

| テンプレ | pkdx オプション |
|---------|---------------|
| ability | `--atk-ability` / `--def-ability` |
| item | `--atk-item` / `--def-item` |
| tera | `--tera-type` |
| nature | `--atk-nature` / `--def-nature` |
| regulation | `--regulation` |
| regulation のプレフィックス | `--version` |
