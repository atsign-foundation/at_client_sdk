import { expect, test, type Page } from '@playwright/test';

const port = Number(process.env.DEMO_PORT ?? 4174);

/** Loads [path] on the demo server and collects every console error and uncaught exception. */
async function load(page: Page, path: string): Promise<string[]> {
  const problems: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') problems.push(message.text());
  });
  page.on('pageerror', (error) => problems.push(error.message));
  await page.goto(`http://127.0.0.1:${port}/${path}`);
  return problems;
}

test('the demo page loads clean and renders the prfSupported indicator', async ({ page }) => {
  const problems = await load(page, 'index.html');
  const prf = page.locator('#prf');
  await expect(prf).toHaveAttribute('data-state', /^(supported|unsupported)$/);
  await expect(prf).toHaveText(/PRF (supported|unsupported)/);
  await expect(page.locator('#cram')).toHaveAttribute('type', 'password');
  expect(problems).toEqual([]);
});

test('the talk page loads clean and starts disconnected', async ({ page }) => {
  const problems = await load(page, 'talk.html');
  await expect(page.locator('#status')).toHaveAttribute('data-state', 'disconnected');
  await expect(page.locator('#send button')).toBeDisabled();
  expect(problems).toEqual([]);
});

test('a failed login shows the AtError code and keeps the secret out of the page log', async ({ page }) => {
  const problems = await load(page, 'index.html');
  await page.locator('#atSign').fill('@demo-nobody');
  await page.locator('#cram').fill('not-a-real-secret');
  await page.locator('#login').click();
  await expect(page.locator('#result')).toHaveAttribute('data-state', 'error');
  await expect(page.locator('#result')).toHaveText(/^[a-z_]+: /);
  expect(await page.locator('body').innerText()).not.toContain('not-a-real-secret');
  expect(problems.filter((p) => p.includes('not-a-real-secret'))).toEqual([]);
});
