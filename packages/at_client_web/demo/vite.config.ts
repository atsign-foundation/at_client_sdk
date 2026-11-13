import { resolve } from 'node:path';
import { defineConfig } from 'vite';

const root = import.meta.dirname;
const dist = resolve(root, '../dist');

export default defineConfig({
  root,
  base: './',
  resolve: { alias: { '@atsign/at_client_web': resolve(dist, 'index.js') } },
  server: { hmr: false, fs: { allow: [resolve(root, '..')] } },
  preview: { port: Number(process.env.DEMO_PORT ?? 4174), strictPort: true },
  build: {
    outDir: resolve(root, 'dist'),
    emptyOutDir: true,
    assetsInlineLimit: 0,
    rollupOptions: { input: { index: resolve(root, 'index.html'), talk: resolve(root, 'talk.html') } },
  },
});
