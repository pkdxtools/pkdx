#!/usr/bin/env bun
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { resolve } from 'node:path';

const cwd = process.cwd();
const contentRoot = resolve(cwd, 'test/fixtures');
const distDir = resolve(cwd, 'dist');

if (existsSync(distDir)) {
  rmSync(distDir, { recursive: true, force: true });
}

const env = {
  ...process.env,
  CONTENT_ROOT: contentRoot,
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

if (failed > 0) {
  console.error(`[smoke] ${failed} assertion(s) failed`);
  process.exit(1);
}
console.log('[smoke] All assertions passed');
