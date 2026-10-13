// E3/E4/E7 on real Safari without safaridriver (which needs an admin password to
// enable). Safari is opened with `open -a Safari <url>`; an injected shim POSTs
// each page's result back to this server and terminates the page's workers so
// SimpleOPFS access handles are released between steps.
//   node safari.mjs
import http from 'node:http';
import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const site = path.join(here, '../../../build/vfs_lab');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const SHIM = `<script>(()=>{const W=window.Worker,ws=[];window.Worker=function(u,o){const w=new W(u,o);ws.push(w);return w};window.Worker.prototype=W.prototype;
const q=new URLSearchParams(location.search),tag=q.get('tag');
const post=(kind,v)=>fetch('/report?tag='+tag+'&kind='+kind,{method:'POST',body:String(v)}).catch(()=>{});
post('ua',navigator.userAgent);
window.lab_result=j=>{post('result',j).finally(()=>ws.forEach(w=>w.terminate()))};
const t0=Date.now();let done=0;
window.lab_ack=i=>{window.__a=Math.max(window.__a||0,+i);
if(q.get('mode')==='write'&&!done&&Date.now()-t0>6000){done=1;post('ack',window.__a).finally(()=>{ws.forEach(w=>w.terminate());location.href='about:blank'})}};
</script>`;

const reports = new Map(); // tag -> {kind: value}
const stops = new Set();
const server = http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  if (process.env.SAFARI_DEBUG) console.error('req', req.method, u.pathname, u.search.slice(0, 80));
  if (u.pathname === '/report') {
    let body = ''; for await (const c of req) body += c;
    const r = reports.get(u.searchParams.get('tag')) ?? {};
    r[u.searchParams.get('kind')] = body; reports.set(u.searchParams.get('tag'), r);
    return res.end('ok');
  }
  if (u.pathname === '/stop') return res.end(stops.has(u.searchParams.get('tag')) ? 'stop' : 'go');
  try {
    const file = path.join(site, u.pathname);
    res.setHeader('content-type', MIME[path.extname(file)] ?? 'application/octet-stream');
    let body = await readFile(file);
    if (file.endsWith('.html')) body = Buffer.from(SHIM + body);
    res.end(body);
  } catch { res.statusCode = 404; res.end(); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const open = (url) => execFileSync('open', ['-a', 'Safari', `${base}/${url}`]);
const wait = async (tag, kind = 'result', ms = 120000) => {
  const t = Date.now();
  while (Date.now() - t < ms) { const v = reports.get(tag)?.[kind]; if (v !== undefined) return v; await sleep(200); }
  return null;
};
let n = 0;
async function run(page, query, ms) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const tag = `t${++n}`;
    open(`${page}?${new URLSearchParams({ ...query, tag })}`);
    const raw = await wait(tag, 'result', ms);
    const r = raw === null ? { error: 'timeout' } : JSON.parse(raw);
    if (!/NoModificationAllowed|InvalidState/.test(JSON.stringify(r)) || page === 'e3.html' || query.mode) return r;
    await sleep(700); // previous step's worker may still be terminating
  }
  return { error: 'lock never released' };
}

const version = execFileSync('defaults', ['read', '/Applications/Safari.app/Contents/Info', 'CFBundleShortVersionString']).toString().trim();
const out = { safari: version, E3: {}, E4: [], E7: {} };
const id = Date.now();
if (!process.env.E7ONLY) for (const r of ['same-worker', 'same-dir', 'one-worker']) out.E3[r] = await run('e3.html', { run: r, id }, 60000);
console.error('E3', JSON.stringify(out.E3));
for (const vfs of process.env.E7ONLY || process.env.E3ONLY ? [] : ['indexedDb', 'simpleOpfs']) {
  for (const rows of [1000, 10000, 100000]) {
    const db = `e4_${vfs}_${rows}_${Date.now()}`;
    const populate = await run('e4.html', { vfs, db, n: rows, phase: 'populate' }, 300000);
    const opens = [];
    for (let i = 0; i < 2; i++) opens.push(await run('e4.html', { vfs, db, n: rows, phase: 'open' }, 300000));
    out.E4.push({ vfs, n: rows, populate, opens });
    console.error(vfs, rows, JSON.stringify(populate), JSON.stringify(opens[0]));
  }
}
for (const vfs of process.env.E3ONLY ? [] : ['indexedDb', 'simpleOpfs']) {
  const db = `e7_${vfs}_${Date.now()}`;
  const q = (tag, extra) => `index.html?${new URLSearchParams({ vfs, db, tag, ...extra })}`;
  open(q(`a${vfs}`, { mode: 'write', flush: '1' }));
  await sleep(2500);
  open(q(`b${vfs}`, { mode: 'write', flush: '1' }));
  await sleep(3500);
  const bResult = reports.get(`b${vfs}`)?.result;
  const aAck = await wait(`a${vfs}`, 'ack', 15000);
  const bAck = await wait(`b${vfs}`, 'ack', 15000);
  await sleep(1500);
  const verify = await run('index.html', { vfs, db, mode: 'verify' }, 60000);
  out.E7[vfs] = { aAck, bAck, bOpenError: bResult && JSON.parse(bResult), verify: { ...verify, torn: verify.torn?.length } };
  console.error('E7', vfs, JSON.stringify(out.E7[vfs]));
}
if (process.env.SAFARI_DEBUG) console.error('reports', JSON.stringify([...reports], null, 0).slice(0, 3000));
server.close();
await mkdir(path.join(site, 'results'), { recursive: true });
await writeFile(path.join(site, process.env.E7ONLY ? 'results/e7-safari.json' : 'results/e5-safari.json'), JSON.stringify(out, null, 1));
console.log('done Safari', version);
