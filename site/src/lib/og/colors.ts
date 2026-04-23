// タイプカラー定義。値は site/src/styles/global.css の --type-* と同期。
// satori は CSS 変数を解決しないため、hex リテラルで持つ必要がある。
export const TYPE_HEX_MAP: Record<string, string> = {
  ノーマル: '#aea886',
  ほのお: '#f45c19',
  みず: '#4a96d6',
  でんき: '#eaa317',
  くさ: '#28b25c',
  こおり: '#45a9c0',
  かくとう: '#9a3d3e',
  どく: '#8f5b98',
  じめん: '#916d3c',
  ひこう: '#7e9ecf',
  エスパー: '#d56d8b',
  むし: '#989001',
  いわ: '#878052',
  ゴースト: '#555fa4',
  ドラゴン: '#454ba6',
  あく: '#2f2a28',
  はがね: '#9b9b9b',
  フェアリー: '#ffbbff',
};

const NEUTRAL = '#1a1a1a';

export function typeColor(t: string | undefined): string {
  if (!t) return NEUTRAL;
  return TYPE_HEX_MAP[t] ?? NEUTRAL;
}

// MemberCard.astro の `.member-card::before` と同じ 135deg グラデを hex で組む。
// dual:   135deg, primary 0 30%, secondary 70% 100%
// single: 135deg, transparent 10% 30%, primary 70% 100%  (→ satori で transparent
//         は扱いが曖昧なので NEUTRAL に置換して 「下三角だけ色が乗る」見た目を再現)
export function buildTypeGradient(types: string[]): string {
  const clean = types.filter((t): t is string => typeof t === 'string' && t.length > 0);
  if (clean.length === 0) {
    return NEUTRAL;
  }
  if (clean.length >= 2 && clean[0] !== clean[1]) {
    const a = typeColor(clean[0]);
    const b = typeColor(clean[1]);
    return `linear-gradient(135deg, ${a} 0%, ${a} 30%, ${b} 70%, ${b} 100%)`;
  }
  const p = typeColor(clean[0]);
  return `linear-gradient(135deg, ${NEUTRAL} 10%, ${NEUTRAL} 30%, ${p} 70%, ${p} 100%)`;
}
