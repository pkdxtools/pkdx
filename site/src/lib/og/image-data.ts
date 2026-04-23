import { readdirSync, readFileSync } from 'node:fs';
import { basename, extname, join, resolve } from 'node:path';

export interface PokemonImageDataUrlOpts {
  dir: string;
}

export type PokemonImageDataUrlResolver = (name: string) => string | null;

const ALLOWED: ReadonlyArray<{ ext: string; mime: string }> = [
  { ext: '.png', mime: 'image/png' },
  { ext: '.jpg', mime: 'image/jpeg' },
];

export function createPokemonImageDataUrl(
  opts: PokemonImageDataUrlOpts,
): PokemonImageDataUrlResolver {
  return (name: string): string | null => {
    let entries: string[];
    try {
      entries = readdirSync(opts.dir);
    } catch {
      return null;
    }

    // .png priority: scan png-named entries first.
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
      const hit = ALLOWED.find((a) => a.ext === ext);
      if (!hit) continue;
      const stem = basename(filename, rawExt);
      if (stem !== name) continue;
      const full = resolve(join(opts.dir, filename));
      const buf = readFileSync(full);
      return `data:${hit.mime};base64,${buf.toString('base64')}`;
    }
    return null;
  };
}
