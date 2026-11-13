import type { AtKey } from './index.js';

/** A key as the bridge takes it: absent fields are left out. */
export interface BridgeKey {
  key: string;
  namespace: string;
  sharedWith?: string;
  sharedBy?: string;
}

/** The bridge's form of [key], under [namespace] unless it names its own. */
export function toBridgeKey(key: AtKey, namespace: string): BridgeKey {
  const bridgeKey: BridgeKey = { key: key.key, namespace: key.namespace ?? namespace };
  if (key.sharedWith !== undefined) bridgeKey.sharedWith = key.sharedWith;
  if (key.sharedBy !== undefined) bridgeKey.sharedBy = key.sharedBy;
  return bridgeKey;
}

/**
 * The `AtKey` a key string names: `[cached:][public:|@with:]key.namespace[@by]`.
 * The namespace is [namespace] when the key ends in it, else the last
 * dot-separated segment; a key with no dot has none. The `public:` and
 * `cached:` prefixes are dropped.
 */
export function parseKey(text: string, namespace?: string): AtKey {
  let rest = text.startsWith('cached:') ? text.slice('cached:'.length) : text;
  const key: Partial<AtKey> = {};

  if (rest.startsWith('public:')) {
    rest = rest.slice('public:'.length);
  } else if (rest.startsWith('@')) {
    const colon = rest.indexOf(':');
    if (colon > 0) {
      key.sharedWith = rest.slice(0, colon);
      rest = rest.slice(colon + 1);
    }
  }

  const at = rest.lastIndexOf('@');
  if (at >= 0) {
    key.sharedBy = rest.slice(at);
    rest = rest.slice(0, at);
  }

  const suffix = namespace === undefined ? undefined : `.${namespace}`;
  const dot = rest.lastIndexOf('.');
  if (suffix !== undefined && rest.endsWith(suffix) && rest.length > suffix.length) {
    key.key = rest.slice(0, -suffix.length);
    key.namespace = namespace;
  } else if (dot > 0) {
    key.key = rest.slice(0, dot);
    key.namespace = rest.slice(dot + 1);
  } else {
    key.key = rest;
  }

  const ordered: AtKey = { key: key.key! };
  if (key.namespace !== undefined) ordered.namespace = key.namespace;
  if (key.sharedWith !== undefined) ordered.sharedWith = key.sharedWith;
  if (key.sharedBy !== undefined) ordered.sharedBy = key.sharedBy;
  return ordered;
}

/** The key string of [key] under [namespace] unless it names its own. */
export function formatKey(key: AtKey, namespace?: string): string {
  const ns = key.namespace ?? namespace;
  const name = ns === undefined ? key.key : `${key.key}.${ns}`;
  return `${key.sharedWith === undefined ? '' : `${key.sharedWith}:`}${name}${key.sharedBy ?? ''}`;
}
