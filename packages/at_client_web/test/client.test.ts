import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AtClient, AtError } from '../src/index.js';
import { MAX_BUFFERED_EVENTS } from '../src/subscription.js';
import { setBridgeLoader, type Bridge, type BridgeOptions, type BridgeSession } from '../src/loader.js';

type Listener = (payload: unknown) => void;

function fakeSession() {
  const listeners: Listener[] = [];
  const unsubscribe = vi.fn();
  const session = {
    put: vi.fn(async () => null),
    get: vi.fn(async (): Promise<string | Uint8Array | null> => null),
    delete: vi.fn(async () => null),
    keys: vi.fn(async (): Promise<string[]> => []),
    notify: vi.fn(async () => true),
    subscribe: vi.fn((_regex: string, listener: Listener) => {
      listeners.push(listener);
      return unsubscribe;
    }),
    otp: vi.fn(async () => '123456'),
    pendingEnrollments: vi.fn(async () => []),
    approve: vi.fn(async () => null),
    deny: vi.fn(async () => null),
    close: vi.fn(async () => null),
  };
  return { session, listeners, unsubscribe };
}

function fakeBridge(session: BridgeSession) {
  return {
    prfSupported: vi.fn(async () => true),
    create: vi.fn(async (_options: BridgeOptions) => session),
    onboard: vi.fn(async (_options: BridgeOptions, _cram: string, _device?: string) => session),
    enroll: vi.fn(
      async (_options: BridgeOptions, _app: string, _device: string, _otp: string) => session,
    ),
  };
}

function browser(overrides: { isSecureContext?: boolean; hostname?: string } = {}) {
  vi.stubGlobal('window', {
    isSecureContext: overrides.isSecureContext ?? true,
    location: { hostname: overrides.hostname ?? 'app.example.com' },
  });
}

const opts = { atSign: '@alice', namespace: 'tally' };

let fake: ReturnType<typeof fakeSession>;
let bridge: ReturnType<typeof fakeBridge>;
let loader: ReturnType<typeof vi.fn<() => Promise<Bridge>>>;

beforeEach(() => {
  fake = fakeSession();
  bridge = fakeBridge(fake.session as unknown as BridgeSession);
  loader = vi.fn(async () => bridge as unknown as Bridge);
  setBridgeLoader(loader);
  browser();
});

afterEach(() => {
  setBridgeLoader();
  vi.unstubAllGlobals();
});

async function rejection(promise: Promise<unknown>): Promise<AtError> {
  try {
    await promise;
  } catch (e) {
    expect(e).toBeInstanceOf(AtError);
    return e as AtError;
  }
  throw new Error('expected a rejection');
}

describe('static argument mapping', () => {
  it('create defaults app to namespace, rpId to the hostname and rpName to app', async () => {
    await AtClient.create(opts);
    expect(bridge.create).toHaveBeenCalledWith({
      atSign: '@alice',
      namespace: 'tally',
      app: 'tally',
      rpId: 'app.example.com',
      rpName: 'tally',
    });
  });

  it('create honours explicit app, rpId and rpName', async () => {
    await AtClient.create({ ...opts, app: 'tally-web', rpId: 'example.com', rpName: 'Tally' });
    expect(bridge.create).toHaveBeenCalledWith({
      atSign: '@alice',
      namespace: 'tally',
      app: 'tally-web',
      rpId: 'example.com',
      rpName: 'Tally',
    });
  });

  it('rpName defaults to an explicit app', async () => {
    await AtClient.create({ ...opts, app: 'tally-web' });
    expect(bridge.create.mock.calls[0]![0]).toMatchObject({ app: 'tally-web', rpName: 'tally-web' });
  });

  it('accepts the default root domain', async () => {
    await AtClient.create({ ...opts, rootDomain: 'root.atsign.org' });
    expect(bridge.create).toHaveBeenCalledTimes(1);
  });

  it('enroll passes the options, app name, device name and otp', async () => {
    await AtClient.enroll(opts, 'tally-phone', 'Pixel', '4F7A9C');
    expect(bridge.enroll).toHaveBeenCalledWith(
      { atSign: '@alice', namespace: 'tally', app: 'tally', rpId: 'app.example.com', rpName: 'tally' },
      'tally-phone',
      'Pixel',
      '4F7A9C',
    );
  });

  it('onboard passes the options, cram and device name', async () => {
    await AtClient.onboard(opts, { cram: 'abc', deviceName: 'laptop' });
    expect(bridge.onboard).toHaveBeenCalledWith(
      { atSign: '@alice', namespace: 'tally', app: 'tally', rpId: 'app.example.com', rpName: 'tally' },
      'abc',
      'laptop',
    );
  });

  it('onboard leaves the device name undefined when not given', async () => {
    await AtClient.onboard(opts, { cram: 'abc' });
    expect(bridge.onboard.mock.calls[0]![2]).toBeUndefined();
  });

  it('prfSupported reports what the bridge says', async () => {
    bridge.prfSupported.mockResolvedValueOnce(false);
    expect(await AtClient.prfSupported()).toBe(false);
  });
});

