import { defineCollection } from 'astro:content';
import { z } from 'zod';
import { globWithPublishedAt } from './loaders/with-published-at';

const CONTENT_ROOT = process.env.CONTENT_ROOT ?? '../box';

const battleFormat = z.enum(['singles', 'doubles']);

const teamSchema = z.object({
  title: z.string().optional(),
  axis: z.string().optional(),
  date: z.coerce.date().optional(),
  // ソート用の公開時刻。published: false → true 切り替え時に ISO datetime を入れる。
  // 未設定なら date にフォールバック。
  publishedAt: z.coerce.date().optional(),
  battle_format: battleFormat.optional(),
  mechanics: z.string().optional(),
  version: z.string().optional(),
  regulation: z.string().optional(),
  members: z.array(z.string()).optional(),
  description: z.string().optional(),
  eyecatch: z.string().optional(),
  tags: z.array(z.string()).default([]),
  edited: z.boolean().default(false),
  // falsy = 非公開。team-builder が `--publish` 付きで生成したときだけ true。
  // 明示されていない (既存の手書き md など) 場合は公開寄りに倒す。
  published: z.boolean().default(true),
  generated_by: z.string().optional(),
  schema_version: z.number().default(1),
});

const blogSchema = z.object({
  title: z.string(),
  date: z.coerce.date(),
  publishedAt: z.coerce.date().optional(),
  description: z.string().optional(),
  tags: z.array(z.string()).default([]),
  eyecatch: z.string().optional(),
  // falsy = 非公開。TEMPLATE からコピーしたときは `published: true` が入る。
  published: z.boolean().default(true),
});

const teams = defineCollection({
  loader: globWithPublishedAt({ pattern: '**/*.md', base: `${CONTENT_ROOT}/teams` }),
  schema: teamSchema,
});

const blog = defineCollection({
  loader: globWithPublishedAt({ pattern: '**/*.md', base: `${CONTENT_ROOT}/blog` }),
  schema: blogSchema,
});

export const collections = { teams, blog };

export type TeamFrontmatter = z.infer<typeof teamSchema>;
export type BlogFrontmatter = z.infer<typeof blogSchema>;

export type PublishedTeamData = TeamFrontmatter & {
  title: string;
  axis: string;
  date: Date;
  battle_format: 'singles' | 'doubles';
  mechanics: string;
  version: string;
  members: string[];
};

export function isPublishableTeam<T extends { data: TeamFrontmatter }>(
  entry: T,
): entry is T & { data: PublishedTeamData } {
  const d = entry.data;
  return (
    d.published !== false &&
    typeof d.title === 'string' &&
    typeof d.axis === 'string' &&
    d.date instanceof Date &&
    d.battle_format != null &&
    typeof d.mechanics === 'string' &&
    typeof d.version === 'string' &&
    Array.isArray(d.members)
  );
}

export function isPublishableBlog<T extends { data: BlogFrontmatter }>(entry: T): boolean {
  return entry.data.published !== false;
}
