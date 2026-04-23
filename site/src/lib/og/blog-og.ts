import { h, renderToPng, renderToSvg, type OgSize, type VNode } from './render.ts';

export interface BlogOgInput {
  title: string;
  date?: Date;
  tags: string[];
  siteName: string;
}

const SIZE: OgSize = { width: 1200, height: 630 };

const BG = '#fafafa';
const COLOR_TEXT = '#18181b';
const COLOR_MUTED = '#71717a';
const COLOR_ACCENT = '#2563eb';

export function pickTitleFontSize(len: number): number {
  if (len <= 15) return 72;
  if (len <= 30) return 60;
  return 48;
}

function dateISO(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function truncate(s: string, max: number): string {
  return s.length > max ? `${s.slice(0, max - 1)}…` : s;
}

export function buildBlogOgNode(input: BlogOgInput): VNode {
  const title = truncate(input.title, 90);
  const fontSize = pickTitleFontSize(title.length);
  const dateStr = input.date ? dateISO(input.date) : null;
  const tagText = input.tags.slice(0, 4).map((t) => `#${t}`).join('  ');

  return h(
    'div',
    {
      style: {
        width: SIZE.width,
        height: SIZE.height,
        display: 'flex',
        flexDirection: 'column',
        background: BG,
        color: COLOR_TEXT,
        fontFamily: 'IBMPlex',
        padding: '0 72px',
      },
    },
    // top accent line
    h('div', {
      style: {
        display: 'flex',
        width: 160,
        height: 6,
        background: COLOR_ACCENT,
        marginTop: 56,
      },
    }),
    // site name
    h(
      'div',
      {
        style: {
          display: 'flex',
          fontSize: 28,
          fontWeight: 700,
          color: COLOR_ACCENT,
          marginTop: 12,
        },
      },
      input.siteName,
    ),
    // title — centered vertical area
    h(
      'div',
      {
        style: {
          display: 'flex',
          flex: 1,
          alignItems: 'center',
        },
      },
      h(
        'div',
        {
          style: {
            display: 'flex',
            fontSize,
            fontWeight: 700,
            lineHeight: 1.3,
            letterSpacing: -0.5,
          },
        },
        title,
      ),
    ),
    // footer: date + tags
    h(
      'div',
      {
        style: {
          display: 'flex',
          alignItems: 'center',
          gap: 24,
          fontSize: 24,
          color: COLOR_MUTED,
          marginBottom: 56,
        },
      },
      dateStr ? h('span', { style: { display: 'flex' } }, dateStr) : null,
      tagText.length > 0 ? h('span', { style: { display: 'flex' } }, tagText) : null,
    ),
  );
}

export async function renderBlogOgToSvg(input: BlogOgInput): Promise<string> {
  return renderToSvg(buildBlogOgNode(input), SIZE);
}

export async function renderBlogOg(input: BlogOgInput): Promise<Uint8Array> {
  return renderToPng(buildBlogOgNode(input), SIZE);
}
