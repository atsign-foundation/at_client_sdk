import { expect, test, type CDPSession, type Page } from '@playwright/test';

// The live lane needs a CTAP2 virtual authenticator and an atSign on the
// default root whose CRAM secret is supplied; without both it is skipped.
const atSign = process.env.AT_CLIENT_WEB_LIVE_ATSIGN;
const cram = process.env.AT_CLIENT_WEB_LIVE_CRAM;
const port = Number(process.env.E2E_PORT ?? 4173);
const namespace = 'e2e';

test.skip(!atSign || !cram, 'set AT_CLIENT_WEB_LIVE_ATSIGN and AT_CLIENT_WEB_LIVE_CRAM to run the live lane');

/** Installs a platform authenticator that holds resident keys and evaluates PRF. */
async function addAuthenticator(page: Page): Promise<CDPSession> {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('WebAuthn.enable');
  await cdp.send('WebAuthn.addVirtualAuthenticator', {
    options: {
      protocol: 'ctap2',
      transport: 'internal',
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
      automaticPresenceSimulation: true,
      hasPrf: true,
    },
  });
  return cdp;
}

async function open(page: Page): Promise<void> {
  await page.goto(`http://localhost:${port}/`);
  await page.waitForFunction(() => (window as any).e2eReady === true);
}

test('onboard, login, put/get, notify and subscribe against a live atServer', async ({ page }) => {
  test.setTimeout(180_000);
  await addAuthenticator(page);
  await open(page);

  expect(await page.evaluate(() => (window as any).AtClient.prfSupported())).toBe(true);

  const opts = { atSign, namespace, rpId: 'localhost' };
  await page.evaluate(async ([o, secret]) => {
    const client = await (window as any).AtClient.onboard(o, { cram: secret, deviceName: 'e2e' });
    await client.close();
  }, [opts, cram] as const);

  // A fresh page load proves login reads the passkey and stored enrollment, not live state.
  await open(page);
  const result = await page.evaluate(async (o) => {
    const client = await (window as any).AtClient.create(o);
    const id = Date.now().toString(36);
    const events: { operation: string; key: string; value?: unknown }[] = [];
    const stream = client.subscribe();
    const drain = (async () => {
      for await (const event of stream) {
        events.push({ operation: event.operation, key: event.key.key, value: event.value });
      }
    })();
    const waitFor = async (match: (e: (typeof events)[number]) => boolean, ms: number) => {
      const deadline = Date.now() + ms;
      while (Date.now() < deadline) {
        const hit = events.find(match);
        if (hit) return hit;
        await new Promise((r) => setTimeout(r, 100));
      }
      return null;
    };

    const key = { key: `put-${id}` };
    await client.put(key, 'hello');
    const got = await client.get(key);
    const listed = (await client.keys()).some((k: { key: string }) => k.key === key.key);

    const echoKey = { key: `echo-${id}`, sharedWith: o.atSign };
    await client.notify(echoKey, 'ping');
    const echo = await waitFor((e) => e.key === echoKey.key, 15_000);

    await client.delete(key);
    const deleted = await waitFor((e) => e.key === key.key && e.operation === 'delete', 15_000);

    await client.close();
    await drain;
    return { got, listed, echo, deleted, events };
  }, opts);

  expect(result.got).toBe('hello');
  expect(result.listed).toBe(true);
  test.info().annotations.push({
    type: 'self-notify echo',
    description: result.echo ? `arrived: ${JSON.stringify(result.echo)}` : 'did not arrive within 15s',
  });
  test.info().annotations.push({
    type: 'observed events',
    description: JSON.stringify(result.events),
  });
  expect(result.deleted, 'a delete notification with operation "delete"').not.toBeNull();
  expect(result.deleted?.operation).toBe('delete');
});
