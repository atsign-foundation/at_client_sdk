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

export interface AtClientOptions {
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

export interface AtKey {
  key: string;
  sharedBy?: string;
  sharedWith?: string;
  namespace?: string;
}

export interface AtEvent {
  operation: 'update' | 'delete';
  key: AtKey;
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
  id: string;
  appName: string;
  deviceName: string;
  /** Each requested namespace with its access, `r` or `rw`. */
  namespaces: Record<string, string>;
}

export interface AtClientLike {
  /** Gets a string or Uint8Array value */
  get(key: AtKey): Promise<string | Uint8Array | null>;

  /** Puts a string or Uint8Array value */
  put(key: AtKey, value: string | Uint8Array): Promise<boolean>;

  /** Deletes a key */
  delete(key: AtKey): Promise<boolean>;

  /** Scans for keys matching the regex/filter */
  keys(filter?: string): Promise<AtKey[]>;

  /** Sends a notification */
  notify(key: AtKey, value: string): Promise<boolean>;

  /**
   * Real-time event subscription via AsyncIterable.
   * Enables clean wrapping in React hooks (e.g. `useAtNotifications`).
   */
  subscribe(regex?: string): AsyncIterable<AtEvent>;

  /** Closes the connection and releases resources */
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

  get(key: AtKey): Promise<string | Uint8Array | null> {
    return bridged(async () => (await this.session.get(toBridgeKey(key, this.namespace))) ?? null);
  }

  async put(key: AtKey, value: string | Uint8Array): Promise<boolean> {
    await bridged(() => this.session.put(toBridgeKey(key, this.namespace), value));
    return true;
  }

  async delete(key: AtKey): Promise<boolean> {
    await bridged(() => this.session.delete(toBridgeKey(key, this.namespace)));
    return true;
  }

  async keys(filter?: string): Promise<AtKey[]> {
    const keys = await bridged(() => this.session.keys(filter));
    return keys.map((text) => parseKey(text, this.namespace));
  }

  notify(key: AtKey, value: string): Promise<boolean> {
    return bridged(() => this.session.notify(toBridgeKey(key, this.namespace), value));
  }

  subscribe(regex?: string): AsyncIterable<AtEvent> {
    if (this.closed) throw new AtError('the client is closed', 'closed');
    let unsubscribe: (() => void) | undefined;
    const queue: EventQueue<AtEvent> = new EventQueue(() => {
      this.streams.delete(queue);
      unsubscribe?.();
    });
    try {
      unsubscribe = this.session.subscribe(
        regex ?? `\\.${this.namespace.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}@`,
        (notification) => queue.push(this.event(notification)),
      );
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

  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    for (const stream of [...this.streams]) stream.end();
    await bridged(() => this.session.close());
  }

  private event(notification: BridgeNotification): AtEvent {
    const event: AtEvent = {
      operation: notification.operation,
      key: parseKey(notification.key, this.namespace),
    };
    if (notification.value !== null && notification.value !== undefined) {
      event.value = notification.value;
    }
    return event;
  }
}
