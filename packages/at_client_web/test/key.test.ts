import { describe, expect, it } from 'vitest';
import { formatKey, parseKey, toBridgeKey } from '../src/key.js';

describe('toBridgeKey', () => {
  it('defaults the namespace and drops absent fields', () => {
    expect(toBridgeKey({ key: 'note' }, 'wavi')).toEqual({ key: 'note', namespace: 'wavi' });
  });

  it('keeps an explicit namespace, sharedWith and sharedBy', () => {
    expect(
      toBridgeKey({ key: 'k', namespace: 'tally', sharedWith: '@bob', sharedBy: '@alice' }, 'wavi'),
    ).toEqual({ key: 'k', namespace: 'tally', sharedWith: '@bob', sharedBy: '@alice' });
  });

  it('does not carry undefined properties onto the bridge object', () => {
    const bridgeKey = toBridgeKey({ key: 'k', sharedWith: undefined }, 'wavi');
    expect(Object.keys(bridgeKey).sort()).toEqual(['key', 'namespace']);
  });
});

describe('keys round-trip to the bridge', () => {
  const texts = [
    'note.wavi@alice',
    '@bob:note.wavi@alice',
    'public:note.wavi@alice',
    'cached:@bob:note.wavi@alice',
    'cached:public:note.wavi@alice',
    '@bob:shared_key@alice',
    'public:plain@alice',
  ];

  for (const text of texts) {
    it(`rebuilds ${text}`, () => {
      const bridge = toBridgeKey(parseKey(text, 'wavi'), 'wavi');
      const namespace = bridge.noNamespace ? undefined : bridge.namespace;
      const rebuilt = formatKey(
        {
          key: bridge.key,
          sharedWith: bridge.sharedWith,
          sharedBy: bridge.sharedBy,
          namespace,
          public: bridge.public,
          cached: bridge.cached,
          noNamespace: bridge.noNamespace,
        },
        'wavi',
      );
      expect(rebuilt).toBe(text);
    });
  }

  it('sends the flags and no default namespace for a key that had none', () => {
    expect(toBridgeKey(parseKey('public:plain@alice', 'wavi'), 'wavi')).toEqual({
      key: 'plain', sharedBy: '@alice', public: true, noNamespace: true,
    });
  });

  it('sends public and cached through', () => {
    expect(toBridgeKey({ key: 'k', public: true, cached: true }, 'wavi')).toEqual({
      key: 'k', namespace: 'wavi', public: true, cached: true,
    });
  });
});

describe('parseKey', () => {
  it('splits a self key into key, namespace and sharedBy', () => {
    expect(parseKey('@alice:note.wavi@alice', 'wavi')).toEqual({
      key: 'note', namespace: 'wavi', sharedWith: '@alice', sharedBy: '@alice',
    });
  });

  it('reads a key with no recipient prefix', () => {
    expect(parseKey('note.wavi@alice', 'wavi')).toEqual({
      key: 'note', namespace: 'wavi', sharedBy: '@alice',
    });
  });

  it('keeps dots in the key when the namespace is the default', () => {
    expect(parseKey('rpc.req.1.tally@alice', 'tally')).toEqual({
      key: 'rpc.req.1', namespace: 'tally', sharedBy: '@alice',
    });
  });

  it('takes the last segment as the namespace when it is not the default', () => {
    expect(parseKey('@bob:a.b.other@alice', 'wavi')).toEqual({
      key: 'a.b', namespace: 'other', sharedWith: '@bob', sharedBy: '@alice',
    });
  });

  it('carries the public and cached prefixes', () => {
    expect(parseKey('public:note.wavi@alice', 'wavi')).toEqual({
      key: 'note', namespace: 'wavi', sharedBy: '@alice', public: true,
    });
    expect(parseKey('cached:@bob:note.wavi@alice', 'wavi')).toEqual({
      key: 'note', namespace: 'wavi', sharedWith: '@bob', sharedBy: '@alice', cached: true,
    });
    expect(parseKey('cached:public:note.wavi@alice', 'wavi')).toEqual({
      key: 'note', namespace: 'wavi', sharedBy: '@alice', public: true, cached: true,
    });
  });

  it('leaves the namespace out of a key that has none and says so', () => {
    expect(parseKey('@bob:shared_key@alice')).toEqual({
      key: 'shared_key', sharedWith: '@bob', sharedBy: '@alice', noNamespace: true,
    });
  });

  it('accepts a string with no owner', () => {
    expect(parseKey('rpc.req.1.tally', 'tally')).toEqual({ key: 'rpc.req.1', namespace: 'tally' });
  });
});

describe('formatKey', () => {
  it('writes <key>.<namespace>@<sharedBy> with the default namespace', () => {
    expect(formatKey({ key: 'note', sharedBy: '@alice' }, 'wavi')).toBe('note.wavi@alice');
  });

  it('prefixes the recipient', () => {
    expect(formatKey({ key: 'k', namespace: 'tally', sharedWith: '@bob', sharedBy: '@alice' }, 'wavi')).toBe(
      '@bob:k.tally@alice',
    );
  });

  it('round-trips what parseKey reads', () => {
    for (const text of ['note.wavi@alice', '@bob:a.b.wavi@alice', '@alice:rpc.req.9.tally@alice', 'public:n.wavi@alice', 'cached:public:n.wavi@alice', '@bob:plain@alice']) {
      expect(formatKey(parseKey(text, 'wavi'), 'wavi')).toBe(text);
    }
  });
});
