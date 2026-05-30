#!/usr/bin/env python3
"""Stop hook: ダメージ計算/タイプ相性の文脈で、エージェントの最終応答に含まれる
タイプ相性倍率の主張が `pkdx type-chart` の実出力と矛盾していないか決定論的に検証する。

なぜ必要か: LLM はツール (type-chart) が正答を返していても、テーブル外の散文で
矛盾する倍率 (例: 2x の出力に対し「4倍」) を捏造することがある。CLAUDE.md は
「タイプ相性は必ず type-chart で計算してからフィードバックする」「事実のみ返す」と
定めるが、これは非決定論的な自制に依存していた。本 hook が機械的な歯止めを与える。

判定:
  - このターンの tool 出力に type-chart 行 (`-> ...: Nx`) も damage JSON
    (`"damages":[`) も無ければ「ダメ計/相性の文脈ではない」とみなし素通り。
  - 最終応答から型相性倍率 (N ∈ {0,0.25,0.5,1,2,4} の「N倍」「Nx」) を抽出。
    1.5x (タイプ一致) や 1.3x (いのちのたま) 等は集合外なので対象にならない。
  - 抽出した倍率のうち type-chart 出力倍率集合に含まれないものがあれば exit 2 で
    停止をブロックし、再導出を強制する。type-chart 未実行で倍率を書いた場合も
    (出力集合が空なので) ブロックされる。

fail-open: 例外時・python欠如時・stop_hook_active 再入時は exit 0 で素通り
(ガードが壊れて作業を止めることがないようにする)。
"""

import sys
import json
import re

# タイプ相性として実在する倍率 (テラ一致 1.5x / 道具 1.3x 等を除外するための許可集合)
VALID_MULTS = {0.0, 0.25, 0.5, 1.0, 2.0, 4.0}

# type-chart 出力行: "こおり -> ドラゴン/ひこう: 4x"
TYPE_CHART_LINE = re.compile(r"->\s*[^\n:]+:\s*([0-9]+(?:\.[0-9]+)?)x", re.IGNORECASE)
# 最終応答中の倍率主張: "4倍" / "2x" / "0.5x" / "4×"
CLAIM_BAI = re.compile(r"([0-9]+(?:\.[0-9]+)?)\s*倍")
CLAIM_X = re.compile(r"([0-9]+(?:\.[0-9]+)?)\s*[xX×]")
# damage CLI の JSON 出力マーカー
DAMAGE_MARKER = '"damages":['


def to_mult(s):
    try:
        return float(s)
    except ValueError:
        return None


def is_human_turn_start(ev):
    """tool_result ではない生のユーザー入力か (ターン境界の判定)。"""
    if ev.get("type") != "user":
        return False
    content = ev.get("message", {}).get("content")
    if isinstance(content, str):
        return True
    if isinstance(content, list):
        return not any(
            isinstance(b, dict) and b.get("type") == "tool_result" for b in content
        )
    return False


def collect_tool_result_text(ev, sink):
    if ev.get("type") != "user":
        return
    content = ev.get("message", {}).get("content")
    if not isinstance(content, list):
        return
    for b in content:
        if not (isinstance(b, dict) and b.get("type") == "tool_result"):
            continue
        rc = b.get("content")
        if isinstance(rc, str):
            sink.append(rc)
        elif isinstance(rc, list):
            for x in rc:
                if isinstance(x, dict) and x.get("type") == "text":
                    sink.append(x.get("text", ""))


def assistant_text(ev):
    if ev.get("type") != "assistant":
        return ""
    content = ev.get("message", {}).get("content")
    if not isinstance(content, list):
        return ""
    return "".join(
        b.get("text", "")
        for b in content
        if isinstance(b, dict) and b.get("type") == "text"
    )


def extract_claims(text):
    found = set()
    for rx in (CLAIM_BAI, CLAIM_X):
        for m in rx.finditer(text):
            v = to_mult(m.group(1))
            if v is not None and v in VALID_MULTS:
                found.add(v)
    return found


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        return 0

    # Stop hook 起因の再入は素通り (無限ループ防止)
    if payload.get("stop_hook_active"):
        return 0

    tpath = payload.get("transcript_path")
    if not tpath:
        return 0

    try:
        with open(tpath, encoding="utf-8") as f:
            events = [json.loads(line) for line in f if line.strip()]
    except Exception:
        return 0
    if not events:
        return 0

    # 最後の生ユーザー入力以降を「このターン」とする
    start = 0
    for i, ev in enumerate(events):
        if is_human_turn_start(ev):
            start = i
    turn = events[start + 1 :]
    if not turn:
        return 0

    tool_text_parts = []
    final_text = ""
    for ev in turn:
        collect_tool_result_text(ev, tool_text_parts)
        t = assistant_text(ev)
        if t.strip():
            final_text = t  # 最後の非空 assistant text = 最終応答
    tool_text = "\n".join(tool_text_parts)

    chart_mults = {
        to_mult(m.group(1))
        for m in TYPE_CHART_LINE.finditer(tool_text)
        if to_mult(m.group(1)) is not None
    }
    damage_context = (DAMAGE_MARKER in tool_text) or bool(chart_mults)
    if not damage_context:
        return 0  # ダメ計/相性の文脈ではない

    claims = extract_claims(final_text)
    if not claims:
        return 0

    unsupported = sorted(claims - chart_mults)
    if not unsupported:
        return 0

    chart_disp = (
        ", ".join(f"{m:g}x" for m in sorted(chart_mults)) if chart_mults else "(なし)"
    )
    bad_disp = ", ".join(f"{m:g}x" for m in unsupported)
    sys.stderr.write(
        "タイプ相性の捏造ガード: 最終応答に type-chart 出力で裏付けられない倍率の主張があります。\n"
        f"  応答中の未裏付け倍率: {bad_disp}\n"
        f"  このターンの type-chart 実出力: {chart_disp}\n"
        "対処: 当該タイプの組み合わせに対し `pkdx type-chart <技タイプ> <防御タイプ(,区切り)>` を\n"
        "実行し、その出力倍率のみを使って記述を訂正してください。type-chart で確認できない倍率や\n"
        "倍率に基づく相性評価をユーザーへ提示してはいけません (CLAUDE.md #5)。\n"
    )
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # ガード自体の失敗で作業を止めない
        sys.exit(0)
