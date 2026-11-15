import { AtError, toAtError, type AtErrorCode } from './error.js';
import { parseKey, toBridgeKey } from './key.js';
import {
  loadBridge,
  type Bridge,
  type BridgeEnrollment,
  type BridgeNotification,
  type BridgeOptions,
  type BridgeSession,
} from './loader.js';
import { EventQueue } from './subscription.js';

export { AtError };
export type { AtErrorCode };

/** What every entry point (`create`, `onboard`, `enroll`) takes to name the atSign and the passkey's scope. */
export interface AtClientOptions {
  /** The atSign to open, with its leading `@`. */
  atSign: string;
  /** Required: it scopes every key this client reads and writes. */
  namespace?: string;
  /** Only `root.atsign.org` is supported. */
  rootDomain?: string;
  /** The enrollment's app name; defaults to `namespace`. */
  app?: string;
  /** The passkey's relying-party id; defaults to `location.hostname`. */
  rpId?: string;
  /** The passkey's relying-party display name; defaults to `app`. */
  rpName?: string;
}

/** A key's parts; the client composes and parses the wire form (`@with:key.namespace@by`). */
export interface AtKey {
  /** The key's name, without namespace or atSigns. */
  key: string;
  /** The atSign that owns the key; left out for the client's own atSign. */
  sharedBy?: string;
  /** The atSign the key is shared with; left out for a key kept to oneself. */
  sharedWith?: string;
  /** Defaults to the client's `namespace`. */
  namespace?: string;
  /** A public key (`public:`); set on the keys `keys()` and `subscribe` return. */
  public?: boolean;
  /** A key cached from another atSign (`cached:`); set on the keys `keys()` and `subscribe` return. */
  cached?: boolean;
  /** The key has no namespace; set on the keys `keys()` and `subscribe` return, so `get` reads the same record. */
  noNamespace?: boolean;
}

/** One notification delivered to a `subscribe` iterator. */
export interface AtEvent {
  /** What happened to the key. */
  operation: 'update' | 'delete';
  /** The atSign that sent the notification, in `@name` form; it is the key's owner. */
  from: string;
  /** The key that changed. */
  key: AtKey;
  /** The new value; absent when the notification carries none. */
  value?: string | Uint8Array;
}

/** What `AtClient.onboard` needs to bring a fresh atSign up. */
export interface OnboardOptions {
  /** The atSign's CRAM secret. */
  cram: string;
  /** Names this browser's enrollment. */
  deviceName?: string;
}

/** An enrollment request awaiting `approve` or `deny`. */
export interface PendingEnrollment {
  /** The id to pass to `approve` or `deny`. */
  id: string;
  /** The app the requesting device enrolls for. */
  appName: string;
  /** The name the requesting device gave itself. */
  deviceName: string;
  /** Each requested namespace with its access, `r` or `rw`. */
  namespaces: Record<string, string>;
}

/** The data-plane surface of an open client: key/value access, notifications and subscriptions. */
export interface AtClientLike {
  /** Gets a string or Uint8Array value; `null` when the key has none. */
  get(key: AtKey): Promise<string | Uint8Array | null>;

  /** Puts a string or Uint8Array value; resolves `true` once it is stored. */
  put(key: AtKey, value: string | Uint8Array): Promise<boolean>;

  /** Deletes a key; resolves `true` once it is gone. */
  delete(key: AtKey): Promise<boolean>;

  /** Lists the keys whose wire form matches the `filter` regex; every key when it is omitted. */
  keys(filter?: string): Promise<AtKey[]>;

  /** Sends `value` to the key's `sharedWith` atSign as a notification. */
  notify(key: AtKey, value: string): Promise<boolean>;

  /**
   * Real-time event subscription via AsyncIterable.
   * Registers when called, buffers up to 4096 events and unsubscribes when
   * the loop ends (`break`/`return()`) or the client closes. A subscription
   * that buffers more ends: on overflow the subscription ends, buffered events
   * are discarded, and `next()` rejects with `AtError('overflow')`; subscribe
   * again. Without
   * `regex` it matches the client's namespace. Throws `AtError('closed')`
   * after `close()`.
   */
  subscribe(regex?: string): AsyncIterable<AtEvent>;

  /** Closes the connection, ends every open `subscribe` iterator, and releases resources. */
  close(): Promise<void>;
}

const supportedRootDomain = 'root.atsign.org';

/** Maps a rejected or thrown bridge failure to an `AtError`. */
async function bridged<T>(call: () => Promise<T>): Promise<T> {
  try {
    return await call();
  } catch (error) {
    throw toAtError(error);
  }
}

type Page = { isSecureContext?: boolean; location: { hostname: string } };

function page(): Page | undefined {
  return (globalThis as { window?: Page }).window;
}

/** Refuses anything but a browser page. */
function requireBrowser(): void {
  if (page() === undefined) throw new AtError('AtClient runs in browsers only', 'unsupported');
}

/** Refuses anything but a secure browser page. */
function requireSecureBrowser(): void {
  requireBrowser();
  if (page()?.isSecureContext !== true) {
    throw new AtError('AtClient needs a secure context (HTTPS)', 'unsupported');
  }
}

/** The bridge's options for [opts], with every default applied. */
function bridgeOptions(opts: AtClientOptions): BridgeOptions {
  if (opts.rootDomain !== undefined && opts.rootDomain !== supportedRootDomain) {
    throw new AtError(`rootDomain ${opts.rootDomain} is not supported`, 'unsupported');
  }
  if (!opts.namespace) throw new AtError('AtClientOptions.namespace is required', 'bad_key');
  const app = opts.app ?? opts.namespace;
  return {
    atSign: opts.atSign,
    namespace: opts.namespace,
    app,
    rpId: opts.rpId ?? page()?.location.hostname ?? '',
    rpName: opts.rpName ?? app,
  };
}