describe('pin gaps', () => {
  it('a missing namespace rejects bad_key before loading the bridge', async () => {
    const error = await rejection(AtClient.create({ atSign: '@alice' }));
    expect(error.code).toBe('bad_key');
    expect(loader).not.toHaveBeenCalled();
  });

  it('a foreign rootDomain rejects unsupported', async () => {
    const error = await rejection(AtClient.create({ ...opts, rootDomain: 'root.example.org' }));
    expect(error.code).toBe('unsupported');
    expect(bridge.create).not.toHaveBeenCalled();
  });

  it('no window rejects unsupported for every static', async () => {
    vi.unstubAllGlobals();
    for (const call of [
      () => AtClient.create(opts),
      () => AtClient.enroll(opts, 'a', 'd', 'otp'),
      () => AtClient.onboard(opts, { cram: 'c' }),
      () => AtClient.prfSupported(),
    ]) {
      expect((await rejection(call())).code).toBe('unsupported');
    }
    expect(loader).not.toHaveBeenCalled();
  });

  it('a non-secure context rejects unsupported', async () => {
    browser({ isSecureContext: false });
    expect((await rejection(AtClient.create(opts))).code).toBe('unsupported');
    expect(loader).not.toHaveBeenCalled();
  });
});

describe('error mapping', () => {
  it('maps a {code, message} rejection to an AtError', async () => {
    bridge.create.mockRejectedValueOnce({ code: 'pkam_refused', message: 'refused' });
    const error = await rejection(AtClient.create(opts));
    expect(error).toMatchObject({ name: 'AtError', message: 'refused', code: 'pkam_refused' });
    expect(error).toBeInstanceOf(Error);
  });

  it('maps every W8 code and bad_key through unchanged', async () => {
    for (const code of [
      'no_passkey_here', 'passkey_lost', 'prf_unavailable', 'pkam_refused', 'public_key_mismatch',
      'setup_lock_timeout', 'offline', 'onboarding_incomplete', 'enrollment_denied', 'closed',
      'unsupported', 'internal', 'bad_key',
    ]) {
      bridge.create.mockRejectedValueOnce({ code, message: code });
      expect((await rejection(AtClient.create(opts))).code).toBe(code);
    }
  });

  it('maps an unknown code or a thrown Error to internal', async () => {
    bridge.create.mockRejectedValueOnce({ code: 'brand_new', message: 'm' });
    expect((await rejection(AtClient.create(opts))).code).toBe('internal');
    bridge.create.mockRejectedValueOnce(new TypeError('boom'));
    expect(await rejection(AtClient.create(opts))).toMatchObject({ code: 'internal', message: 'boom' });
  });

  it('maps session call rejections too', async () => {
    const client = await AtClient.create(opts);
    fake.session.get.mockRejectedValueOnce({ code: 'offline', message: 'down' });
    expect((await rejection(client.get({ key: 'k' }))).code).toBe('offline');
    fake.session.keys.mockRejectedValueOnce({ code: 'closed', message: 'gone' });
    expect((await rejection(client.keys())).code).toBe('closed');
  });

  it('keeps AtError a subclass of Error with the given code', () => {
    const error = new AtError('m', 'offline');
    expect(error).toBeInstanceOf(Error);
    expect(error.code).toBe('offline');
    expect(error.name).toBe('AtError');
  });
});

