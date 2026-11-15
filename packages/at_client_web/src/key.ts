import type { AtKey } from './index.js';

/** A key as the bridge takes it: absent fields are left out. */
export interface BridgeKey {
  key: string;
  /** Absent for a key with no namespace (then [noNamespace] is true). */
  namespace?: string;
  sharedWith?: string;
  sharedBy?: string;
  public?: true;
  cached?: true;
  noNamespace?: true;
}

/** The bridge's form of [key], under [namespace] unless it names its own. */
export function toBridgeKey(key: AtKey, namespace: string): BridgeKey {
  const bridgeKey: BridgeKey = { key: key.key };
  if (key.noNamespace === true) bridgeKey.noNamespace = true;
  else bridgeKey.namespace = key.namespace ?? namespace;
  if (key.sharedWith !== undefined) bridgeKey.sharedWith = key.sharedWith;
  if (key.sharedBy !== undefined) bridgeKey.sharedBy = key.sharedBy;
  if (key.public === true) bridgeKey.public = true;
  if (key.cached === true) bridgeKey.cached = true;
  return bridgeKey;
}

/**
 * The `AtKey` a key string names: `[cached:][public:|@with:]key.namespace[@by]`.
 * The namespace is [namespace] when the key ends in it, else the last
 * dot-separated segment; a key with no dot has none and is marked
 * `noNamespace`. The `public:` and `cached:` prefixes are kept as flags, so
 * the result names the same record when passed back to the client.
 */
export function parseKey(text: string, namespace?: string): AtKey {
  let rest = text;
  const key: Partial<AtKey> = {};

  if (rest.startsWith('cached:')) {
    key.cached = true;
    rest = rest.slice('cached:'.length);
  }

  if (rest.startsWith('public:')) {
    key.public = true;
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
    key.noNamespace = true;
  }

  const ordered: AtKey = { key: key.key! };
  if (key.namespace !== undefined) ordered.namespace = key.namespace;
  if (key.sharedWith !== undefined) ordered.sharedWith = key.sharedWith;
  if (key.sharedBy !== undefined) ordered.sharedBy = key.sharedBy;
  if (key.public) ordered.public = true;
  if (key.cached) ordered.cached = true;
  if (key.noNamespace) ordered.noNamespace = true;
  return ordered;
}

/** The key string of [key] under [namespace] unless it names its own. */
export function formatKey(key: AtKey, namespace?: string): string {
  const ns = key.noNamespace === true ? undefined : (key.namespace ?? namespace);
  const name = ns === undefined ? key.key : `${key.key}.${ns}`;
  const prefix = `${key.cached === true ? 'cached:' : ''}${key.public === true ? 'public:' : ''}`;
  return `${prefix}${key.sharedWith === undefined ? '' : `${key.sharedWith}:`}${name}${key.sharedBy ?? ''}`;
}
