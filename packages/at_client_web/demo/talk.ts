import { AtClient } from '@atsign/at_client_web';
import { canonicalAtSign } from './atsign.js';
import { appendLine, byId, describeError } from './common.js';

const messageKey = 'attalk';

const me = byId<HTMLInputElement>('me');
const peer = byId<HTMLInputElement>('peer');
const namespace = byId<HTMLInputElement>('namespace');
const line = byId<HTMLInputElement>('line');
const log = byId('log');
const status = byId('status');

let client: AtClient | undefined;
let stream: AsyncIterator<unknown> | undefined;

function setStatus(state: 'disconnected' | 'connecting' | 'connected', label: string): void {
  status.dataset.state = state;
  status.textContent = label;
}

function setOpen(open: boolean): void {
  for (const element of Array.from(byId<HTMLFormElement>('send').elements)) {
    (element as HTMLInputElement | HTMLButtonElement).disabled = !open;
  }
  byId<HTMLButtonElement>('open').disabled = open;
  byId<HTMLButtonElement>('close').disabled = !open;
  byId<HTMLFieldSetElement>('fields').disabled = open;
  setStatus(open ? 'connected' : 'disconnected', open ? 'Connected' : 'Disconnected');
  if (open) line.focus();
}

function note(text: string, error = false): void {
  appendLine(log, text, error ? 'note err' : 'note');
}

function bubble(sender: string, text: string, own: boolean): void {
  const row = document.createElement('div');
  row.className = `msg ${own ? 'me' : 'peer'}`;
  const who = document.createElement('div');
  who.className = 'who';
  who.textContent = sender;
  const body = document.createElement('div');
  body.className = 'bubble';
  body.textContent = text;
  const time = document.createElement('time');
  time.textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  row.append(who, body, time);
  log.append(row);
  log.scrollTop = log.scrollHeight;
}

/** Renders every message notification the client delivers until the stream ends. */
async function receive(opened: AtClient, own: string): Promise<void> {
  const events = opened.subscribe()[Symbol.asyncIterator]();
  stream = events;
  try {
    for (let next = await events.next(); !next.done; next = await events.next()) {
      const { operation, key, value, from } = next.value;
      if (operation !== 'update' || key.key !== messageKey || typeof value !== 'string') continue;
      if (canonicalAtSign(from) !== canonicalAtSign(own)) bubble(from, value, false);
    }
  } catch (error) {
    note(`receive: ${describeError(error)}`, true);
  }
}

async function stop(): Promise<void> {
  const closing = client;
  client = undefined;
  void stream?.return?.();
  stream = undefined;
  await closing?.close();
}

byId('open').addEventListener('click', () => {
  byId<HTMLButtonElement>('open').disabled = true;
  setStatus('connecting', 'Connecting');
  const own = me.value.trim();
  AtClient.create({ atSign: own, namespace: namespace.value.trim() }).then(
    (opened) => {
      client = opened;
      setOpen(true);
      note(`opened ${own}, talking to ${peer.value.trim()}`);
      void receive(opened, own);
    },
    (error: unknown) => {
      setOpen(false);
      note(`open: ${describeError(error)}`, true);
    },
  );
});

byId('close').addEventListener('click', () => {
  stop().then(
    () => {
      setOpen(false);
      note('closed');
    },
    (error: unknown) => note(`close: ${describeError(error)}`, true),
  );
});

byId('send').addEventListener('submit', (event) => {
  event.preventDefault();
  const text = line.value;
  const to = peer.value.trim();
  if (!text || client === undefined) return;
  line.value = '';
  client.notify({ key: messageKey, sharedWith: to, sharedBy: me.value.trim() }, text).then(
    () => bubble(me.value.trim(), text, true),
    (error: unknown) => note(`send: ${describeError(error)}`, true),
  );
});

window.addEventListener('pagehide', () => {
  void stop();
});
