import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { canonicalAtSign } from '../demo/atsign.js';

const demo = resolve(import.meta.dirname, '../demo');
const pages = ['index.html', 'talk.html'];

/** Every source file under [dir], leaving out build output and installed packages. */
function sources(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    if (name === 'dist' || name === 'node_modules') return [];
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sources(path);
    return /\.(ts|js|mjs|html|css)$/.test(name) ? [path] : [];
  });
}

describe('demo sources', () => {
  const files = existsSync(demo) ? sources(demo) : [];

  it('has both pages and their scripts', () => {
    for (const name of ['index.html', 'main.ts', 'talk.html', 'talk.ts']) {
      expect(existsSync(join(demo, name)), name).toBe(true);
    }
  });

  it('never assigns or parses markup from a string', () => {
    const markup = /innerHTML|outerHTML|insertAdjacentHTML|document\.write|createContextualFragment|DOMParser/;
    for (const file of files) expect(readFileSync(file, 'utf8'), file).not.toMatch(markup);
  });

  it('keeps nothing in web storage', () => {
    const storage = /localStorage|sessionStorage|indexedDB|document\.cookie/;
    for (const file of files) expect(readFileSync(file, 'utf8'), file).not.toMatch(storage);
  });

  it('offers no key file ingress', () => {
    const ingress = /type=["']?file|type\s*=\s*['"]file|showOpenFilePicker|\.atKeys/;
    for (const file of files) expect(readFileSync(file, 'utf8'), file).not.toMatch(ingress);
  });

  it.each(pages)('%s carries a CSP with no wasm-unsafe-eval and no unsafe-eval', (page) => {
    const html = readFileSync(join(demo, page), 'utf8');
    const csp = /<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]+)"/.exec(html)?.[1];
    expect(csp).toBeDefined();
    expect(csp).not.toContain('wasm-unsafe-eval');
    expect(csp).not.toMatch(/'unsafe-eval'|'unsafe-inline'|\*(?!\.)/);
    expect(csp).toContain("default-src 'none'");
  });

  it('takes the CRAM secret in a password input', () => {
    const html = readFileSync(join(demo, 'index.html'), 'utf8');
    expect(html).toMatch(/<input[^>]*id="cram"[^>]*type="password"|<input[^>]*type="password"[^>]*id="cram"/);
  });
});

describe('demo atSign comparison', () => {
  it('puts atSigns in one form: trimmed, lower-case, leading @', () => {
    expect(canonicalAtSign(' Alice ')).toBe('@alice');
    expect(canonicalAtSign('@ALICE')).toBe('@alice');
    expect(canonicalAtSign('@alice')).toBe(canonicalAtSign('alice'));
    expect(canonicalAtSign('@alice')).not.toBe(canonicalAtSign('@bob'));
  });

  it('talk.ts labels a message with the event sender and compares canonical atSigns', () => {
    const source = readFileSync(join(demo, 'talk.ts'), 'utf8');
    expect(source).toMatch(/bubble\(from,/);
    expect(source).toMatch(/canonicalAtSign\(from\) !== canonicalAtSign\(own\)/);
  });
});
