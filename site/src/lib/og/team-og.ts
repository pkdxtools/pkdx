import { buildTypeGradient } from './colors.ts';
import { h, renderToPng, renderToSvg, type OgSize, type VNode } from './render.ts';

export interface TeamOgInput {
  title: string;
  battleFormat: 'singles' | 'doubles';
  mechanics: string;
  // 公式レギュレーション名 (例: "H", "M-A", "M-B")。frontmatter では optional。
  regulation?: string;
  date: Date;
  siteName: string;
  axisImageDataUrl: string | null;
  // 軸ポケのタイプ (日本語)。MemberCard と同じ 135deg type-gradient を BG に敷くのに使う。
  // 画像なし時はこの gradient 単体、画像あり時は下地の gradient の上に opacity 0.7 で画像が重なる。
  axisTypes: string[];
}

const SIZE: OgSize = { width: 1200, height: 630 };

const COLOR_TEXT = '#ffffff';
const COLOR_MUTED = 'rgba(255,255,255,0.78)';

function formatLabel(kind: 'singles' | 'doubles'): string {
  return kind === 'doubles' ? 'ダブル' : 'シングル';
}

function dateISO(d: Date): string {
  return d.toISOString().slice(0, 10);
}

// 長文タイトルは satori の文字送り安定のため手動 truncate
function truncate(s: string, max: number): string {
  return s.length > max ? `${s.slice(0, max - 1)}…` : s;
}

export function buildTeamOgNode(input: TeamOgInput): VNode {
  const title = truncate(input.title, 60);
  const metaParts = [
    formatLabel(input.battleFormat),
    input.mechanics,
    input.regulation,
  ].filter((s): s is string => typeof s === 'string' && s.length > 0);
  const meta = metaParts.join(' · ');
  const dateStr = dateISO(input.date);
  const hasImage = input.axisImageDataUrl != null;
  const bgGradient = buildTypeGradient(input.axisTypes);

  return h(
    'div',
    {
      style: {
        width: SIZE.width,
        height: SIZE.height,
        display: 'flex',
        position: 'relative',
        // L0: タイプカラー (MemberCard と同じ 135deg) を敷く。画像がある場合はこの上に
        // opacity 0.7 で画像が重なり、色が透けて member-card と同じ質感になる。
        background: bgGradient,
        color: COLOR_TEXT,
        fontFamily: 'IBMPlex',
      },
    },
    // L1: axis pokemon image (bleeds off left edge)
    hasImage
      ? h('img', {
          src: input.axisImageDataUrl!,
          width: 900,
          height: 900,
          style: {
            position: 'absolute',
            left: -150,
            // キャンバス中央寄せ (-135) だとポケモン画像の顔が上端に寄る素材で
            // 見切れるため、画像全体を下にシフトして顔を中段に落とす。
            top: -40,
            width: 900,
            height: 900,
            objectFit: 'cover',
            opacity: 0.7,
          },
        })
      : null,
    // L2: readability overlay on the right — fades from transparent to dark so that text on the right side remains legible over any pokemon color palette
    h('div', {
      style: {
        position: 'absolute',
        right: 0,
        top: 0,
        width: 720,
        height: SIZE.height,
        display: 'flex',
        background:
          'linear-gradient(to right, rgba(26,26,26,0) 0%, rgba(26,26,26,0.85) 40%, rgba(26,26,26,0.92) 100%)',
      },
    }),
    // L3: content — site name (top), title + format (middle right), date (bottom right)
    h(
      'div',
      {
        style: {
          position: 'relative',
          width: SIZE.width,
          height: SIZE.height,
          display: 'flex',
          flexDirection: 'column',
          padding: '32px 48px',
          justifyContent: 'space-between',
        },
      },
      // top: site name
      h(
        'div',
        {
          style: {
            display: 'flex',
            fontSize: 28,
            fontWeight: 700,
            opacity: 0.9,
          },
        },
        input.siteName,
      ),
      // middle: title + format — right-aligned column near right edge
      h(
        'div',
        {
          style: {
            display: 'flex',
            flexDirection: 'column',
            alignSelf: 'flex-end',
            width: 660,
            gap: 16,
          },
        },
        h(
          'div',
          {
            style: {
              display: 'flex',
              fontSize: 64,
              fontWeight: 700,
              lineHeight: 1.2,
              letterSpacing: -0.5,
              textAlign: 'right',
              justifyContent: 'flex-end',
            },
          },
          title,
        ),
        h(
          'div',
          {
            style: {
              display: 'flex',
              fontSize: 30,
              color: COLOR_MUTED,
              justifyContent: 'flex-end',
            },
          },
          meta,
        ),
      ),
      // bottom: date right-aligned
      h(
        'div',
        {
          style: {
            display: 'flex',
            fontSize: 24,
            color: COLOR_MUTED,
            justifyContent: 'flex-end',
          },
        },
        dateStr,
      ),
    ),
  );
}

export async function renderTeamOgToSvg(input: TeamOgInput): Promise<string> {
  return renderToSvg(buildTeamOgNode(input), SIZE);
}

export async function renderTeamOg(input: TeamOgInput): Promise<Uint8Array> {
  return renderToPng(buildTeamOgNode(input), SIZE);
}
