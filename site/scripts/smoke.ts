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
const build = spawnSync('bunx', ['astro', 'build'], { stdio: 'inherit', env });
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
  { path: 'dist/teams/drafty/index.html', expected: false, label: 'drafty team is hidden (draft:true filtered)' },
  { path: 'dist/teams/legacy/index.html', expected: false, label: 'legacy MD without frontmatter is skipped' },
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
  { path: 'dist/teams/full/index.html', needle: 'role-label', label: 'full team renders role card markup' },
  { path: 'dist/teams/full/index.html', needle: '先発で展開を作る高速物理アタッカー', label: 'full team renders role prose verbatim' },
  { path: 'dist/teams/full/index.html', needle: 'damage-calcs', label: 'full team renders damage-calcs section' },
  { path: 'dist/teams/full/index.html', needle: 'defense-matrix', label: 'full team renders defense-matrix section' },
  { path: 'dist/teams/full/index.html', needle: 'coverage', label: 'full team renders coverage section' },
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
