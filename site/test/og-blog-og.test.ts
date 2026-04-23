import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { resolve } from 'node:path';
import { clearFontCache } from '../src/lib/og/fonts.ts';
import {
  buildBlogOgNode,
  pickTitleFontSize,
  renderBlogOg,
  type BlogOgInput,
} from '../src/lib/og/blog-og.ts';

const FONT_DIR = resolve(process.cwd(), 'assets/fonts');
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

beforeEach(() => {
  process.env.OG_FONT_DIR = FONT_DIR;
  clearFontCache();
});

afterEach(() => {
  delete process.env.OG_FONT_DIR;
  clearFontCache();
});

const baseInput: BlogOgInput = {
  title: 'ポケモン対戦における Nash 均衡',
  date: new Date('2026-04-22T00:00:00Z'),
  tags: ['nash', 'theory'],
  siteName: 'pkdx',
};

function nodeJson(input: BlogOgInput): string {
  return JSON.stringify(buildBlogOgNode(input));
}

describe('pickTitleFontSize', () => {
  const cases: Array<[number, number]> = [
    [1, 72],
    [10, 72],
    [15, 72],
    [16, 60],
    [25, 60],
    [30, 60],
    [31, 48],
    [60, 48],
    [120, 48],
  ];
  for (const [len, expected] of cases) {
    it(`len ${len} -> fontSize ${expected}`, () => {
      expect(pickTitleFontSize(len)).toBe(expected);
    });
  }
});

describe('buildBlogOgNode', () => {
  it('includes site name, title, date, and tags', () => {
    const json = nodeJson(baseInput);
    expect(json).toContain('pkdx');
    expect(json).toContain('ポケモン対戦における Nash 均衡');
    expect(json).toContain('2026-04-22');
    expect(json).toContain('#nash');
    expect(json).toContain('#theory');
  });

  it('uses fontSize 72 for short titles', () => {
    const json = nodeJson({ ...baseInput, title: 'あ'.repeat(10) });
    expect(json).toContain('"fontSize":72');
  });

  it('uses fontSize 48 for very long titles', () => {
    const json = nodeJson({ ...baseInput, title: 'あ'.repeat(60) });
    expect(json).toContain('"fontSize":48');
  });

  it('uses light background (#fafafa)', () => {
    const json = nodeJson(baseInput);
    expect(json.toLowerCase()).toContain('#fafafa');
  });

  it('omits tag labels when tags array is empty', () => {
    const json = JSON.stringify(buildBlogOgNode({ ...baseInput, tags: [] }));
    expect(json).toContain('2026-04-22');
    expect(json).not.toContain('#nash');
    expect(json).not.toContain('#theory');
  });

  it('truncates excessively long titles', () => {
    const long = 'あ'.repeat(200);
    const json = nodeJson({ ...baseInput, title: long });
    expect(json).toContain('…');
  });
});

describe('renderBlogOg (integration)', () => {
  it('produces a 1200x630 PNG', async () => {
    const png = await renderBlogOg(baseInput);
    const buf = Buffer.from(png);
    expect(buf.subarray(0, 8)).toEqual(PNG_SIG);
    expect(buf.readUInt32BE(16)).toBe(1200);
    expect(buf.readUInt32BE(20)).toBe(630);
  });
});
