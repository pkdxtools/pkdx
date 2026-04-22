import { describe, expect, it, beforeEach, afterEach } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPokemonImageResolver } from '../src/lib/pokemon-image.ts';

let dir = '';

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'pokemon-image-'));
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

function place(name: string): void {
  writeFileSync(join(dir, name), 'x');
}

describe('createPokemonImageResolver', () => {
  it('returns null when no file exists', () => {
    const resolve = createPokemonImageResolver({ dir, baseUrl: '/' });
    expect(resolve('カバルドン')).toBeNull();
  });

  it('resolves png file with baseUrl prefix', () => {
    place('カバルドン.png');
    const resolve = createPokemonImageResolver({ dir, baseUrl: '/pkdx/' });
    expect(resolve('カバルドン')).toBe(`/pkdx/pokemons/${encodeURIComponent('カバルドン.png')}`);
  });

  it('resolves jpg file when only jpg exists', () => {
    place('マンムー.jpg');
    const resolve = createPokemonImageResolver({ dir, baseUrl: '/' });
    expect(resolve('マンムー')).toBe(`/pokemons/${encodeURIComponent('マンムー.jpg')}`);
  });

  it('prefers png over jpg when both exist (explicit priority)', () => {
    place('リザードン.png');
    place('リザードン.jpg');
    const resolve = createPokemonImageResolver({ dir, baseUrl: '/' });
    expect(resolve('リザードン')).toBe(`/pokemons/${encodeURIComponent('リザードン.png')}`);
  });

  it('encodes special characters (タイプ：ヌル, ニドラン♂)', () => {
    place('タイプ：ヌル.png');
    place('ニドラン♂.jpg');
    const resolve = createPokemonImageResolver({ dir, baseUrl: '/pkdx/' });
    expect(resolve('タイプ：ヌル')).toBe(`/pkdx/pokemons/${encodeURIComponent('タイプ：ヌル.png')}`);
    expect(resolve('ニドラン♂')).toBe(`/pkdx/pokemons/${encodeURIComponent('ニドラン♂.jpg')}`);
  });

  it('ignores dotfiles (.gitkeep, .DS_Store)', () => {
    place('.gitkeep');
    place('.DS_Store');
    const resolve = createPokemonImageResolver({ dir, baseUrl: '/' });
    expect(resolve('.gitkeep')).toBeNull();
    expect(resolve('.DS_Store')).toBeNull();
  });

  it('ignores unsupported extensions (.webp, .gif)', () => {
    place('カバルドン.webp');
    place('マンムー.gif');
    const resolve = createPokemonImageResolver({ dir, baseUrl: '/' });
    expect(resolve('カバルドン')).toBeNull();
    expect(resolve('マンムー')).toBeNull();
  });

  it('returns null when directory is missing', () => {
    const missing = join(dir, 'nope');
    const resolve = createPokemonImageResolver({ dir: missing, baseUrl: '/' });
    expect(resolve('カバルドン')).toBeNull();
  });

  it('picks up files added after the resolver is created (dev hot-add)', () => {
    const resolve = createPokemonImageResolver({ dir, baseUrl: '/' });
    expect(resolve('カバルドン')).toBeNull();
    place('カバルドン.png');
    expect(resolve('カバルドン')).toBe(`/pokemons/${encodeURIComponent('カバルドン.png')}`);
  });

  it('accepts uppercase extensions (FOO.PNG / FOO.JPG)', () => {
    place('カバルドン.PNG');
    place('マンムー.JPG');
    const resolve = createPokemonImageResolver({ dir, baseUrl: '/' });
    expect(resolve('カバルドン')).toBe(`/pokemons/${encodeURIComponent('カバルドン.PNG')}`);
    expect(resolve('マンムー')).toBe(`/pokemons/${encodeURIComponent('マンムー.JPG')}`);
  });
});
