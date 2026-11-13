// Copies the dart2js bundle into dist/dart/, where the loader finds it.
import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = resolve(root, '../at_client_wasm/build/at_client_web.js');
const target = resolve(root, 'dist/dart/at_client.js');

if (!existsSync(source)) {
  console.error(`missing ${source}; run packages/at_client_wasm/tool/build.sh first`);
  process.exit(1);
}
mkdirSync(dirname(target), { recursive: true });
copyFileSync(source, target);
