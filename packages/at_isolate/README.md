<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

# at_isolate

Run AtClient operations in a separate isolate for improved performance and isolation.

## Overview

`at_isolate` provides an isolate-based wrapper for the atProtocol's AtClient. By running AtClient in a dedicated isolate, you can:

- Prevent blocking the main isolate during heavy I/O operations
- Isolate AtClient state and credentials from the main application
- Enable concurrent AtClient usage with automatic serialization

## Features

- **Isolate-based**: AtClient runs in a separate isolate
- **Full API Coverage**: Implements all non-deprecated AtClient methods
- **Thread-safe**: Built-in mutex ensures safe concurrent access
- **Transparent**: Use just like a regular AtClient
- **Configurable**: Pass AtClientPreference for custom configuration

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  at_isolate: ^0.1.0
```

## Usage

### Basic Example

```dart
import 'package:at_isolate/at_isolate.dart';
import 'package:at_auth/at_auth.dart';

void main() async {
  // Load your atKeys
  final atKeys = await FileAtKeysIo().read('@alice');

  // Configure the client
  final preference = AtClientPreference()
    ..namespace = 'myapp'
    ..isLocalStoreRequired = false;

  // Spawn an isolated AtClient
  final client = await IsolatedAtClient.spawn(
    Atsign('@alice'),
    AtRootDomain.atsignDomain,
    atKeys,
    preference,
  );

  // Use it like a normal AtClient
  final key = AtKey()
    ..key = 'phone'
    ..namespace = 'myapp';

  await client.put(key, '+1 555 1234');
  final result = await client.get(key);
  print('Phone: ${result.value}');

  // Clean up
  client.close();
}
```

### With Local Storage

```dart
final preference = AtClientPreference()
  ..namespace = 'myapp'
  ..isLocalStoreRequired = true
  ..hiveStoragePath = '/tmp/@alice/hive'
  ..commitLogPath = '/tmp/@alice/commit';

final client = await IsolatedAtClient.spawn(
  Atsign('@alice'),
  AtRootDomain.atsignDomain,
  atKeys,
  preference,
);
```

### Supported Operations

The following AtClient operations are supported:

**Data Operations**
- `put()` - Store a value
- `putText()` - Store text data
- `putBinary()` - Store binary data
- `get()` - Retrieve a value
- `delete()` - Delete a key
- `putMeta()` - Update metadata
- `getMeta()` - Get metadata

**Query Operations**
- `getKeys()` - List keys as strings
- `getAtKeys()` - List keys as AtKey objects
- `getCurrentAtSign()` - Get the current atSign

**Notification Operations**
- `notifyList()` - List notifications
- `notifyStatus()` - Check notification status

**Authentication**
- `getOTP()` - Generate an OTP
- `setSPP()` - Set a semi-permanent passcode

### Unsupported Operations

The following are not implemented and throw `UnimplementedError`:

- Deprecated methods (notify, notifyChange, startMonitor, stream, file transfer)
- Service getters (syncService, notificationService, enrollmentService)
- Configuration methods (setPreferences, getPreferences)
- Internal services (getLocalSecondary, getRemoteSecondary, encryptionService)

## How It Works

1. **Spawning**: `IsolatedAtClient.spawn()` creates a new isolate and authenticates
2. **Message Passing**: Each AtClient operation is sent to the worker isolate
3. **Serialization**: AtKey, Metadata, and other objects are converted to records for isolate transfer
4. **Synchronization**: A mutex ensures operations are serialized
5. **Response**: The worker sends back the result, which is converted back to objects

## Performance

Running AtClient in an isolate provides:
- Non-blocking I/O in the main isolate
- Better responsiveness for UI applications
- Isolation of potentially slow operations

Overhead per operation is minimal (typically < 1ms for serialization).

## Testing

Run the test suite:

```bash
cd packages/at_isolate
dart test
```

For integration tests with real credentials:

```bash
TEST_ATSIGN=@alice TEST_KEYS_PATH=/path/to/keys dart test
```

## Examples

See the [example](example/) directory for more usage examples.

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md).

## License

See [LICENSE](LICENSE).
