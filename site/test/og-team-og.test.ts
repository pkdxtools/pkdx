import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { resolve } from 'node:path';
import { clearFontCache } from '../src/lib/og/fonts.ts';
import { buildTeamOgNode, renderTeamOg, type TeamOgInput } from '../src/lib/og/team-og.ts';

const FONT_DIR = resolve(process.cwd(), 'assets/fonts');
// Minimal 1x1 PNG (valid signature + IHDR) as a data URL.
const TINY_PNG_DATA_URL =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

beforeEach(() => {
  process.env.OG_FONT_DIR = FONT_DIR;
  clearFontCache();
});

afterEach(() => {
  delete process.env.OG_FONT_DIR;
  clearFontCache();
});

const baseInput: TeamOgInput = {
  title: 'カバルドン軸 受けループ',
  battleFormat: 'singles',
  mechanics: 'Champions M-A',
  date: new Date('2026-04-22T00:00:00Z'),
  siteName: 'pkdx',
  axisImageDataUrl: TINY_PNG_DATA_URL,
  axisTypes: ['じめん', 'いわ'],
};

function nodeJson(input: TeamOgInput): string {
  return JSON.stringify(buildTeamOgNode(input));
}

describe('buildTeamOgNode', () => {
  it('includes site name, title, format label, mechanics, and date', () => {
    const json = nodeJson(baseInput);
    expect(json).toContain('pkdx');
    expect(json).toContain('カバルドン軸 受けループ');
    expect(json).toContain('シングル');
    expect(json).toContain('Champions M-A');
    expect(json).toContain('2026-04-22');
  });

  it('appends regulation to the meta line when provided', () => {
    const json = nodeJson({ ...baseInput, regulation: 'H' });
    expect(json).toContain('シングル · Champions M-A · H');
  });

  it('omits regulation from meta line when not provided', () => {
    const json = nodeJson({ ...baseInput, regulation: undefined });
    expect(json).toContain('シングル · Champions M-A');
    expect(json).not.toContain('· ·');
  });

  it('uses "ダブル" label for doubles', () => {
    const json = nodeJson({ ...baseInput, battleFormat: 'doubles' });
    expect(json).toContain('ダブル');
    expect(json).not.toContain('シングル');
  });

  it('renders axis pokemon image with opacity 0.7 and negative left offset', () => {
    const node = buildTeamOgNode(baseInput);
    const json = JSON.stringify(node);
    // <img> child present with the data URL as src
    expect(json).toContain('"type":"img"');
    expect(json).toContain(TINY_PNG_DATA_URL);
    // Style: opacity 0.7 and negative left (bleeds off left edge)
    expect(json).toContain('"opacity":0.7');
    expect(json).toContain('"left":-150');
    // top は顔見切れ防止のため中央寄せ(-135)から下シフトしている。負値であることで
    // 画像がキャンバス上端からはみ出して右ペインに対して BG を敷く構図が成立する。
    expect(json).toMatch(/"top":-\d+/);
    expect(json).toContain('"width":900');
    expect(json).toContain('"height":900');
  });

  it('falls back to solid #1a1a1a background when axis image is null AND types are empty', () => {
    const node = buildTeamOgNode({ ...baseInput, axisImageDataUrl: null, axisTypes: [] });
    const json = JSON.stringify(node);
    expect(json).not.toContain('"type":"img"');
    expect(json.toLowerCase()).toContain('#1a1a1a');
  });

  it('uses 135deg type gradient as background when axis types are provided', () => {
    const node = buildTeamOgNode({ ...baseInput, axisTypes: ['ドラゴン', 'じめん'] });
    const json = JSON.stringify(node);
    expect(json).toContain('linear-gradient(135deg');
    // primary type: ドラゴン = #454ba6, secondary: じめん = #916d3c
    expect(json.toLowerCase()).toContain('#454ba6');
    expect(json.toLowerCase()).toContain('#916d3c');
  });

  it('does NOT include axis pokemon name / type / ability / item / nature', () => {
    // negative assertion — information-design regression check.
    // title には軸名が入るのが普通なので、ここだけは title を中立的な構築名にして、
    // 実装が「うっかり ability/item/nature/types を埋め込んでいないか」を検証する
    const neutralTitle = '受けループ構築メモ';
    const json = nodeJson({ ...baseInput, title: neutralTitle });
    expect(json).not.toContain('カバルドン'); // axis name
    expect(json).not.toContain('じめん'); // type
    expect(json).not.toContain('すなおこし'); // ability
    expect(json).not.toContain('たべのこし'); // item
    expect(json).not.toContain('わんぱく'); // nature
  });

  it('truncates excessively long titles to 60 chars with ellipsis', () => {
    const long = 'あ'.repeat(120);
    const json = nodeJson({ ...baseInput, title: long });
    expect(json).toContain(`${'あ'.repeat(59)}…`);
    expect(json).not.toContain('あ'.repeat(61));
  });
});

describe('renderTeamOg (integration)', () => {
  it('produces a 1200x630 PNG', async () => {
    const png = await renderTeamOg(baseInput);
    const buf = Buffer.from(png);
    expect(buf.subarray(0, 8)).toEqual(PNG_SIG);
    expect(buf.readUInt32BE(16)).toBe(1200);
    expect(buf.readUInt32BE(20)).toBe(630);
    expect(buf.byteLength).toBeGreaterThan(1000);
  });

  it('still produces valid PNG when axis image is null', async () => {
    const png = await renderTeamOg({ ...baseInput, axisImageDataUrl: null });
    const buf = Buffer.from(png);
    expect(buf.subarray(0, 8)).toEqual(PNG_SIG);
  });
});
