import { AtClient, type AtClientOptions } from '@atsign/at_client_web';
import { byId, describeError } from './common.js';

const atSign = byId<HTMLInputElement>('atSign');
const namespace = byId<HTMLInputElement>('namespace');
const cram = byId<HTMLInputElement>('cram');
const keyName = byId<HTMLInputElement>('keyName');
const keyValue = byId<HTMLInputElement>('keyValue');
const result = byId('result');
const status = byId('status');
const prf = byId('prf');
const sessionButtons = ['logout', 'put', 'get', 'keys'].map((id) => byId<HTMLButtonElement>(id));
const entryButtons = ['onboard', 'login'].map((id) => byId<HTMLButtonElement>(id));

let client: AtClient | undefined;

function show(state: 'ok' | 'error' | 'idle', text: string): void {
  result.dataset.state = state;
  result.textContent = text;
}

function setOpen(open: boolean): void {
  for (const button of sessionButtons) button.disabled = !open;
  for (const button of entryButtons) button.disabled = open;
  byId<HTMLFieldSetElement>('account').disabled = open;
  status.dataset.state = open ? 'connected' : 'disconnected';
  status.textContent = open ? 'Connected' : 'Disconnected';
}

/** Runs [action], showing what it returns or the `AtError` code it fails with. */
async function run(action: () => Promise<string>): Promise<void> {
  try {
    show('ok', await action());
  } catch (error) {
    show('error', describeError(error));
  }
}

function options(): AtClientOptions {
  return { atSign: atSign.value.trim(), namespace: namespace.value.trim() };
}

async function open(start: () => Promise<AtClient>): Promise<string> {
  status.dataset.state = 'connecting';
  status.textContent = 'Connecting';
  try {
    client = await start();
  } catch (error) {
    setOpen(false);
    throw error;
  }
  setOpen(true);
  return `opened ${atSign.value.trim()}`;
}

byId('onboard').addEventListener('click', () => {
  const secret = cram.value;
  cram.value = '';
  void run(() => open(() => AtClient.onboard(options(), { cram: secret, deviceName: 'demo' })));
});

byId('login').addEventListener('click', () => {
  void run(() => open(() => AtClient.create(options())));
});

byId('logout').addEventListener('click', () => {
  void run(async () => {
    await client?.close();
    client = undefined;
    setOpen(false);
    return 'closed';
  });
});

byId('put').addEventListener('click', () => {
  void run(async () => {
    await client?.put({ key: keyName.value }, keyValue.value);
    return `put ${keyName.value}`;
  });
});

byId('get').addEventListener('click', () => {
  void run(async () => {
    const value = await client?.get({ key: keyName.value });
    return value === null || value === undefined ? `${keyName.value}: no value` : `${keyName.value} = ${String(value)}`;
  });
});

byId('keys').addEventListener('click', () => {
  void run(async () => {
    const keys = (await client?.keys()) ?? [];
    return keys.length === 0 ? 'no keys' : keys.map((k) => `${k.key}${k.namespace ? `.${k.namespace}` : ''}${k.sharedBy ?? ''}`).join('\n');
  });
});

window.addEventListener('pagehide', () => {
  void client?.close();
});

AtClient.prfSupported().then(
  (supported) => {
    prf.dataset.state = supported ? 'supported' : 'unsupported';
    prf.textContent = supported ? 'PRF supported' : 'PRF unsupported';
  },
  (error: unknown) => {
    prf.dataset.state = 'unsupported';
    prf.textContent = 'PRF unsupported';
    show('error', describeError(error));
  },
);
