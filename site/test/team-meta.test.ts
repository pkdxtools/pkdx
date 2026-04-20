import { describe, expect, it } from 'bun:test';
import { parseTeamMeta } from '../src/lib/team-meta';

describe('parseTeamMeta', () => {
  it('returns null for null input', () => {
    expect(parseTeamMeta(null)).toBeNull();
  });

  it('returns null for empty input', () => {
    expect(parseTeamMeta('')).toBeNull();
  });

  it('returns null for invalid JSON', () => {
    expect(parseTeamMeta('not json')).toBeNull();
  });

  it('returns null for JSON array at root', () => {
    expect(parseTeamMeta('[1,2,3]')).toBeNull();
  });

  it('accepts empty object with defaults', () => {
    const result = parseTeamMeta('{}');
    expect(result).not.toBeNull();
    expect(result?.members).toEqual([]);
    expect(result?.coverage).toEqual([]);
    expect(result?.defense_matrix).toEqual([]);
    expect(result?.matchup_plans).toEqual([]);
    expect(result?.damage_calcs).toEqual([]);
  });

  it('parses a minimal team meta with a single member', () => {
    const input = JSON.stringify({
      battle_format: 'singles',
      mechanics: 'テラスタル',
      version: 'sv',
      members: [
        {
          name: 'ガブリアス',
          types: ['ドラゴン', 'じめん'],
          base_stats: { h: 108, a: 130, b: 95, c: 80, d: 85, s: 102 },
          ability: 'さめはだ',
          item: 'こだわりハチマキ',
          role: 'サイクルを崩す高速物理アタッカー',
          moves: [
            { name: 'じしん', type: 'じめん', category: 'physical', power: 100 },
          ],
        },
      ],
    });
    const result = parseTeamMeta(input);
    expect(result).not.toBeNull();
    expect(result?.members).toHaveLength(1);
    expect(result?.members[0]?.name).toBe('ガブリアス');
    expect(result?.members[0]?.role).toContain('アタッカー');
  });

  it('parses damage_calcs with rolls_percent', () => {
    const input = JSON.stringify({
      damage_calcs: [
        {
          title: '軸サマリ',
          attacker: { name: 'ガブリアス', level: 50 },
          defender: { name: 'ゴチルゼル', level: 50 },
          move: { name: 'じしん', type: 'じめん', category: 'physical', power: 100 },
          rolls_percent: [60.1, 61.4, 61.9, 62.4, 62.9, 63.4, 63.9, 64.5, 65.0, 65.5, 66.0, 66.5, 67.0, 67.5, 68.0, 70.1],
          min_percent: 60.1,
          max_percent: 70.1,
          guaranteed_hits: 2,
        },
      ],
    });
    const result = parseTeamMeta(input);
    expect(result?.damage_calcs).toHaveLength(1);
    expect(result?.damage_calcs[0]?.title).toBe('軸サマリ');
    expect(result?.damage_calcs[0]?.rolls_percent).toHaveLength(16);
    expect(result?.damage_calcs[0]?.guaranteed_hits).toBe(2);
  });

  it('tolerates unknown keys without failing', () => {
    const input = JSON.stringify({
      members: [],
      future_field: 'not-validated-yet',
    });
    const result = parseTeamMeta(input);
    expect(result).not.toBeNull();
    expect(result?.members).toEqual([]);
  });

  it('returns null when members[].name is the wrong type', () => {
    const input = JSON.stringify({ members: [{ name: 123 }] });
    expect(parseTeamMeta(input)).toBeNull();
  });
});
