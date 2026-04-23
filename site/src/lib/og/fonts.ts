import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export interface FontBuffers {
  regular: Buffer;
  bold: Buffer;
}

const REGULAR_FILENAME = 'IBMPlexSansJP-Regular.woff';
const BOLD_FILENAME = 'IBMPlexSansJP-Bold.woff';

let cache: FontBuffers | null = null;

export function loadFonts(dir?: string): FontBuffers {
  if (cache) return cache;
  const fontDir =
    dir ?? process.env.OG_FONT_DIR ?? resolve(process.cwd(), 'assets/fonts');
  try {
    const regular = readFileSync(resolve(fontDir, REGULAR_FILENAME));
    const bold = readFileSync(resolve(fontDir, BOLD_FILENAME));
    cache = { regular, bold };
    return cache;
  } catch (cause) {
    throw new Error(
      `OG font not found in ${fontDir}: ${REGULAR_FILENAME} / ${BOLD_FILENAME}`,
      { cause },
    );
  }
}

export function clearFontCache(): void {
  cache = null;
}
