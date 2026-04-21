import { glob } from 'astro/loaders';
import { execSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

type GlobArgs = Parameters<typeof glob>[0];

const cache = new Map<string, string | null>();

function gitFirstCommitIso(absPath: string): string | null {
  if (cache.has(absPath)) return cache.get(absPath)!;
  try {
    const out = execSync(
      `git log --reverse --format=%aI -- "${absPath}"`,
      { encoding: 'utf-8' },
    );
    const iso = out.split('\n')[0]?.trim() || null;
    cache.set(absPath, iso);
    return iso;
  } catch {
    cache.set(absPath, null);
    return null;
  }
}

/**
 * glob() loader を wrap し、frontmatter に publishedAt が無い記事に対して
 * そのファイルを最初に commit した author date を ISO 文字列で差し込む。
 * 手動で publishedAt を書いていれば上書きしない。
 */
export function globWithPublishedAt(options: GlobArgs) {
  const base = glob(options);
  return {
    ...base,
    async load(ctx: Parameters<typeof base.load>[0]) {
      await base.load(ctx);
      const rootDir = fileURLToPath(ctx.config.root);
      for (const [, entry] of ctx.store.entries()) {
        const data = entry.data as Record<string, unknown>;
        if (data.publishedAt) continue;
        if (data.published === false) continue;
        if (!entry.filePath) continue;
        const abs = resolve(rootDir, entry.filePath);
        const iso = gitFirstCommitIso(abs);
        if (!iso) continue;
        ctx.store.set({
          ...entry,
          data: { ...data, publishedAt: iso },
        });
      }
    },
  };
}
