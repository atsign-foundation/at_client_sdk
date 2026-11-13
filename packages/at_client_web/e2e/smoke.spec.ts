import { expect, test } from '@playwright/test';

const port = Number(process.env.E2E_PORT ?? 4173);

test('the bundle loads and prfSupported resolves to a boolean', async ({ page }) => {
  await page.goto(`http://localhost:${port}/`);
  await page.waitForFunction(() => (window as any).e2eReady === true);
  const supported = await page.evaluate(() => (window as any).AtClient.prfSupported());
  expect(typeof supported).toBe('boolean');
});

test('create on a non-secure page rejects with unsupported', async ({ page }) => {
  await page.goto(`http://insecure.test:${port}/`);
  await page.waitForFunction(() => (window as any).e2eReady === true);
  expect(await page.evaluate(() => window.isSecureContext)).toBe(false);
  const failure = await page.evaluate(async () => {
    try {
      await (window as any).AtClient.create({ atSign: '@alice', namespace: 'e2e' });
      return null;
    } catch (error) {
      const e = error as { name: string; code: string };
      return { isAtError: error instanceof (window as any).AtError, name: e.name, code: e.code };
    }
  });
  expect(failure).toEqual({ isAtError: true, name: 'AtError', code: 'unsupported' });
});
