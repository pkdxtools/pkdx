import { describe, expect, it } from 'bun:test';
import { buildTypeGradient, typeColor } from '../src/lib/og/colors.ts';

describe('typeColor', () => {
  it('returns hex for known JP type name', () => {
    expect(typeColor('ドラゴン')).toBe('#454ba6');
  });
  it('returns neutral for unknown', () => {
    expect(typeColor('??')).toBe('#1a1a1a');
  });
  it('returns neutral for undefined', () => {
    expect(typeColor(undefined)).toBe('#1a1a1a');
  });
});

describe('buildTypeGradient', () => {
  it('returns neutral color when types is empty', () => {
    expect(buildTypeGradient([])).toBe('#1a1a1a');
  });

  it('emits 135deg two-color gradient for dual type', () => {
    const g = buildTypeGradient(['ドラゴン', 'じめん']);
    expect(g).toContain('linear-gradient(135deg');
    expect(g).toContain('#454ba6');
    expect(g).toContain('#916d3c');
  });

  it('emits neutral + primary for single type (uses neutral on the lower wedge)', () => {
    const g = buildTypeGradient(['ドラゴン']);
    expect(g).toContain('linear-gradient(135deg');
    expect(g).toContain('#454ba6');
    expect(g).toContain('#1a1a1a');
  });

  it('treats duplicate types as single type', () => {
    const dup = buildTypeGradient(['ほのお', 'ほのお']);
    const single = buildTypeGradient(['ほのお']);
    expect(dup).toBe(single);
  });

  it('handles empty strings gracefully', () => {
    expect(buildTypeGradient([''])).toBe('#1a1a1a');
  });
});
