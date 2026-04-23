import { defineConfig, fontProviders } from 'astro/config';
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
  vite: {
    // @resvg/resvg-js は native binary を含む。Vite の optimizeDeps に拾われると
    // bundle 時に壊れるので exclude。endpoint 側では直接 node_modules から解決する。
    optimizeDeps: { exclude: ['@resvg/resvg-js'] },
    ssr: { external: ['@resvg/resvg-js'] },
  },
  // 一覧ページから詳細へのリンクを hover/focus 時点で HTML prefetch する。
  // prefetch された HTML をブラウザがパースするタイミングで <link rel="preload">
  // のフォントも早期に disk cache に乗るので、遷移時の 304 ラウンドトリップが
  // 表示より手前で済む。
  prefetch: {
    prefetchAll: true,
    defaultStrategy: 'hover',
  },
  fonts: [
    {
      provider: fontProviders.google(),
      name: 'IBM Plex Sans JP',
      cssVariable: '--font-ibm-plex-sans-jp',
      weights: [400, 500, 600, 700],
      styles: ['normal'],
      subsets: ['japanese', 'latin'],
      // block: 初回のみ最大 100ms invisible で web font 到着を待ち、
       // FOUT を回避する。<ClientRouter /> による SPA 遷移で head は
       // 維持されるため、初回以降の遷移では block period が再発しない。
      display: 'block',
      // optimizedFallbacks は default true。fallback 側に size-adjust /
      // ascent-override を自動付与し、web font ロード前後の layout shift /
      // 文字サイズ変動を抑える。
      fallbacks: [
        '-apple-system',
        'BlinkMacSystemFont',
        'Hiragino Sans',
        'Hiragino Kaku Gothic ProN',
        'Meiryo',
        'sans-serif',
      ],
    },
  ],
});
