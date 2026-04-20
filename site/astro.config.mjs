import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

const siteUrl = process.env.SITE_URL ?? 'https://example.github.io';
const siteBase = process.env.SITE_BASE ?? '/pkdx';

export default defineConfig({
  site: siteUrl,
  base: siteBase,
  output: 'static',
  trailingSlash: 'always',
  build: { format: 'directory' },
  integrations: [sitemap()],
});
