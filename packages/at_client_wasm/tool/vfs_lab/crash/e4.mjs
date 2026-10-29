// E4 — open latency / db size vs key count (and E5 browser matrix via --browser).
//   node e4.mjs [--browser chromium|firefox|webkit] [--sizes 1000,10000,100000]
import http from 'node:http';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import * as pw from 'playwright';

const here = path.dirname(fileURLToPath(import.meta.url));
const { values: o } = parseArgs({ options: {
  browser: { type: 'string', default: 'chromium' },
  sizes: { type: 'string', default: '1000,10000,100000' },
  reps: { type: 'string', default: '3' },
} });
const site = path.join(here, '../../../build/vfs_lab');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const server = http.createServer(async (req, res) => {
  try {
    const file = path.join(site, new URL(req.url, 'http://x').pathname);
    res.setHeader('content-type', MIME[path.extname(file)] ?? 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.statusCode = 404; res.end(); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

const profile = await mkdtemp(path.join(tmpdir(), 'vfs-lab-e4-'));
const launcher = pw[o.browser];
const browser = await launcher.launch({ headless: true });
const ctx = await browser.newContext();
const ua = await (async () => { const p = await ctx.newPage(); const u = await p.evaluate(() => navigator.userAgent); await p.close(); return u; })();

async function step(query) {
  const page = await ctx.newPage();
  const result = new Promise((r) => page.exposeFunction('lab_result', (j) => r(JSON.parse(j))));
  await page.exposeFunction('lab_ack', () => {});
  await page.goto(`${base}/e4.html?${new URLSearchParams(query)}`);
  const r = await Promise.race([result, new Promise((r) => setTimeout(() => r({ error: 'timeout' }), 300_000))]);
  await page.close();
  return r;
}

const out = [];
for (const vfs of ['indexedDb', 'simpleOpfs']) {
  for (const n of o.sizes.split(',').map(Number)) {
    const db = `e4_${vfs}_${n}_${Date.now()}`;
    const populate = await step({ vfs, db, n, phase: 'populate' });
    const opens = [];
    for (let i = 0; i < Number(o.reps); i++) opens.push(await step({ vfs, db, n, phase: 'open' }));
    out.push({ vfs, n, populate, opens });
    console.error(vfs, n, JSON.stringify(populate), JSON.stringify(opens[0]));
  }
}
await ctx.close(); await browser.close(); server.close();
await rm(profile, { recursive: true, force: true });
const dir = path.join(site, 'results'); await mkdir(dir, { recursive: true });
const summary = { experiment: 'E4', browser: o.browser, ua, out };
await writeFile(path.join(dir, `e4-${o.browser}.json`), JSON.stringify(summary, null, 1));
console.log('done', o.browser);
