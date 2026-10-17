// E6 — price of a worker hop: postMessage round-trip for a ~300 B and a 64 KB
// payload (the realistic bounds of a keystore row / a value). Echo worker, no SQLite.
//   [BROWSER=webkit] node e6.mjs
import * as pw from 'playwright';
const browser = await pw[process.env.BROWSER ?? 'chromium'].launch({ headless: true });
const page = await browser.newPage();
const out = await page.evaluate(async () => {
  const w = new Worker(URL.createObjectURL(new Blob(['onmessage=e=>postMessage(e.data)'])));
  const rtt = async (payload, n) => {
    for (let i = 0; i < 50; i++) await new Promise((r) => { w.onmessage = r; w.postMessage(payload); });
    const t = performance.now();
    for (let i = 0; i < n; i++) await new Promise((r) => { w.onmessage = r; w.postMessage(payload); });
    return (performance.now() - t) / n;
  };
  return { small_ms: await rtt('x'.repeat(300), 2000), large_ms: await rtt('x'.repeat(65536), 1000) };
});
console.log('E6', process.env.BROWSER ?? 'chromium', JSON.stringify(out));
await browser.close();
