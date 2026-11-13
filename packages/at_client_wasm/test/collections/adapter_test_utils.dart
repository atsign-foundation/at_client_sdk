// Fixtures for the JS collections adapter tests.
//
// An in-memory keystore is shared by every [FakeAtClient] of one
// [FakeAtServer]. Each client is a mocktail [AtClient] whose key operations
// read and write that store as its own atSign, so an upstream AtCollection
// runs for real: it writes self copies and recipient copies, lists them, and
// reads them back. Visibility follows the atServer rule: a key is visible to
// the atSign that owns it (sharedBy) and to the atSign it is shared with
// (sharedWith).
//
// Event injection uses the upstream test hooks from package:at_client/testing.dart.
// Every AtCollection built here is on the EventSource.both path, whatever
// eventSource the adapter asked for; the adapter's eventSource choice is
// asserted through the mocked `AtClient.collection` call instead.

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';

const Duration testExpiration = Duration(days: 7);

/// Registers the fallback values mocktail needs for `any()` matchers.
void registerAdapterFallbacks() {
  registerFallbackValue(FakeAtKey());
  registerFallbackValue(EventSource.data);
  registerFallbackValue(const Duration());
  registerFallbackValue('');
  registerFallbackValue(false);
}

class MockAtClient extends Mock implements AtClient {}

class FakeAtKey extends Fake implements AtKey {}

class MockAtCollection extends Mock
    implements AtCollection<Map<String, dynamic>> {}

class _StoredKey {
  _StoredKey(this.key, this.value);

  final AtKey key;
  final String value;
}

/// An in-memory atServer shared by the clients of one test.
class FakeAtServer {
  final Map<String, _StoredKey> _store = {};
  final Map<String, FakeAtClient> _clients = {};

  /// The client acting as [atSign], created on first use.
  FakeAtClient client(String atSign) => _clients.putIfAbsent(
      atSign, () => FakeAtClient._(this, atSign.toAtsign()));

  bool _visibleTo(AtKey key, Atsign me) =>
      key.sharedBy?.toAtsign() == me || key.sharedWith?.toAtsign() == me;

  AtValue _get(Atsign me, AtKey key) {
    final stored = _store[key.toString()];
    if (stored == null || !_visibleTo(stored.key, me)) {
      throw KeyNotFoundException('no key ${key.toString()}');
    }
    return AtValue()
      ..value = stored.value
      ..metadata = stored.key.metadata;
  }

  /// Whether a key named [key] (its `AtKey.toString()` form) is stored.
  bool hasKey(String key) => _store.containsKey(key);

  /// The stored value of the key named [key], or null.
  String? storedValue(String key) => _store[key]?.value;

  /// Stores [value] under [key] as it is, as another device's write would.
  void putRaw(String key, String value) => _put(AtKey.fromString(key), value);

  bool _put(AtKey key, String value) {
    final metadata = key.metadata;
    metadata.createdAt ??= DateTime.now().toUtc();
    metadata.expiresAt ??= DateTime.now().toUtc().add(testExpiration);
    _store[key.toString()] = _StoredKey(key, value);
    return true;
  }

  bool _delete(AtKey key) {
    _store.remove(key.toString());
    return true;
  }

  /// Replaces the stored value of every key that [match] accepts with [value],
  /// leaving the key and its metadata as they are.
  void overwriteValues(bool Function(AtKey key) match, String value) {
    for (final entry in _store.entries.toList()) {
      if (match(entry.value.key)) {
        _store[entry.key] = _StoredKey(entry.value.key, value);
      }
    }
  }

  List<AtKey> _keys(Atsign me, String? regex) {
    final pattern = RegExp(regex ?? '.*');
    return [
      for (final stored in _store.values)
        if (_visibleTo(stored.key, me) &&
            pattern.hasMatch(stored.key.toString()))
          stored.key,
    ];
  }
}

/// A mocktail [AtClient] for one atSign, backed by a [FakeAtServer].
class FakeAtClient {
  FakeAtClient._(this._server, this.atSign) {
    _stubKeyOperations();
    _stubCollectionFactory();
  }

