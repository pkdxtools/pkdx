# 009_yawn_ailment_name — あくびは仕様上「遅延ねむり」なので DrowsyKind に
# 対応させる。008 では ailment_ja="ねむり" として入れていたが、pkdx 側の
# `status_kind_from_jp` が "あくび" を `DrowsyKind` にマップするため、DB 値も
# "あくび" に書き換える。
#
# 冪等: UPDATE なので複数回実行されても結果は同じ。

db.execute(
  "UPDATE move_meta SET ailment_ja = 'あくび' WHERE name_ja = 'あくび'"
)

puts "    yawn ailment_ja normalized to 'あくび'"
