import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { isPublishableBlog } from '../../../content.config';
import { loadSiteConfig } from '../../../lib/site-config';
import { renderBlogOg } from '../../../lib/og/blog-og';

export async function getStaticPaths() {
  const entries = (await getCollection('blog')).filter(isPublishableBlog);
  return entries.map((entry) => ({
    params: { slug: entry.id },
    props: { entry },
  }));
}

export const GET: APIRoute = async ({ props }) => {
  const { entry } = props as {
    entry: Awaited<ReturnType<typeof getCollection<'blog'>>>[number];
  };
  const config = loadSiteConfig();

  const png = await renderBlogOg({
    title: entry.data.title,
    date: entry.data.date,
    tags: entry.data.tags ?? [],
    siteName: config.site_name,
  });

  return new Response(new Uint8Array(png), {
    headers: {
      'Content-Type': 'image/png',
      'Cache-Control': 'public, max-age=300, must-revalidate',
    },
  });
};
