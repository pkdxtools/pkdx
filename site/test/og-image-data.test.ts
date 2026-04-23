import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPokemonImageDataUrl } from '../src/lib/og/image-data.ts';

let dir = '';

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'og-image-data-'));
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const JPEG_SIG = Buffer.from([0xff, 0xd8, 0xff, 0xe0]);

function place(name: string, sig: Buffer): void {
  writeFileSync(join(dir, name), sig);
}

describe('createPokemonImageDataUrl', () => {
  it('returns null when file is missing', () => {
    const resolve = createPokemonImageDataUrl({ dir });
    expect(resolve('カバルドン')).toBeNull();
  });

  it('returns data:image/png;base64,... for .png file', () => {
    place('カバルドン.png', PNG_SIG);
    const resolve = createPokemonImageDataUrl({ dir });
    const url = resolve('カバルドン');
    expect(url).not.toBeNull();
    expect(url!.startsWith('data:image/png;base64,')).toBe(true);
    const decoded = Buffer.from(url!.split(',')[1], 'base64');
    expect(decoded.subarray(0, 8)).toEqual(PNG_SIG);
  });

  it('returns data:image/jpeg;base64,... for .jpg file', () => {
    place('マンムー.jpg', JPEG_SIG);
    const resolve = createPokemonImageDataUrl({ dir });
    const url = resolve('マンムー');
    expect(url).not.toBeNull();
    expect(url!.startsWith('data:image/jpeg;base64,')).toBe(true);
  });

  it('prefers png over jpg when both exist', () => {
    place('リザードン.png', PNG_SIG);
    place('リザードン.jpg', JPEG_SIG);
    const resolve = createPokemonImageDataUrl({ dir });
    expect(resolve('リザードン')!.startsWith('data:image/png;base64,')).toBe(true);
  });

  it('returns null when directory does not exist', () => {
    const missing = join(dir, 'nope');
    const resolve = createPokemonImageDataUrl({ dir: missing });
    expect(resolve('カバルドン')).toBeNull();
  });

  it('ignores unsupported extensions (.webp)', () => {
    place('カバルドン.webp', Buffer.from('webp'));
    const resolve = createPokemonImageDataUrl({ dir });
    expect(resolve('カバルドン')).toBeNull();
  });

  it('handles name with special characters (タイプ：ヌル)', () => {
    place('タイプ：ヌル.png', PNG_SIG);
    const resolve = createPokemonImageDataUrl({ dir });
    expect(resolve('タイプ：ヌル')).not.toBeNull();
  });
});