describe('session calls', () => {
  it('put sends the key with the default namespace and resolves true', async () => {
    const client = await AtClient.create(opts);
    expect(await client.put({ key: 'note' }, 'hi')).toBe(true);
    expect(fake.session.put).toHaveBeenCalledWith({ key: 'note', namespace: 'tally' }, 'hi');
  });

  it('put passes bytes through', async () => {
    const client = await AtClient.create(opts);
    const bytes = new Uint8Array([1, 2]);
    await client.put({ key: 'blob', sharedWith: '@bob' }, bytes);
    expect(fake.session.put).toHaveBeenCalledWith(
      { key: 'blob', namespace: 'tally', sharedWith: '@bob' },
      bytes,
    );
  });

  it('get returns strings, bytes and null', async () => {
    const client = await AtClient.create(opts);
    fake.session.get.mockResolvedValueOnce('v').mockResolvedValueOnce(new Uint8Array([9])).mockResolvedValueOnce(null);
    expect(await client.get({ key: 'a' })).toBe('v');
    expect(await client.get({ key: 'b' })).toEqual(new Uint8Array([9]));
    expect(await client.get({ key: 'c' })).toBeNull();
  });

  it('delete resolves true', async () => {
    const client = await AtClient.create(opts);
    expect(await client.delete({ key: 'a', namespace: 'other' })).toBe(true);
    expect(fake.session.delete).toHaveBeenCalledWith({ key: 'a', namespace: 'other' });
  });

  it('keys maps the bridge strings to AtKey objects', async () => {
    const client = await AtClient.create(opts);
    fake.session.keys.mockResolvedValueOnce(['rpc.req.1.tally@alice', '@bob:note.tally@alice']);
    expect(await client.keys('rpc')).toEqual([
      { key: 'rpc.req.1', namespace: 'tally', sharedBy: '@alice' },
      { key: 'note', namespace: 'tally', sharedWith: '@bob', sharedBy: '@alice' },
    ]);
    expect(fake.session.keys).toHaveBeenCalledWith('rpc');
  });

  it('notify resolves what the bridge reports', async () => {
    const client = await AtClient.create(opts);
    expect(await client.notify({ key: 'rpc.req.1', sharedWith: '@alice' }, 'ping')).toBe(true);
    expect(fake.session.notify).toHaveBeenCalledWith(
      { key: 'rpc.req.1', namespace: 'tally', sharedWith: '@alice' },
      'ping',
    );
    fake.session.notify.mockResolvedValueOnce(false);
    expect(await client.notify({ key: 'x', sharedWith: '@alice' }, 'ping')).toBe(false);
  });
});

describe('pairing', () => {
  it('otp, pendingEnrollments, approve and deny reach the bridge', async () => {
    const client = await AtClient.create(opts);
    expect(await client.otp()).toBe('123456');
    const pending = [{ id: 'e1', appName: 'app', deviceName: 'phone', namespaces: { tally: 'rw' } }];
    fake.session.pendingEnrollments.mockResolvedValueOnce(pending as never);
    expect(await client.pendingEnrollments()).toEqual(pending);
    await client.approve('e1');
    await client.deny('e2');
    expect(fake.session.approve).toHaveBeenCalledWith('e1');
    expect(fake.session.deny).toHaveBeenCalledWith('e2');
  });

  it('maps an unsupported rejection', async () => {
    const client = await AtClient.create(opts);
    fake.session.otp.mockRejectedValueOnce({ code: 'unsupported', message: 'no __manage' });
    expect((await rejection(client.otp())).code).toBe('unsupported');
  });
});

