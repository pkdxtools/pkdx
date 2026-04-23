#!/usr/bin/env bun
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync, statSync } from 'node:fs';
import { resolve } from 'node:path';

const cwd = process.cwd();
const contentRoot = resolve(cwd, 'test/fixtures');
const pokemonImageDir = resolve(cwd, 'test/fixtures/pokemons');
const distDir = resolve(cwd, 'dist');

if (existsSync(distDir)) {
  rmSync(distDir, { recursive: true, force: true });
}

const env = {
  ...process.env,
  CONTENT_ROOT: contentRoot,
  // OG endpoint はデフォルトで public/pokemons/ を見る。smoke では fixture の軸ポケ
  // (ガブリアス) に対応する画像が public 側にない場合もあるので、fixture 側に隔離した
  // pokemons/ を指せるよう OG_POKEMON_IMAGE_DIR で差し替える。
  OG_POKEMON_IMAGE_DIR: pokemonImageDir,
  SITE_URL: 'https://example.test',
  SITE_BASE: '/',
};

console.log(`[smoke] Building with CONTENT_ROOT=${contentRoot}`);
// `bunx` は runtime fetch (サプライチェーン攻撃の表面積を広げる)。
// `bun install --frozen-lockfile` で pin された astro の binstub を直接呼ぶ。
const astroBin = resolve(cwd, 'node_modules/.bin/astro');
const build = spawnSync(astroBin, ['build'], { stdio: 'inherit', env });
if (build.status !== 0) {
  console.error('[smoke] astro build failed');
  process.exit(build.status ?? 1);
}

interface Check {
  path: string;
  expected: boolean;
  label: string;
}

const checks: Check[] = [
  { path: 'dist/teams/full/index.html', expected: true, label: 'full team is published' },
  { path: 'dist/teams/drafty/index.html', expected: false, label: 'unpublished team is hidden (published:false filtered)' },
  { path: 'dist/teams/legacy/index.html', expected: false, label: 'legacy MD without frontmatter is skipped' },
  // Astro の glob loader は id を小文字化するため、URL は lowercase。meta.json の
  // 解決は filePath ベースで行う必要がある（case-sensitive な Linux CI で再発防止）。
  { path: 'dist/teams/upper-case-guard/index.html', expected: true, label: 'uppercase-filename team lowercases to slug' },
  { path: 'dist/teams/index.html', expected: true, label: 'teams index is rendered' },
  { path: 'dist/blog/hello/index.html', expected: true, label: 'blog fixture is published' },
  { path: 'dist/blog/index.html', expected: true, label: 'blog index is rendered' },
  { path: 'dist/index.html', expected: true, label: 'root index is rendered' },
  // OG PNG endpoints
  { path: 'dist/og/teams/full.png', expected: true, label: 'team OG image generated (full)' },
  { path: 'dist/og/teams/upper-case-guard.png', expected: true, label: 'team OG image generated (UPPER-case-guard, lowercased)' },
  { path: 'dist/og/blog/hello.png', expected: true, label: 'blog OG image generated (hello)' },
  { path: 'dist/og/default.png', expected: true, label: 'default OG image copied from public/' },
];

let failed = 0;
for (const c of checks) {
  const full = resolve(cwd, c.path);
  const ok = existsSync(full) === c.expected;
  const mark = ok ? '✅ PASS' : '❌ FAIL';
  const expectation = c.expected ? 'exists' : 'does not exist';
  console.log(`${mark}: ${c.label} — expected to ${expectation} — ${c.path}`);
  if (!ok) failed++;
}

interface ContentCheck {
  path: string;
  needle: string;
  label: string;
}

const contentChecks: ContentCheck[] = [
  { path: 'dist/teams/full/index.html', needle: 'member-detail', label: 'full team renders per-member detail sections' },
  { path: 'dist/teams/full/index.html', needle: '先発で展開を作る高速物理アタッカー', label: 'full team renders role prose as detail body' },
  { path: 'dist/teams/full/index.html', needle: '個別解説', label: 'full team renders 2-chapter layout (個別解説)' },
  { path: 'dist/teams/full/index.html', needle: '構築コンセプト', label: 'full team renders concept chapter' },
  { path: 'dist/teams/full/index.html', needle: '高速物理ドラゴンで先発制圧', label: 'full team renders concept body prose' },
  { path: 'dist/teams/full/index.html', needle: 'damage-calcs', label: 'full team renders damage-calcs section' },
  { path: 'dist/teams/full/index.html', needle: 'defense-matrix', label: 'full team renders defense-matrix section' },
  { path: 'dist/teams/full/index.html', needle: 'coverage', label: 'full team renders coverage section' },
  { path: 'dist/teams/full/index.html', needle: '表選出', label: 'full team renders primary selection section' },
  { path: 'dist/teams/full/index.html', needle: '裏選出', label: 'full team renders alternate selection section' },
  // uppercase ファイル名でも meta.json が解決され、本文が空でないことを守る。
  { path: 'dist/teams/upper-case-guard/index.html', needle: 'member-detail', label: 'uppercase-filename team resolves meta.json (member-detail rendered)' },
  { path: 'dist/teams/upper-case-guard/index.html', needle: '構築コンセプト', label: 'uppercase-filename team resolves meta.json (concept chapter rendered)' },
  { path: 'dist/teams/index.html', needle: 'ガブリアス軸構築', label: 'teams index lists full team' },
  { path: 'dist/teams/index.html', needle: '未公開の試作構築', label: 'teams index does NOT list drafty', expectedMissing: true } as ContentCheck & { expectedMissing: boolean },
  // OG / twitter meta tags on article pages
  { path: 'dist/teams/full/index.html', needle: '<meta property="og:image" content="https://example.test/og/teams/full.png"', label: 'team og:image is absolute URL with correct path' },
  { path: 'dist/teams/full/index.html', needle: '<meta name="twitter:card" content="summary_large_image"', label: 'team page has twitter large card' },
  { path: 'dist/teams/full/index.html', needle: '<link rel="canonical" href="https://example.test/', label: 'team page canonical is absolute' },
  { path: 'dist/blog/hello/index.html', needle: '<meta property="og:image" content="https://example.test/og/blog/hello.png"', label: 'blog og:image is absolute URL with correct path' },
  // Root page falls back to default.png
  { path: 'dist/index.html', needle: '<meta property="og:image" content="https://example.test/og/default.png"', label: 'root og:image falls back to default.png' },
];

