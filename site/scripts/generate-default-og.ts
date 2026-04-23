#!/usr/bin/env bun
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { renderBlogOg } from '../src/lib/og/blog-og.ts';
import { loadSiteConfig } from '../src/lib/site-config.ts';

const out = resolve(process.cwd(), 'public/og/default.png');
const config = loadSiteConfig();

const png = await renderBlogOg({
  title: 'ポケモン対戦と育成のメモ',
  tags: [],
  siteName: config.site_name,
});

mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, png);
console.log(`Wrote ${out} (${png.byteLength} bytes)`);
