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
  // Rescan the directory on every call so images added during an active dev
  // server session are picked up without a restart.
  return (name: string): string | null => {
    let entries: string[];
    try {
      entries = readdirSync(opts.dir);
    } catch {
      return null;
    }

    // .png priority: examine .png entries first so .jpg only wins when no .png exists.
    const ordered = [...entries].sort((a, b) => {
      const ea = extname(a).toLowerCase();
      const eb = extname(b).toLowerCase();
      if (ea === '.png' && eb !== '.png') return -1;
      if (eb === '.png' && ea !== '.png') return 1;
      return 0;
    });

    for (const filename of ordered) {
      if (filename.startsWith('.')) continue;
      const rawExt = extname(filename);
      const ext = rawExt.toLowerCase();
      if (!ALLOWED_EXTENSIONS.includes(ext as (typeof ALLOWED_EXTENSIONS)[number])) continue;
      // Strip with the original-case extension so uppercase suffixes (FOO.PNG) are removed correctly.
      const stem = basename(filename, rawExt);
      if (stem !== name) continue;
      return joinUrl(opts.baseUrl, filename);
    }
    return null;
  };
}

export const resolvePokemonImage: PokemonImageResolver = createPokemonImageResolver({
  dir: resolve(process.cwd(), 'public/pokemons'),
  baseUrl: import.meta.env.BASE_URL ?? '/',
});