for (const c of contentChecks) {
  const full = resolve(cwd, c.path);
  const expectMissing = (c as ContentCheck & { expectedMissing?: boolean }).expectedMissing === true;
  if (!existsSync(full)) {
    console.log(`❌ FAIL: ${c.label} — file missing ${c.path}`);
    failed++;
    continue;
  }
  const body = readFileSync(full, 'utf-8');
  const found = body.includes(c.needle);
  const ok = expectMissing ? !found : found;
  const mark = ok ? '✅ PASS' : '❌ FAIL';
  const mode = expectMissing ? 'must NOT contain' : 'contains';
  console.log(`${mark}: ${c.label} — ${mode} "${c.needle}"`);
  if (!ok) failed++;
}

interface PngCheck {
  path: string;
  minBytes?: number;
  width?: number;
  height?: number;
  label: string;
}

const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const pngChecks: PngCheck[] = [
  // 100KB 閾値: 軸ポケ画像が埋め込まれた場合 (data URL 経由で base64 化) は PNG 自体が
  // 大きくなる。fallback #1a1a1a 単色なら 20KB 程度に収まる。閾値を高めにすることで
  // 「軸ポケ画像解決が silent に壊れてフォールバックが出続ける」回帰を検知する。
  { path: 'dist/og/teams/full.png', minBytes: 100_000, width: 1200, height: 630, label: 'team OG embeds axis image (size > 100KB) and 1200x630' },
  { path: 'dist/og/teams/upper-case-guard.png', minBytes: 100_000, width: 1200, height: 630, label: 'upper-case team OG embeds axis image and 1200x630' },
  { path: 'dist/og/blog/hello.png', minBytes: 5_000, width: 1200, height: 630, label: 'blog OG has valid size and 1200x630 dimensions' },
  { path: 'dist/og/default.png', minBytes: 5_000, width: 1200, height: 630, label: 'default OG has valid size and 1200x630 dimensions' },
];

for (const c of pngChecks) {
  const full = resolve(cwd, c.path);
  if (!existsSync(full)) {
    console.log(`❌ FAIL: ${c.label} — file missing ${c.path}`);
    failed++;
    continue;
  }
  const size = statSync(full).size;
  if (c.minBytes && size < c.minBytes) {
    console.log(`❌ FAIL: ${c.label} — size ${size} < ${c.minBytes}`);
    failed++;
    continue;
  }
  const buf = readFileSync(full);
  if (!buf.subarray(0, 8).equals(PNG_SIG)) {
    console.log(`❌ FAIL: ${c.label} — not a valid PNG (bad signature)`);
    failed++;
    continue;
  }
  // IHDR chunk: bytes 16-19 = width, 20-23 = height (big-endian uint32)
  const width = buf.readUInt32BE(16);
  const height = buf.readUInt32BE(20);
  if (c.width && width !== c.width) {
    console.log(`❌ FAIL: ${c.label} — width ${width} !== ${c.width}`);
    failed++;
    continue;
  }
  if (c.height && height !== c.height) {
    console.log(`❌ FAIL: ${c.label} — height ${height} !== ${c.height}`);
    failed++;
    continue;
  }
  console.log(`✅ PASS: ${c.label}`);
}

// Cross-page check: og:image must differ between two distinct team articles.
// Guards against accidental fallback (all pages pointing to default.png).
const fullOg = readMetaContent('dist/teams/full/index.html', 'og:image');
const upperOg = readMetaContent('dist/teams/upper-case-guard/index.html', 'og:image');
if (fullOg && upperOg && fullOg !== upperOg) {
  console.log('✅ PASS: two team articles have distinct og:image URLs');
} else {
  console.log(`❌ FAIL: team og:image URLs expected to differ — full=${fullOg ?? 'missing'} upper=${upperOg ?? 'missing'}`);
  failed++;
}

function readMetaContent(relPath: string, property: string): string | null {
  const full = resolve(cwd, relPath);
  if (!existsSync(full)) return null;
  const body = readFileSync(full, 'utf-8');
  const re = new RegExp(`<meta (?:property|name)="${property}" content="([^"]+)"`);
  const m = body.match(re);
  return m ? m[1] : null;
}

if (failed > 0) {
  console.error(`[smoke] ${failed} assertion(s) failed`);
  process.exit(1);
}
console.log('[smoke] All assertions passed');
