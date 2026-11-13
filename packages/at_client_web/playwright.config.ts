import { defineConfig } from '@playwright/test';

const port = Number(process.env.E2E_PORT ?? 4173);

export default defineConfig({
  testDir: 'e2e',
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  use: {
    browserName: 'chromium',
    headless: true,
    // Maps a name to the loopback server that Chromium, unlike localhost, treats as insecure over http.
    launchOptions: { args: ['--host-resolver-rules=MAP insecure.test 127.0.0.1'] },
  },
  webServer: {
    command: 'node e2e/server.mjs',
    url: `http://127.0.0.1:${port}/`,
    reuseExistingServer: false,
  },
});
