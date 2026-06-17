<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![Pub Package](https://img.shields.io/pub/v/at_commons)](https://pub.dev/packages/at_commons)

# at_commons

Foundational types used across every package in the Atsign Protocol SDK:
key representations, metadata, atSign validation, root-domain parsing,
verb builders (Atsign Protocol wire format), and the exception hierarchy.

`at_commons` is a pure-Dart library with no dependency on any specific
client implementation. Most application developers consume these types
transitively via [`at_client`](../at_client); you'll reach for
`at_commons` directly when you need to construct an `AtKey` by hand,
interpret exceptions, or build Atsign Protocol verbs at a lower level.

## AtKey

`AtKey` represents a key in the atServer keystore. Prefer the static
factory methods over the field-builder form — they encode the key
*shape* (self / shared / public / local / cached) at the type level:

```dart
// Shared with another atSign
AtKey shared = (AtKey.shared('phone', namespace: 'myapp', sharedBy: '@alice')
      ..sharedWith('@bob'))
    .build();

// Public (readable by anyone)
AtKey pub = AtKey.public('avatar', namespace: 'myapp', sharedBy: '@alice').build();

// Self (only readable by the owner)
AtKey self = AtKey.self('prefs', namespace: 'myapp', sharedBy: '@alice').build();

// Local (never synced to the cloud)
AtKey local = AtKey.local('cache', '@alice', namespace: 'myapp').build();

// Parse from a wire-format string
AtKey parsed = AtKey.fromString('@bob:phone.myapp@alice');
```

Useful getters:

| Getter            | Example output           |
|-------------------|--------------------------|
| `fullKey`         | `phone.myapp`            |
| `fullKeyAndOwner` | `phone.myapp@alice`      |
| `toString()`      | `@bob:phone.myapp@alice` |

## atKeys runtime models

`AtKeysSet` is the runtime container for authentication key material. It is
separate from `AtKey`, which models an atServer keystore key name.

To create a new asymmetric key pair and add it to an `AtKeysSet`, construct an
`AtAsymmetricKey` and call `addKey`:

```dart
AtKeysSet atKeysSet = AtKeysSet(
  atsign: '@alice'.toAtsign(),
  asymmetricKeys: [],
  symmetricKeys: [],
  defaults: AtKeysDefaults(values: {
    KeyPurposes.pkam: 'device-pkam',
  }),
);

AtAsymmetricKey pkamKeyPair = AtAsymmetricKey(
  pairId: 'device-pkam',
  purpose: KeyPurposes.pkam,
  algorithm: 'rsa-2048',
  publicKey: AtBytes.fromString('cGthbS1wdWJsaWMta2V5'),
  privateKey: AtBytes.fromString('cGthbS1wcml2YXRlLWtleQ=='),
  operations: ['authenticate', 'sign', 'verify'],
);

atKeysSet.addKey(pkamKeyPair);
```

Use `addKeys` when adding multiple runtime key models:

```dart
AtSymmetricKey selfEncryptionKey = AtSymmetricKey(
  id: 'self-encryption',
  purpose: KeyPurposes.selfEncryption,
  algorithm: 'aes-256',
  bytes: AtBytes.fromString('c2VsZi1lbmNyeXB0aW9uLWtleQ=='),
  operations: ['encrypt', 'decrypt'],
);

atKeysSet.addKeys(<AtKeysMaterial>[
  pkamKeyPair,
  selfEncryptionKey,
]);
```

`AtKeysSet.addKey` rejects duplicate asymmetric `pairId` values and duplicate
symmetric `id` values.

## Metadata

`Metadata` carries per-key settings. The fields most app code actually
touches:

| Field            | Type        | Description                                                                |
|------------------|-------------|----------------------------------------------------------------------------|
| `ttl`            | `int?`      | Time-to-live in ms (key self-expires)                                      |
| `ttb`            | `int?`      | Time-to-birth in ms (key becomes visible after this delay)                 |
| `ttr`            | `int?`      | Recipient cache refresh interval in seconds; `-1` means cache indefinitely |
| `ccd`            | `bool?`     | Cascade-delete cached copies when the original is deleted                  |
| `isPublic`       | `bool?`     | Key is publicly readable                                                   |
| `isEncrypted`    | `bool?`     | Value is encrypted                                                         |
| `isBinary`       | `bool?`     | Value is binary data                                                       |
| `namespaceAware` | `bool`      | Whether the namespace is appended to the key on the wire                   |
| `immutable`      | `bool?`     | Key may not be updated once set                                            |
| `expiresAt`      | `DateTime?` | Derived expiry timestamp (from `ttl`)                                      |
| `availableAt`    | `DateTime?` | Derived availability timestamp (from `ttb`)                                |

## Atsign / AtRootDomain

```dart
Atsign alice = '@alice'.toAtsign();          // validated, fully qualified
AtsignWithoutAt a = alice.withoutAt;         // no leading '@'

AtRootDomain root = AtRootDomain.parse('root.atsign.org:64');
AtRootDomain prod = AtRootDomain.atsignDomain; // production default
```

## Exceptions

All exceptions extend `AtException`. The main sub-hierarchies are:

- **`AtConnectException`** — connection / auth failures
  (`SecondaryServerConnectivityException`, `UnAuthorizedException`,
  `HandShakeException`, …)
- **`AtServerException`** — server-side errors
  (`InboundConnectionLimitException`, `LookupException`,
  `InternalServerException`, …)
- **`AtEnrollmentException`** — APKAM enrollment failures
  (`AtInvalidEnrollmentException`, `AtEnrollmentRevokeException`,
  `AtThrottleLimitExceeded`)
- Standalone: `InvalidAtKeyException`, `KeyNotFoundException`,
  `AtTimeoutException`, `InvalidAtSignException`, `AtSigningException`,
  `AtIOException`, and others.

## Verb builders

Each builder constructs an Atsign Protocol wire command via `buildCommand()`.
Application code normally doesn't touch these directly — the client
packages use them internally — but they're exposed for lower-level
tooling (see the test suite in [`test/`](test) for concrete usage).

| Builder              | Protocol verb |
|----------------------|---------------|
| `UpdateVerbBuilder`  | `update:`     |
| `DeleteVerbBuilder`  | `delete:`     |
| `LookupVerbBuilder`  | `lookup:`     |
| `LLookupVerbBuilder` | `llookup:`    |
| `PLookupVerbBuilder` | `plookup:`    |
| `ScanVerbBuilder`    | `scan`        |
| `NotifyVerbBuilder`  | `notify:`     |
| `MonitorVerbBuilder` | `monitor`     |
| `SyncVerbBuilder`    | `sync:`       |
| `EnrollVerbBuilder`  | `enroll:`     |
| `StatsVerbBuilder`   | `stats:`      |

## Other types

- **`AtBytes`** — wrapper for base64-encoded binary payloads
- **`KeyType`** — `selfKey`, `sharedKey`, `publicKey`, `localKey`,
  `cachedSharedKey`, …
- **`EnrollmentStatus`** — `pending`, `approved`, `denied`, `revoked`,
  `expired`
- **`PublicKeyHash`** — hash + algorithm of a public encryption key
- **`SecureSocketConfig`** — TLS configuration for atServer connections

## Where to go next

- [`at_client`](../at_client) — the client that uses these types
- [`at_auth`](../at_auth) — onboarding / authentication that produces
  the keys embedded in `AtKey`
