import { describe, expect, it } from 'bun:test';
import { DEFAULT_SITE_CONFIG, parseSiteConfig } from '../src/lib/site-config';

describe('parseSiteConfig', () => {
  it('returns defaults when input is null', () => {
    expect(parseSiteConfig(null)).toEqual(DEFAULT_SITE_CONFIG);
  });

  it('returns defaults on invalid JSON', () => {
    expect(parseSiteConfig('not json at all')).toEqual(DEFAULT_SITE_CONFIG);
  });

  it('returns defaults on empty string', () => {
    expect(parseSiteConfig('')).toEqual(DEFAULT_SITE_CONFIG);
  });

  it('returns defaults on empty object', () => {
    expect(parseSiteConfig('{}')).toEqual(DEFAULT_SITE_CONFIG);
  });

  it('overlays partial fields onto defaults', () => {
    const result = parseSiteConfig('{"site_name":"My Team"}');
    expect(result.site_name).toBe('My Team');
    expect(result.author).toBe(DEFAULT_SITE_CONFIG.author);
    expect(result.enabled).toBe(DEFAULT_SITE_CONFIG.enabled);
  });

  it('accepts author as string', () => {
    const result = parseSiteConfig('{"author":"ushironoko"}');
    expect(result.author).toBe('ushironoko');
  });

  it('accepts enabled=false', () => {
    const result = parseSiteConfig('{"enabled":false}');
    expect(result.enabled).toBe(false);
  });

  it('ignores unknown keys without throwing', () => {
    const result = parseSiteConfig('{"site_name":"X","future":123}');
    expect(result.site_name).toBe('X');
  });

  it('falls back to defaults when JSON is an array', () => {
    expect(parseSiteConfig('[1,2,3]')).toEqual(DEFAULT_SITE_CONFIG);
  });

  it('falls back to defaults when JSON is null literal', () => {
    expect(parseSiteConfig('null')).toEqual(DEFAULT_SITE_CONFIG);
  });
});
