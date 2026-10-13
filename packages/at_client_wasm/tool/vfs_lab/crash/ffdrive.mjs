// E5 on stock Firefox, driven over raw WebDriver (geckodriver). Playwright's
// patched Firefox does not launch on this machine. Runs E3, E4 and E7; E2 needs
// CDP's Page.crash, which Firefox lacks, so it is not run.
//   Launch Firefox through Launch Services (direct exec cannot find its profile on
//   this macOS):  open -n -a /path/Firefox.app --args --headless --no-remote --marionette --profile DIR
//   then:  GECKODRIVER=/path/geckodriver node ffdrive.mjs
import http from 'node:http';
import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const site = path.join(here, '../../../build/vfs_lab');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const SHIM = '<script>window.lab_result=j=>{window.__r=j};window.lab_ack=i=>{window.__a=Math.max(window.__a||0,Number(i))}</script>';
const server = http.createServer(async (req, res) => {
  try {
    const file = path.join(site, new URL(req.url, 'http://x').pathname);
    res.setHeader('content-type', MIME[path.extname(file)] ?? 'application/octet-stream');
    let body = await readFile(file);
    if (file.endsWith('.html')) body = Buffer.from(SHIM + body);
    res.end(body);
  } catch { res.statusCode = 404; res.end(); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

const gd = spawn(process.env.GECKODRIVER, ['--port', '4444', '--connect-existing', '--marionette-port', '2828'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
await sleep(1500);
const wd = async (method, p, body) => {
  const r = await fetch(`http://127.0.0.1:4444${p}`, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const j = await r.json();
  if (j.value?.error) throw new Error(`${j.value.error}: ${j.value.message}`);
  return j.value;
};
const s = await wd('POST', '/session', { capabilities: { alwaysMatch: { 'moz:firefoxOptions': { binary: '/private/tmp/ffstock/Firefox.app/Contents/MacOS/firefox' } } } });
const sid = s.sessionId;
const S = (p) => `/session/${sid}${p}`;
const ua = await (async () => { await wd('POST', S('/url'), { url: `${base}/index.html?mode=none` }); return (await wd('POST', S('/execute/sync'), { script: 'return navigator.userAgent', args: [] })); })();

// A page we just navigated away from may still hold its SimpleOPFS access handle
// for a moment (Chromium's harness closes the page instead), so retry lock errors.
async function run(url, ms = 60000) {
  for (let attempt = 0; attempt < 10; attempt++) {
    const r = await runOnce(url, ms);
    const text = JSON.stringify(r);
    if (!/NoModificationAllowed/.test(text) || url.startsWith('e3.html') || url.includes('mode=write')) return r;
    await sleep(500);
  }
  return runOnce(url, ms);
}

// Each run gets its own tab and closes it: navigating a tab away leaves the page
// (and its SimpleOPFS worker) alive in the back/forward cache, still holding the
// access handles.
async function runOnce(url, ms) {
  const home = await wd('GET', S('/window'));
  const tab = (await wd('POST', S('/window/new'), { type: 'tab' })).handle;
  await wd('POST', S('/window'), { handle: tab });
  try {
    await wd('POST', S('/url'), { url: `${base}/${url}` });
    const t = Date.now();
    while (Date.now() - t < ms) {
      const r = await wd('POST', S('/execute/sync'), { script: 'return window.__r ?? null', args: [] });
      if (r) return JSON.parse(r);
      await sleep(200);
    }
    return { error: 'timeout' };
  } finally {
    await wd('DELETE', S('/window'));
    await wd('POST', S('/window'), { handle: home });
    await sleep(150);
  }
}

const out = { ua, E3: {}, E4: [], E7: {} };
const id = Date.now();
for (const r of ['same-worker', 'same-dir', 'one-worker']) out.E3[r] = await run(`e3.html?run=${r}&id=${id}`);
console.error('E3', JSON.stringify(out.E3));
for (const vfs of ['indexedDb', 'simpleOpfs']) {
  for (const n of [1000, 10000, 100000]) {
    const db = `e4_${vfs}_${n}_${Date.now()}`;
    const populate = await run(`e4.html?vfs=${vfs}&db=${db}&n=${n}&phase=populate`, 300000);
    const opens = [];
    for (let i = 0; i < 2; i++) opens.push(await run(`e4.html?vfs=${vfs}&db=${db}&n=${n}&phase=open`, 300000));
    out.E4.push({ vfs, n, populate, opens });
    console.error(vfs, n, JSON.stringify(populate), JSON.stringify(opens[0]));
  }
}

// E7: two tabs, one db.
const home = await wd('GET', S('/window'));
for (const vfs of ['indexedDb', 'simpleOpfs']) {
  const db = `e7_${vfs}_${Date.now()}`;
  const q = (extra) => `index.html?${new URLSearchParams({ vfs, db, ...extra })}`;
  const openTab = async (extra) => {
    const handle = (await wd('POST', S('/window/new'), { type: 'tab' })).handle;
    await wd('POST', S('/window'), { handle });
    await wd('POST', S('/url'), { url: `${base}/${q(extra)}` });
    return handle;
  };
  const read = (script) => wd('POST', S('/execute/sync'), { script, args: [] });
  const tabA = await openTab({ mode: 'write', flush: '1' });
  await sleep(1500);
  const tabB = await openTab({ mode: 'write', flush: '1' });
  await sleep(2500);
  const bRes = await read('return [window.__r ?? null, window.__a ?? 0]');
  await wd('POST', S('/window'), { handle: tabA });
  const aAck = await read('return window.__a ?? 0');
  for (const h of [tabA, tabB]) {
    await wd('POST', S('/window'), { handle: h });
    await wd('DELETE', S('/window'));
  }
  await wd('POST', S('/window'), { handle: home });
  await sleep(500);
  const verify = await run(q({ mode: 'verify' }));
  out.E7[vfs] = { aAck, bOpenError: bRes[0] && JSON.parse(bRes[0]), bAck: bRes[1], verify: { ...verify, torn: verify.torn?.length } };
  console.error('E7', vfs, JSON.stringify(out.E7[vfs]));
}

await wd('DELETE', S(''));
gd.kill(); server.close();
await mkdir(path.join(site, 'results'), { recursive: true });
await writeFile(path.join(site, 'results/e5-firefox.json'), JSON.stringify(out, null, 1));
console.log('done', ua);
