import { readdirSync } from 'node:fs';
import { extname, basename, resolve } from 'node:path';

export interface PokemonImageResolverOpts {
  dir: string;
  baseUrl: string;
}

export type PokemonImageResolver = (name: string) => string | null;

const ALLOWED_EXTENSIONS = ['.png', '.jpg'] as const;

function joinUrl(baseUrl: string, filename: string): string {
  const base = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`;
  return `${base}pokemons/${encodeURIComponent(filename)}`;
}

export function createPokemonImageResolver(opts: PokemonImageResolverOpts): PokemonImageResolver {
  const map = new Map<string, string>();

  let entries: string[];
  try {
    entries = readdirSync(opts.dir);
  } catch {
    entries = [];
  }

  // .png priority: insert .png first, then .jpg only if not already mapped.
  const ordered = [...entries].sort((a, b) => {
    const ea = extname(a).toLowerCase();
    const eb = extname(b).toLowerCase();
    if (ea === '.png' && eb !== '.png') return -1;
    if (eb === '.png' && ea !== '.png') return 1;
    return 0;
  });

  for (const filename of ordered) {
    if (filename.startsWith('.')) continue;
    const ext = extname(filename).toLowerCase();
    if (!ALLOWED_EXTENSIONS.includes(ext as (typeof ALLOWED_EXTENSIONS)[number])) continue;
    const stem = basename(filename, ext);
    if (map.has(stem)) continue;
    map.set(stem, joinUrl(opts.baseUrl, filename));
  }

  return (name: string): string | null => map.get(name) ?? null;
}

const defaultDir = process.env.POKEMON_IMAGE_DIR ?? resolve(process.cwd(), 'public/pokemons');

export const resolvePokemonImage: PokemonImageResolver = createPokemonImageResolver({
  dir: defaultDir,
  baseUrl: import.meta.env.BASE_URL ?? '/',
});
