// E7 — two tabs, one database. Tab A writes; tab B opens the same database
// (verify) then also writes; both are killed; a third page verifies.
//   node e7.mjs [--vfs indexedDb|simpleOpfs]
import http from 'node:http';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { chromium } from 'playwright';

const here = path.dirname(fileURLToPath(import.meta.url));
const site = path.join(here, '../../../build/vfs_lab');
const { values: o } = parseArgs({ options: { vfs: { type: 'string', default: 'indexedDb' } } });
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
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const profile = await mkdtemp(path.join(tmpdir(), 'vfs-lab-e7-'));
const ctx = await chromium.launchPersistentContext(profile, { headless: true });

async function open(query) {
  const page = await ctx.newPage();
  const s = { acked: 0, result: undefined };
  const ready = new Promise((r) => (s.on = r));
  await page.exposeFunction('lab_ack', (i) => (s.acked = Math.max(s.acked, Number(i))));
  await page.exposeFunction('lab_result', (j) => { s.result = JSON.parse(j); s.on(s.result); });
  await page.goto(`${base}/index.html?${new URLSearchParams({ vfs: o.vfs, ...query })}`);
  return { page, s, ready: () => Promise.race([ready, sleep(20000).then(() => ({ opened: false, error: 'timeout' }))]) };
}

const db = `e7_${o.vfs}_${Date.now()}`;
const A = await open({ mode: 'write', db, flush: '1' });
await sleep(1500);
const B = await open({ mode: 'write', db, flush: '1' }); // second writer, same db
await sleep(2500);
// B never reports a result while writing; if opening failed it reports at once.
const bOpenError = B.s.result ?? null;
const out = { vfs: o.vfs, aAcked: A.s.acked, bAcked: B.s.acked, bOpenError };
await A.page.close(); await B.page.close();
await sleep(500);
const V = await open({ mode: 'verify', db });
out.verify = await V.ready();
await ctx.close(); server.close();
await rm(profile, { recursive: true, force: true });
console.log('E7 ' + JSON.stringify(out));