  final FakeAtServer _server;
  final Atsign atSign;

  final MockAtClient mock = MockAtClient();

  final List<Object> _collectionFailures = [];

  void Function(AtKey key)? _beforePut;
  bool Function(AtKey key)? _failPuts;

  /// Calls [hook] once, before the next `AtClient.put` of a key that [match]
  /// accepts is stored. Tests use it to land another device's write in the
  /// middle of a write.
  void beforeNextPut(bool Function(AtKey key) match, void Function() hook) {
    _beforePut = (key) {
      if (!match(key)) return;
      _beforePut = null;
      hook();
    };
  }

  /// Makes every `AtClient.put` of a key that [match] accepts fail.
  void failPutsFor(bool Function(AtKey key) match) => _failPuts = match;

  /// Makes the next `AtClient.collection` call return a failed future with
  /// [error].
  void failNextCollection(Object error) => _collectionFailures.add(error);

  /// Feeds the upstream collections built for this client.
  final StreamController<AtNotification> notifications =
      StreamController<AtNotification>.broadcast();

  /// Feeds the upstream collections built for this client. Tests inject
  /// local keystore mutations here.
  final StreamController<DataEvent> dataEvents =
      StreamController<DataEvent>.broadcast();

  void _stubKeyOperations() {
    when(() => mock.atSign).thenReturn(atSign);
    when(() => mock.getLocalSecondary()).thenReturn(null);
    when(() => mock.pendingEmissions).thenAnswer((_) async {});
    when(() => mock.put(any(), any())).thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      if (_failPuts?.call(key) ?? false) {
        throw AtClientException.message('put refused by the test');
      }
      _beforePut?.call(key);
      return _server._put(key, inv.positionalArguments[1] as String);
    });
    when(() => mock.get(any())).thenAnswer((inv) => Future.sync(
        () => _server._get(atSign, inv.positionalArguments[0] as AtKey)));
    when(() => mock.delete(any())).thenAnswer(
        (inv) async => _server._delete(inv.positionalArguments[0] as AtKey));
    when(() => mock.getAtKeys(regex: any(named: 'regex'))).thenAnswer(
        (inv) async =>
            _server._keys(atSign, inv.namedArguments[#regex] as String?));
  }

  /// Every adapter `AtClient.collection` call gets a real upstream collection
  /// over this client, carrying the `writeTypeTag` the adapter passed.
  void _stubCollectionFactory() {
    when(() => mock.collection<Map<String, dynamic>>(
          any(),
          any(),
          eventSource: any(named: 'eventSource'),
          fromJson: any(named: 'fromJson'),
          typeTag: any(named: 'typeTag'),
          writeTypeTag: any(named: 'writeTypeTag'),
          cleanupOrphansOnCreation: any(named: 'cleanupOrphansOnCreation'),
        )).thenAnswer((inv) {
      if (_collectionFailures.isNotEmpty) {
        return Future<AtCollection<Map<String, dynamic>>>.error(
          _collectionFailures.removeAt(0),
        );
      }
      return Future.value(collectionWithInjectedBoth<Map<String, dynamic>>(
        mock,
        inv.positionalArguments[0] as String,
        inv.positionalArguments[1] as Duration,
        notifications: notifications.stream,
        dataEvents: dataEvents.stream,
        writeTypeTag: inv.namedArguments[#writeTypeTag] as String?,
      ));
    });
  }

  Future<void> dispose() async {
    await notifications.close();
    await dataEvents.close();
  }
}

/// An upstream collection over [client] for [namespace], written with
/// [writeTypeTag] when given. Used to seed items the adapter does not write.
AtCollection<Map<String, dynamic>> rawCollection(
  FakeAtClient client,
  String namespace, {
  String? writeTypeTag,
}) =>
    collectionWithInjectedBoth<Map<String, dynamic>>(
      client.mock,
      namespace,
      testExpiration,
      notifications: client.notifications.stream,
      dataEvents: client.dataEvents.stream,
      writeTypeTag: writeTypeTag,
    );

/// Lets queued upstream events run to completion.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
