import { describe, expect, it } from 'bun:test';
import { buildOgUrl } from '../src/lib/og/meta-url.ts';

const site = new URL('https://example.github.io');

describe('buildOgUrl', () => {
  it('returns absolute URL including base path and slug .png', () => {
    const url = buildOgUrl('teams', 'full', site, '/pkdx/');
    expect(url).toBe('https://example.github.io/pkdx/og/teams/full.png');
  });

  it('supports blog kind', () => {
    const url = buildOgUrl('blog', 'hello', site, '/pkdx/');
    expect(url).toBe('https://example.github.io/pkdx/og/blog/hello.png');
  });

  it('encodes non-ASCII slug', () => {
    const url = buildOgUrl('teams', 'カバルドン-build', site, '/pkdx/');
    expect(url).toBe(
      `https://example.github.io/pkdx/og/teams/${encodeURIComponent('カバルドン-build')}.png`,
    );
  });

  it('works with root base ("/")', () => {
    const url = buildOgUrl('blog', 'hello', site, '/');
    expect(url).toBe('https://example.github.io/og/blog/hello.png');
  });

  it('normalizes base missing trailing slash', () => {
    const url = buildOgUrl('blog', 'hello', site, '/pkdx');
    expect(url).toBe('https://example.github.io/pkdx/og/blog/hello.png');
  });

  it('preserves `/` in nested slug so [...slug] route still matches', () => {
    const url = buildOgUrl('blog', 'sub/dir/article', site, '/pkdx/');
    expect(url).toBe('https://example.github.io/pkdx/og/blog/sub/dir/article.png');
  });

  it('encodes each nested segment independently', () => {
    const url = buildOgUrl('blog', 'カテゴリ/カバルドン-build', site, '/pkdx/');
    expect(url).toBe(
      `https://example.github.io/pkdx/og/blog/${encodeURIComponent('カテゴリ')}/${encodeURIComponent('カバルドン-build')}.png`,
    );
  });
});
