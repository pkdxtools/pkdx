import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { clearFontCache, loadFonts } from '../src/lib/og/fonts.ts';

let dir = '';

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'og-fonts-'));
  clearFontCache();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
  clearFontCache();
});

describe('loadFonts', () => {
  it('throws with path-mentioning error when directory is missing', () => {
    const missing = join(dir, 'nope');
    expect(() => loadFonts(missing)).toThrow(missing);
  });

  it('throws with specific font filenames when files missing', () => {
    expect(() => loadFonts(dir)).toThrow(/IBMPlexSansJP-Regular\.woff/);
  });

  it('returns Buffers for Regular and Bold when present', () => {
    writeFileSync(join(dir, 'IBMPlexSansJP-Regular.woff'), Buffer.from('reg'));
    writeFileSync(join(dir, 'IBMPlexSansJP-Bold.woff'), Buffer.from('bold'));
    const fonts = loadFonts(dir);
    expect(Buffer.from(fonts.regular).toString()).toBe('reg');
    expect(Buffer.from(fonts.bold).toString()).toBe('bold');
  });

  it('caches the result (second call returns same buffers)', () => {
    writeFileSync(join(dir, 'IBMPlexSansJP-Regular.woff'), Buffer.from('reg'));
    writeFileSync(join(dir, 'IBMPlexSansJP-Bold.woff'), Buffer.from('bold'));
    const a = loadFonts(dir);
    const b = loadFonts(dir);
    expect(a.regular).toBe(b.regular);
    expect(a.bold).toBe(b.bold);
  });

  it('clearFontCache forces re-read on next call', () => {
    writeFileSync(join(dir, 'IBMPlexSansJP-Regular.woff'), Buffer.from('v1'));
    writeFileSync(join(dir, 'IBMPlexSansJP-Bold.woff'), Buffer.from('v1'));
    const a = loadFonts(dir);
    writeFileSync(join(dir, 'IBMPlexSansJP-Regular.woff'), Buffer.from('v2'));
    clearFontCache();
    const b = loadFonts(dir);
    expect(Buffer.from(b.regular).toString()).toBe('v2');
    expect(a.regular).not.toBe(b.regular);
  });
});
