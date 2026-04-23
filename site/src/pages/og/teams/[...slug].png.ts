import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { resolve } from 'node:path';
import { isPublishableTeam } from '../../../content.config';
import { loadSiteConfig } from '../../../lib/site-config';
import { createPokemonImageDataUrl } from '../../../lib/og/image-data';
import { renderTeamOg } from '../../../lib/og/team-og';
import { loadTeamMeta } from '../../../lib/team-meta';

const pokemonImageDir =
  process.env.OG_POKEMON_IMAGE_DIR ?? resolve(process.cwd(), 'public/pokemons');
const pokemonImageDataUrl = createPokemonImageDataUrl({ dir: pokemonImageDir });

export async function getStaticPaths() {
  const entries = (await getCollection('teams')).filter(isPublishableTeam);
  return entries.map((entry) => ({
    params: { slug: entry.id },
    props: { entry, meta: loadTeamMeta(entry.filePath) },
  }));
}

export const GET: APIRoute = async ({ props }) => {
  const { entry, meta } = props as {
    entry: Awaited<ReturnType<typeof getCollection<'teams'>>>[number];
    meta: ReturnType<typeof loadTeamMeta>;
  };
  const axisName =
    meta?.members?.[0]?.name ?? entry.data.members?.[0] ?? entry.data.axis ?? null;
  const axisImageDataUrl = axisName ? pokemonImageDataUrl(axisName) : null;
  const axisTypes = meta?.members?.[0]?.types ?? [];
  const config = loadSiteConfig();

  const png = await renderTeamOg({
    title: entry.data.title ?? '',
    battleFormat: entry.data.battle_format ?? 'singles',
    mechanics: entry.data.mechanics ?? '',
    regulation: entry.data.regulation,
    date: entry.data.date ?? new Date(),
    siteName: config.site_name,
    axisImageDataUrl,
    axisTypes,
  });

  // `output: 'static'` ビルドでは endpoint の Response headers はディスクに
  // 残らず捨てられる。GitHub Pages は custom Cache-Control を受け付けないので
  // ここで Cache-Control を返しても no-op になる。キャッシュ無効化が必要な
  // ときは URL 自体を変える (content hash / バージョン付与) 以外に手がない。
  return new Response(new Uint8Array(png), {
    headers: {
      'Content-Type': 'image/png',
    },
  });
};
