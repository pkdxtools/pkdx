export type OgKind = 'teams' | 'blog';

export function buildOgUrl(kind: OgKind, slug: string, site: URL, basePath: string): string {
  const base = basePath.endsWith('/') ? basePath : `${basePath}/`;
  const path = `${base}og/${kind}/${encodeURIComponent(slug)}.png`;
  return new URL(path, site).href;
}