/**
 * An open session on one atSign. Obtain one from `create`, `onboard` or
 * `enroll`; every failure rejects with an `AtError`.
 */
export class AtClient implements AtClientLike {
  private readonly streams = new Set<EventQueue<AtEvent>>();
  private closed = false;

  private constructor(
    private readonly session: BridgeSession,
    private readonly namespace: string,
  ) {}

  /** Opens a session through [connect] on the loaded bridge, checking the page and [opts] first. */
  private static async open(
    opts: AtClientOptions,
    connect: (bridge: Bridge, options: BridgeOptions) => Promise<BridgeSession>,
  ): Promise<AtClient> {
    requireSecureBrowser();
    const options = bridgeOptions(opts);
    const session = await bridged(async () => connect(await loadBridge(), options));
    return new AtClient(session, options.namespace);
  }

  /** Opens the atSign's session with its passkey. */
  static create(opts: AtClientOptions): Promise<AtClient> {
    return AtClient.open(opts, (bridge, options) => bridge.create(options));
  }

  /** Enrolls this browser with a one-time code another device issued; resolves once that device approves. */
  static enroll(
    opts: AtClientOptions,
    appName: string,
    deviceName: string,
    otp: string,
  ): Promise<AtClient> {
    return AtClient.open(opts, (bridge, options) => bridge.enroll(options, appName, deviceName, otp));
  }

  /** Onboards a fresh atSign with its CRAM secret and opens its session. */
  static onboard(opts: AtClientOptions, onboard: OnboardOptions): Promise<AtClient> {
    return AtClient.open(opts, (bridge, options) =>
      bridge.onboard(options, onboard.cram, onboard.deviceName),
    );
  }

  /** Whether this browser can evaluate passkey PRF, which passkey custody needs. */
  static async prfSupported(): Promise<boolean> {
    requireBrowser();
    return bridged(async () => (await loadBridge()).prfSupported());
  }

  /** Gets a string or Uint8Array value; `null` when the key has none. */
  get(key: AtKey): Promise<string | Uint8Array | null> {
    return bridged(async () => (await this.session.get(toBridgeKey(key, this.namespace))) ?? null);
  }

  /** Puts a string or Uint8Array value; resolves `true` once it is stored. */
  async put(key: AtKey, value: string | Uint8Array): Promise<boolean> {
    await bridged(() => this.session.put(toBridgeKey(key, this.namespace), value));
    return true;
  }

  /** Deletes a key; resolves `true` once it is gone. */
  async delete(key: AtKey): Promise<boolean> {
    await bridged(() => this.session.delete(toBridgeKey(key, this.namespace)));
    return true;
  }

  /** Lists the keys whose wire form matches the `filter` regex; every key when it is omitted. */
  async keys(filter?: string): Promise<AtKey[]> {
    const keys = await bridged(() => this.session.keys(filter));
    return keys.map((text) => parseKey(text, this.namespace));
  }

  /** Sends `value` to the key's `sharedWith` atSign as a notification. */
  notify(key: AtKey, value: string): Promise<boolean> {
    return bridged(() => this.session.notify(toBridgeKey(key, this.namespace), value));
  }

  /** Subscribes to notifications; see `AtClientLike.subscribe`. */
  subscribe(regex?: string): AsyncIterable<AtEvent> {
    if (this.closed) throw new AtError('the client is closed', 'closed');
    let unsubscribe: (() => void) | undefined;
    const queue: EventQueue<AtEvent> = new EventQueue(() => {
      this.streams.delete(queue);
      unsubscribe?.();
    });
    try {
      const subscribed = this.session.subscribe(
        regex ?? `\\.${this.namespace.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}@`,
        (notification) => queue.push(this.event(notification)),
      );
      if (typeof subscribed !== 'function') throw subscribed;
      unsubscribe = subscribed;
    } catch (error) {
      throw toAtError(error);
    }
    this.streams.add(queue);
    return queue;
  }

  /** A one-time code a new device quotes to ask for enrollment. Needs `__manage`. */
  otp(): Promise<string> {
    return bridged(() => this.session.otp());
  }

  /** The enrollment requests awaiting a decision. Needs `__manage`. */
  pendingEnrollments(): Promise<PendingEnrollment[]> {
    return bridged(async () =>
      (await this.session.pendingEnrollments()).map((e: BridgeEnrollment) => ({ ...e })),
    );
  }

  /** Approves the pending request [id] for what it asked for. Needs `__manage`. */
  async approve(id: string): Promise<void> {
    await bridged(() => this.session.approve(id));
  }

  /** Denies the pending request [id]. Needs `__manage`. */
  async deny(id: string): Promise<void> {
    await bridged(() => this.session.deny(id));
  }

  /** Closes the session and ends every open `subscribe` iterator; closing twice is a no-op. */
  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    for (const stream of [...this.streams]) stream.end();
    await bridged(() => this.session.close());
  }

  private event(notification: BridgeNotification): AtEvent {
    const event: AtEvent = {
      operation: notification.operation,
      from: notification.from,
      key: parseKey(notification.key, this.namespace),
    };
    if (notification.value !== null && notification.value !== undefined) {
      event.value = notification.value;
    }
    return event;
  }
}
