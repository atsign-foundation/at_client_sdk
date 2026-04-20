<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![Pub Package](https://img.shields.io/pub/v/at_commons)](https://pub.dev/packages/at_commons)

# at_commons

**at_commons** provides the shared types, models, and utilities used across the atPlatform SDK. It has no dependency on any specific client implementation and can be used independently.

## AtKey

`AtKey` represents a key in the Atsign Protocol key-value store. Use the static factory methods to construct keys:

```dart
// Shared with another atSign
AtKey shared = AtKey.shared('phone', namespace: 'myapp', sharedBy: '@alice')
  ..sharedWith('@bob')
  ..build();

// Public (readable by anyone)
AtKey pub = AtKey.public('avatar', namespace: 'myapp', sharedBy: '@alice').build();

// Self (only readable by the owner)
AtKey self = AtKey.self('prefs', namespace: 'myapp', sharedBy: '@alice').build();

// Local (never synced to the cloud)
AtKey local = AtKey.local('cache', '@alice', namespace: 'myapp').build();

// Parse from a string
AtKey parsed = AtKey.fromString('@bob:phone.myapp@alice');
```

Key getters:

| Getter            | Example output           |
|-------------------|--------------------------|
| `fullKey`         | `phone.myapp`            |
| `fullKeyAndOwner` | `phone.myapp@alice`      |
| `toString()`      | `@bob:phone.myapp@alice` |

## Metadata

`Metadata` carries per-key settings. Common fields:

| Field            | Type        | Description                                                                |
|------------------|-------------|----------------------------------------------------------------------------|
| `ttl`            | `int?`      | Time-to-live in milliseconds                                               |
| `ttb`            | `int?`      | Time-to-birth (available-after delay) in milliseconds                      |
| `ttr`            | `int?`      | Recipient cache refresh interval in seconds; `-1` means cache indefinitely |
| `ccd`            | `bool?`     | Cascade-delete cached copies when the original is deleted                  |
| `isPublic`       | `bool?`     | Key is publicly readable                                                   |
| `isEncrypted`    | `bool?`     | Value is encrypted                                                         |
| `isBinary`       | `bool?`     | Value is binary data                                                       |
| `namespaceAware` | `bool`      | Whether the namespace is appended to the key                               |
| `immutable`      | `bool?`     | Key may not be updated once set                                            |
| `expiresAt`      | `DateTime?` | Computed expiry timestamp                                                  |
| `availableAt`    | `DateTime?` | Computed availability timestamp                                            |

## Atsign

`Atsign` is an extension type for validated, fully-qualified atSign strings (e.g. `@alice`). `AtsignWithoutAt` is the variant without the leading `@`.

```dart
Atsign alice = '@alice'.toAtsign();
```

## AtRootDomain

Represents a root server address including an optional port.

```dart
AtRootDomain root = AtRootDomain.parse('root.atsign.org:64');
// AtRootDomain.atsignDomain is the production default
```

## Exceptions

All exceptions extend `AtException`. The main sub-hierarchies are:

- **`AtConnectException`** — connection and authentication failures
  (`SecondaryServerConnectivityException`, `UnAuthorizedException`, `HandShakeException`, …)
- **`AtServerException`** — server-side errors
  (`InboundConnectionLimitException`, `LookupException`, `InternalServerException`, …)
- **`AtEnrollmentException`** — APKAM enrollment errors
  (`AtInvalidEnrollmentException`, `AtEnrollmentRevokeException`, `AtThrottleLimitExceeded`)
- Standalone: `InvalidAtKeyException`, `KeyNotFoundException`, `AtTimeoutException`,
  `InvalidAtSignException`, `AtSigningException`, `AtIOException`, and others

## Verb builders

Each builder constructs an Atsign Protocol command string via `buildCommand()`.

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

- **`AtBytes`** — wrapper for base64-encoded binary data
- **`KeyType`** — enum identifying a key as `selfKey`, `sharedKey`, `publicKey`, `localKey`, `cachedSharedKey`, etc.
- **`EnrollmentStatus`** — `pending`, `approved`, `denied`, `revoked`, `expired`
- **`PublicKeyHash`** — stores the hash and algorithm of a public encryption key
- **`SecureSocketConfig`** — TLS configuration for atServer connections
