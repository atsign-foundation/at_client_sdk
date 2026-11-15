import { AtError } from './error.js';
import type { BridgeKey } from './key.js';

/** A bridge notification as the Dart side delivers it. */
export interface BridgeNotification {
  id: string;
  from: string;
  key: string;
  value: string | null;
  epochMillis: number;
  operation: 'update' | 'delete';
}

export interface BridgeEnrollment {
  id: string;
  appName: string;
  deviceName: string;
  namespaces: Record<string, string>;
}

/** The options the bridge takes, every default already applied. */
export interface BridgeOptions {
  atSign: string;
  namespace: string;
  app: string;
  rpId: string;
  rpName: string;
}

/** One open client on the Dart side. */
export interface BridgeSession {
  put(key: BridgeKey, value: string | Uint8Array): Promise<unknown>;
  get(key: BridgeKey): Promise<string | Uint8Array | null | undefined>;
  delete(key: BridgeKey): Promise<unknown>;
  keys(regex?: string): Promise<string[]>;
  notify(key: BridgeKey, value: string): Promise<boolean>;
  /**
   * The function that unsubscribes. A subscription the bridge cannot make is
   * answered with its `{code, message}` failure instead of a throw, which
   * would reach this side without a code.
   */
  subscribe(
    regex: string,
    listener: (notification: BridgeNotification) => void,
  ): (() => void) | { code: string; message: string };
  otp(): Promise<string>;
  pendingEnrollments(): Promise<BridgeEnrollment[]>;
  approve(id: string): Promise<unknown>;
  deny(id: string): Promise<unknown>;
  close(): Promise<unknown>;
}

/** The statics the Dart bundle installs at `globalThis.__atsignAtClientWeb`. */
export interface Bridge {
  prfSupported(): Promise<boolean>;
  create(options: BridgeOptions): Promise<BridgeSession>;
  onboard(options: BridgeOptions, cram: string, deviceName?: string): Promise<BridgeSession>;
  enroll(
    options: BridgeOptions,
    appName: string,
    deviceName: string,
    otp: string,
  ): Promise<BridgeSession>;
}

export type BridgeLoader = () => Promise<Bridge>;

const bridgeGlobal = '__atsignAtClientWeb';
const installTimeoutMs = 5_000;
const installPollMs = 10;

function installed(): Bridge | undefined {
  return (globalThis as Record<string, unknown>)[bridgeGlobal] as Bridge | undefined;
}

/**
 * Injects the dart2js bundle that sits beside this module once and resolves
 * with the bridge it installs; a bridge that is already installed is reused.
 */
function injectBundle(): Promise<Bridge> {
  const existing = installed();
  if (existing) return Promise.resolve(existing);
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = new URL('./dart/at_client.js', import.meta.url).href;
    script.async = true;
    const fail = (message: string) => {
      script.remove();
      reject(new AtError(message, 'internal'));
    };
    script.onerror = () => fail(`could not load ${script.src}`);
    script.onload = () => {
      const deadline = Date.now() + installTimeoutMs;
      const poll = () => {
        const bridge = installed();
        if (bridge) resolve(bridge);
        else if (Date.now() >= deadline) fail(`${script.src} did not install the bridge`);
        else setTimeout(poll, installPollMs);
      };
      poll();
    };
    document.head.appendChild(script);
  });
}

let loader: BridgeLoader = injectBundle;
let loading: Promise<Bridge> | undefined;

/** The bridge, loaded on the first call and shared by every later one. */
export function loadBridge(): Promise<Bridge> {
  if (loading) return loading;
  const attempt: Promise<Bridge> = loader().catch((error: unknown) => {
    // A loader set meanwhile owns `loading` now; only forget our own failure.
    if (loading === attempt) loading = undefined;
    throw error;
  });
  loading = attempt;
  return attempt;
}

/** Replaces how the bridge loads, or restores the default; forgets any loaded bridge. */
export function setBridgeLoader(replacement?: BridgeLoader): void {
  loader = replacement ?? injectBundle;
  loading = undefined;
}
