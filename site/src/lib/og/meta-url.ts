export type OgKind = 'teams' | 'blog';

export function buildOgUrl(kind: OgKind, slug: string, site: URL, basePath: string): string {
  const base = basePath.endsWith('/') ? basePath : `${basePath}/`;
  // `**/*.md` の collection loader は `subdir/entry` のような階層 slug を吐き得る。
  // `encodeURIComponent(slug)` だと `/` が `%2F` になり [...slug] ルートに
  // マッチしなくなるので、セグメントごとに分けて encode する。
  const encodedSlug = slug.split('/').map(encodeURIComponent).join('/');
  const path = `${base}og/${kind}/${encodedSlug}.png`;
  return new URL(path, site).href;
}
