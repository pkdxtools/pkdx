export interface SiteConfig {
  site_name: string;
  author: string | null;
  enabled: boolean;
}

export const DEFAULT_SITE_CONFIG: SiteConfig = {
  site_name: 'pkdx teams',
  author: null,
  enabled: true,
};

export function parseSiteConfig(jsonText: string | null): SiteConfig {
  if (!jsonText) return { ...DEFAULT_SITE_CONFIG };
  let raw: unknown;
  try {
    raw = JSON.parse(jsonText);
  } catch {
    return { ...DEFAULT_SITE_CONFIG };
  }
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return { ...DEFAULT_SITE_CONFIG };
  }
  const input = raw as Record<string, unknown>;
  const result: SiteConfig = { ...DEFAULT_SITE_CONFIG };
  if (typeof input.site_name === 'string') result.site_name = input.site_name;
  if (typeof input.author === 'string') result.author = input.author;
  if (input.author === null) result.author = null;
  if (typeof input.enabled === 'boolean') result.enabled = input.enabled;
  return result;
}

import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export function loadSiteConfig(): SiteConfig {
  try {
    const candidate = resolve(process.cwd(), '../box/site.config.json');
    if (!existsSync(candidate)) return { ...DEFAULT_SITE_CONFIG };
    return parseSiteConfig(readFileSync(candidate, 'utf-8'));
  } catch {
    return { ...DEFAULT_SITE_CONFIG };
  }
}
