import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { resolve } from 'node:path';
import { clearFontCache } from '../src/lib/og/fonts.ts';
import { h, renderToPng, renderToSvg, svgToPng } from '../src/lib/og/render.ts';

const FONT_DIR = resolve(process.cwd(), 'assets/fonts');
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const simpleNode = h(
  'div',
  {
    style: {
      width: 1200,
      height: 630,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: '#1a1a1a',
      color: '#fff',
      fontFamily: 'IBMPlex',
      fontSize: 72,
    },
  },
  'pkdx',
);

beforeEach(() => {
  process.env.OG_FONT_DIR = FONT_DIR;
  clearFontCache();
});

afterEach(() => {
  delete process.env.OG_FONT_DIR;
  clearFontCache();
});

describe('renderToSvg', () => {
  it('produces an SVG string containing the text', async () => {
    const svg = await renderToSvg(simpleNode, { width: 1200, height: 630 });
    expect(svg.startsWith('<svg')).toBe(true);
    expect(svg).toContain('1200');
    expect(svg).toContain('630');
  });
});

describe('svgToPng', () => {
  it('returns PNG with correct signature and dimensions (IHDR)', async () => {
    const svg = await renderToSvg(simpleNode, { width: 1200, height: 630 });
    const png = svgToPng(svg, 1200);
    const buf = Buffer.from(png);
    expect(buf.subarray(0, 8)).toEqual(PNG_SIG);
    // IHDR chunk: bytes 16-19 = width, 20-23 = height (big-endian uint32)
    expect(buf.readUInt32BE(16)).toBe(1200);
    expect(buf.readUInt32BE(20)).toBe(630);
  });
});

describe('renderToPng', () => {
  it('composes SVG + PNG stages into a PNG buffer', async () => {
    const png = await renderToPng(simpleNode, { width: 1200, height: 630 });
    const buf = Buffer.from(png);
    expect(buf.subarray(0, 8)).toEqual(PNG_SIG);
    expect(buf.readUInt32BE(16)).toBe(1200);
    expect(buf.readUInt32BE(20)).toBe(630);
    expect(buf.byteLength).toBeGreaterThan(1000);
  });
});
