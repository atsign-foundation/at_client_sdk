// Serves dist/ at /dist/ and the e2e page at /, on 127.0.0.1.
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.env.E2E_PORT ?? 4173);
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.map': 'application/json',
};

/** The file a request path names, or undefined when it is outside the served trees. */
function resolveFile(urlPath) {
  const path = normalize(decodeURIComponent(urlPath));
  const file = path === '/' ? join(root, 'e2e/page/index.html')
    : path.startsWith('/dist/') ? join(root, path)
    : undefined;
  if (file === undefined || !file.startsWith(root) || !existsSync(file) || !statSync(file).isFile()) {
    return undefined;
  }
  return file;
}

createServer((request, response) => {
  const file = resolveFile(new URL(request.url ?? '/', 'http://localhost').pathname);
  if (file === undefined) {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' });
  createReadStream(file).pipe(response);
}).listen(port, '127.0.0.1', () => console.log(`serving at http://127.0.0.1:${port}/`));
