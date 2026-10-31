// E3 — can SimpleOPFS host several databases (one per atSign/enrollment)?
//   [BROWSER=firefox|webkit] node e3.mjs
import http from 'node:http';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as pw from 'playwright';
const chromium = pw[process.env.BROWSER ?? 'chromium'];

const here = path.dirname(fileURLToPath(import.meta.url));
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

const profile = await mkdtemp(path.join(tmpdir(), 'vfs-lab-e3-'));
const launcher = chromium;
const browser = await launcher.launch({ headless: true });
const ctx = await browser.newContext();
const out = {};
for (const run of ['same-worker', 'same-dir', 'one-worker']) {
  const page = await ctx.newPage();
  const result = new Promise((r) => page.exposeFunction('lab_result', (j) => r(JSON.parse(j))));
  await page.exposeFunction('lab_ack', () => {});
  await page.goto(`${base}/e3.html?run=${run}&id=${Date.now()}`);
  out[run] = await Promise.race([result, new Promise((r) => setTimeout(() => r('timeout'), 30000))]);
  await page.close();
}
await ctx.close(); await browser.close(); server.close();
await rm(profile, { recursive: true, force: true });
console.log('E3 ' + JSON.stringify(out, null, 1));
