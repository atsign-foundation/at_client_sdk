// E2 — crash consistency. For each run: write transactions in a fresh page,
// crash its renderer at a random moment, then open the database in a new page
// and check the writeTx invariant.
//
//   node e2.mjs --vfs indexedDb|simpleOpfs [--flush] [--runs 200] [--site ../../../build/vfs_lab]
//
// Fault model: CDP `Page.crash` kills the renderer (and its workers), so writes
// still buffered in the page are lost. It does NOT model power loss or a
// browser-process kill; a committed IndexedDB write survives either way.
import http from 'node:http';
import { appendFile, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { chromium } from 'playwright';

const here = path.dirname(fileURLToPath(import.meta.url));
const { values: opts } = parseArgs({
  options: {
    vfs: { type: 'string' },
    runs: { type: 'string', default: '200' },
    site: { type: 'string', default: path.join(here, '../../../build/vfs_lab') },
    out: { type: 'string', default: path.join(here, '../../../build/vfs_lab/results') },
    flush: { type: 'boolean', default: false },
    'min-ms': { type: 'string', default: '150' },
    'max-ms': { type: 'string', default: '1500' },
  },
});
if (!['indexedDb', 'simpleOpfs'].includes(opts.vfs)) {
  throw new Error('--vfs must be indexedDb or simpleOpfs');
}
const runs = Number(opts.runs);
const [minMs, maxMs] = [Number(opts['min-ms']), Number(opts['max-ms'])];

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const server = http.createServer(async (req, res) => {
  try {
    const file = path.join(opts.site, new URL(req.url, 'http://x').pathname);
    res.setHeader('content-type', MIME[path.extname(file)] ?? 'application/octet-stream');
    res.end(await readFile(file));
  } catch {
    res.statusCode = 404;
    res.end();
  }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const withTimeout = (p, ms) => Promise.race([p, sleep(ms).then(() => undefined)]);

async function openPage(ctx, query) {
  const page = await ctx.newPage();
  const state = { acked: 0, result: undefined, onResult: undefined };
  state.resultReady = new Promise((r) => (state.onResult = r));
  await page.exposeFunction('lab_ack', (i) => (state.acked = Math.max(state.acked, Number(i))));
  await page.exposeFunction('lab_result', (json) => state.onResult(JSON.parse(json)));
  await page.goto(`${base}/index.html?${new URLSearchParams(query)}`);
  return { page, state };
}

async function crash(ctx, page) {
  const cdp = await ctx.newCDPSession(page);
  await withTimeout(cdp.send('Page.crash').catch(() => {}), 2000);
  await page.close().catch(() => {});
}

// A just-crashed renderer may hold SimpleOPFS access handles for a moment.
const isLockError = (r) => !r.opened && /NoModification|Access Handle|locked/i.test(r.error);

async function verify(ctx, db) {
  let result;
  for (let attempt = 0; attempt < 10; attempt++) {
    const { page, state } = await openPage(ctx, { mode: 'verify', vfs: opts.vfs, db });
    result = (await withTimeout(state.resultReady, 20_000)) ?? { opened: false, error: 'verify timed out' };
    await page.close().catch(() => {});
    if (!isLockError(result)) break;
    await sleep(300);
  }
  return result;
}

function classify(acked, r) {
  if (!r.opened) return 'unopenable';
  if (!r.integrityOk) return 'corrupt';
  if (r.torn.length || !r.counterOk) return 'torn';
  if (r.maxCommit < acked) return 'lostAcked';
  return 'clean';
}

await mkdir(opts.out, { recursive: true });
const tag = opts.vfs + (opts.flush ? '-flush' : '');
const jsonl = path.join(opts.out, `e2-${tag}.jsonl`);
await writeFile(jsonl, '');
const profile = await mkdtemp(path.join(tmpdir(), 'vfs-lab-'));
const ctx = await chromium.launchPersistentContext(profile, { headless: true });
const probe = await ctx.newPage();
const browserVersion = (await probe.evaluate(() => navigator.userAgent)).match(/Chrome\/([\d.]+)/)?.[1];
await probe.close();

const tally = { clean: 0, lostAcked: 0, torn: 0, corrupt: 0, unopenable: 0 };
let ackedLost = 0;
const stamp = Date.now();
for (let run = 1; run <= runs; run++) {
  const db = `e2_${stamp}_${run}`;
  const { page, state } = await openPage(ctx, { mode: 'write', vfs: opts.vfs, db, flush: opts.flush ? '1' : '0' });
  await sleep(minMs + Math.random() * (maxMs - minMs));
  const acked = state.acked;
  await crash(ctx, page);

  const result = await verify(ctx, db);
  const verdict = classify(acked, result);
  tally[verdict]++;
  if (result.opened && result.maxCommit < acked) ackedLost++;
  await appendFile(jsonl, JSON.stringify({ run, db, acked, verdict, ...result }) + '\n');
  if (run % 10 === 0) console.error(`run ${run}/${runs}`, tally);
}
await ctx.close();
server.close();
await rm(profile, { recursive: true, force: true });

const summary = {
  experiment: 'E2',
  vfs: tag,
  browser: 'chromium',
  browserVersion,
  metrics: { runs, ...tally, runsWithAckedWriteLost: ackedLost },
  notes: `Page.crash at ${minMs}-${maxMs} ms; renderer kill only, not power loss`,
};
console.log('LABRESULT ' + JSON.stringify(summary));