describe('subscribe', () => {
  const payload = (over: Record<string, unknown> = {}) => ({
    id: 'n1',
    from: '@alice',
    key: '@alice:rpc.req.1.tally@alice',
    value: 'ping',
    epochMillis: 1,
    operation: 'update',
    ...over,
  });

  it('a failed subscribe surfaces its code as an AtError', async () => {
    const client = await AtClient.create(opts);
    fake.session.subscribe.mockReturnValueOnce({ code: 'closed', message: 'the session is closed' } as never);
    expect(() => client.subscribe()).toThrow(expect.objectContaining({ name: 'AtError', code: 'closed' }));
  });

  it('throws the AtError of a {code, message} the bridge throws', async () => {
    const client = await AtClient.create(opts);
    fake.session.subscribe.mockImplementationOnce(() => {
      throw { code: 'closed', message: 'the session is closed' };
    });
    expect(() => client.subscribe()).toThrow(expect.objectContaining({ code: 'closed' }));
  });

  it('registers on the bridge at call time, not at the first next()', async () => {
    const client = await AtClient.create(opts);
    client.subscribe('rpc');
    expect(fake.session.subscribe).toHaveBeenCalledTimes(1);
    expect(fake.session.subscribe.mock.calls[0]![0]).toBe('rpc');
  });

  it('defaults the regex to the namespace', async () => {
    const client = await AtClient.create({ atSign: '@alice', namespace: 'tally.v1' });
    client.subscribe();
    expect(fake.session.subscribe.mock.calls[0]![0]).toBe('\\.tally\\.v1@');
  });

  it('buffers events and maps them to AtEvents', async () => {
    const client = await AtClient.create(opts);
    const events = client.subscribe()[Symbol.asyncIterator]();
    fake.listeners[0]!(payload());
    fake.listeners[0]!(payload({ operation: 'delete', value: null, key: 'note.tally@bob' }));
    expect(await events.next()).toEqual({
      done: false,
      value: {
        operation: 'update',
        from: '@alice',
        key: { key: 'rpc.req.1', namespace: 'tally', sharedWith: '@alice', sharedBy: '@alice' },
        value: 'ping',
      },
    });
    const second = await events.next();
    expect(second.value).toEqual({
      operation: 'delete',
      from: '@alice',
      key: { key: 'note', namespace: 'tally', sharedBy: '@bob' },
    });
    expect('value' in second.value).toBe(false);
  });

  it('carries the sending atSign from the bridge', async () => {
    const client = await AtClient.create(opts);
    const events = client.subscribe()[Symbol.asyncIterator]();
    fake.listeners[0]!(payload({ from: '@bob', key: 'note.tally@bob' }));
    expect((await events.next()).value.from).toBe('@bob');
  });

  it('a subscription that buffers past the cap unsubscribes and rejects with overflow', async () => {
    const client = await AtClient.create(opts);
    const events = client.subscribe()[Symbol.asyncIterator]();
    for (let i = 0; i <= MAX_BUFFERED_EVENTS; i++) fake.listeners[0]!(payload());
    expect(fake.unsubscribe).toHaveBeenCalledTimes(1);
    await expect(events.next()).rejects.toMatchObject({ code: 'overflow' });
    expect(await events.next()).toEqual({ done: true, value: undefined });
  });

  it('break unsubscribes once', async () => {
    const client = await AtClient.create(opts);
    const events = client.subscribe();
    fake.listeners[0]!(payload());
    for await (const event of events) {
      expect(event.operation).toBe('update');
      break;
    }
    expect(fake.unsubscribe).toHaveBeenCalledTimes(1);
    fake.listeners[0]!(payload());
    expect(await events[Symbol.asyncIterator]().next()).toEqual({ done: true, value: undefined });
  });

  it('close ends every open iterator, unsubscribes each and closes the bridge session', async () => {
    const client = await AtClient.create(opts);
    const a = client.subscribe()[Symbol.asyncIterator]();
    const b = client.subscribe('x')[Symbol.asyncIterator]();
    const waiting = a.next();
    await client.close();
    expect(await waiting).toEqual({ done: true, value: undefined });
    expect(await b.next()).toEqual({ done: true, value: undefined });
    expect(fake.unsubscribe).toHaveBeenCalledTimes(2);
    expect(fake.session.close).toHaveBeenCalledTimes(1);
  });

  it('close twice closes the bridge session once', async () => {
    const client = await AtClient.create(opts);
    await client.close();
    await client.close();
    expect(fake.session.close).toHaveBeenCalledTimes(1);
  });

  it('subscribe after close throws closed without touching the bridge', async () => {
    const client = await AtClient.create(opts);
    await client.close();
    let thrown: unknown;
    try {
      client.subscribe();
    } catch (e) {
      thrown = e;
    }
    expect(thrown).toBeInstanceOf(AtError);
    expect((thrown as AtError).code).toBe('closed');
    expect(fake.session.subscribe).not.toHaveBeenCalled();
  });

  it('maps a synchronous throw from the bridge subscribe', async () => {
    const client = await AtClient.create(opts);
    fake.session.subscribe.mockImplementationOnce(() => {
      throw { code: 'closed', message: 'gone' };
    });
    expect(() => client.subscribe()).toThrowError(expect.objectContaining({ code: 'closed' }));
  });
});
