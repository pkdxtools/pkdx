import { Resvg } from '@resvg/resvg-js';
import satori from 'satori';
import { loadFonts } from './fonts.ts';

export interface OgSize {
  width: number;
  height: number;
}

export type Style = Record<string, unknown>;

export type VNodeProps = {
  style?: Style;
  children?: unknown;
  [key: string]: unknown;
};

export type VNode = {
  type: string;
  props: VNodeProps;
};

export type Child = VNode | string | number | null | undefined | false;

// React createElement-compatible node factory. 2nd arg is the full props object
// (style, src, href, etc.), not just style — mirrors React so <img src=... /> works.
export function h(
  type: string,
  props: VNodeProps | null,
  ...children: Child[]
): VNode {
  const kids = children.filter(
    (c): c is VNode | string | number => c !== null && c !== undefined && c !== false,
  );
  const finalProps: VNodeProps = { ...(props ?? {}) };
  if (kids.length === 1) finalProps.children = kids[0];
  else if (kids.length > 1) finalProps.children = kids;
  return { type, props: finalProps };
}

export async function renderToSvg(node: VNode, size: OgSize): Promise<string> {
  const { regular, bold } = loadFonts();
  return satori(node as unknown as Parameters<typeof satori>[0], {
    width: size.width,
    height: size.height,
    fonts: [
      { name: 'IBMPlex', data: regular, weight: 400, style: 'normal' },
      { name: 'IBMPlex', data: bold, weight: 700, style: 'normal' },
    ],
  });
}

export function svgToPng(svg: string, width: number): Uint8Array {
  const resvg = new Resvg(svg, { fitTo: { mode: 'width', value: width } });
  return resvg.render().asPng();
}

export async function renderToPng(node: VNode, size: OgSize): Promise<Uint8Array> {
  const svg = await renderToSvg(node, size);
  return svgToPng(svg, size.width);
}
