import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// An in-memory keystore whose write of [parkedValue] waits for [release], so
/// a test can land another write inside that window.
class _ParkingKeyStore extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {
  final Map<String, AtData> data = {};
  String? parkedValue;
  final Completer<void> parked = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<bool> exists(String key) async => data.containsKey(key);

  @override
  Future<AtData?> get(String key) async => data[key];

  @override
  Future<AtMetaData?> getMeta(String key) async => data[key]?.metaData;

  @override
  Future<int?> putAll(String key, AtData value, AtMetaData? metadata) async {
    if (value.data == parkedValue) {
      parked.complete();
      await release.future;
    }
    data[key] = value..metaData = metadata;
    return null;
  }
}

/// Filing a record only when local storage holds none, as one step against
/// every other write to the same name.
void main() {
  const atSign = '@alice';
  const name = 'public:__nskey.app_1.my_apps@alice';

  UpdateVerbBuilder write(String value) => UpdateVerbBuilder()
    ..atKey = AtKey.fromString(name)
    ..value = value;

  LocalSecondary localSecondary(_ParkingKeyStore store) {
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentId).thenReturn(null);
    return LocalSecondary(atClient, keyStore: store);
  }

  test('writes a record local storage does not hold', () async {
    final store = _ParkingKeyStore();

    expect(
        await localSecondary(store)
            .putIfAbsent(write('fetched'), cameFromServer: true),
        isTrue);
    expect(store.data[name]?.data, 'fetched');
  });

  test('leaves a record local storage already holds', () async {
    final store = _ParkingKeyStore();
    final local = localSecondary(store);
    await local.executeVerb(write('synced'), cameFromServer: true);

    expect(await local.putIfAbsent(write('fetched'), cameFromServer: true),
        isFalse);
    expect(store.data[name]?.data, 'synced');
  });

  test('a write that lands while it is writing is not overwritten', () async {
    final store = _ParkingKeyStore()..parkedValue = 'fetched';
    final local = localSecondary(store);

    final filing = local.putIfAbsent(write('fetched'), cameFromServer: true);
    await store.parked.future;
    final synced = local.executeVerb(write('synced'), cameFromServer: true);
    await Future<void>.delayed(Duration.zero);
    store.release.complete();
    await Future.wait([filing, synced]);

    expect(store.data[name]?.data, 'synced',
        reason: 'the filing found the name absent and was mid-write when sync '
            'landed a newer copy; writing the older one over it would leave '
            'local storage behind the atServer, and sync would not bring the '
            'newer one back');
  });
}
