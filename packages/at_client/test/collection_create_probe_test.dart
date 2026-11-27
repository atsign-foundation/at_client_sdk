import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Catalogue: features/at_client/collection_create_probe.feature
void main() {
  setUpAll(() => registerFallbackValue(FakeAtKey()));

  const namespace = 'todos.demo';
  final alice = '@alice'.toAtsign();

  late MockAtClient atClient;
  late StreamController<AtNotification> notifications;

  /// This device's keystore: each key's string form to the value stored.
  late Map<String, String> local;

  /// The atServer's keystore, same shape. A write through the collection
  /// lands in both, as sync keeps them in step.
  late Map<String, String> remote;

  /// A lookup routed to local storage, or to the atServer, can be told to
  /// fail with the error returned here instead of answering from its store.
  late Object? Function(AtKey key)? localFailure;
  late Object? Function(AtKey key)? remoteFailure;

  String keyFor(String id) => '$id.$namespace@alice';

  /// Stores [value] under [id] in [store] as another writer would, with live
  /// metadata.
  void seed(Map<String, String> store, String id, String value) {
    final key = AtKey.fromString(keyFor(id))
      ..metadata = (Metadata()
        ..createdAt = DateTime.now().toUtc()
        ..expiresAt = DateTime.now().toUtc().add(const Duration(days: 7)));
    store[key.toString()] = value;
  }

  setUp(() {
    atClient = MockAtClient();
    notifications = StreamController<AtNotification>.broadcast();
    local = {};
    remote = {};
    localFailure = null;
    remoteFailure = null;

    when(() => atClient.atSign).thenReturn(alice);
    when(() => atClient.getAtKeys(regex: any(named: 'regex')))
        .thenAnswer((inv) async {
      final pattern = RegExp(inv.namedArguments[#regex] as String);
      return [
        for (final key in {...local.keys, ...remote.keys})
          if (pattern.hasMatch(key)) AtKey.fromString(key),
      ];
    });
    when(() => atClient.get(any())).thenAnswer((inv) async {
      final key = inv.positionalArguments.first as AtKey;
      final value = local[key.toString()];
      if (value == null) throw AtKeyNotFoundException('no record for $key');
      return AtValue()
        ..value = value
        ..metadata = (Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().toUtc().add(const Duration(days: 7)));
    });
    when(() => atClient.getMeta(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments.first as AtKey;
      final atServer =
          (inv.namedArguments[#getRequestOptions] as GetRequestOptions?)
                  ?.useRemoteAtServer ==
              true;
      final store = atServer ? remote : local;
      final failure = (atServer ? remoteFailure : localFailure)?.call(key);
      if (failure != null) throw failure;
      if (!store.containsKey(key.toString())) {
        throw AtKeyNotFoundException('no record for $key');
      }
      return Metadata()
        ..createdAt = DateTime.now().toUtc()
        ..expiresAt = DateTime.now().toUtc().add(const Duration(days: 7));
    });
    when(() => atClient.put(any(), any())).thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      final value = inv.positionalArguments[1] as String;
      local[key.toString()] = value;
      remote[key.toString()] = value;
      return true;
    });
    when(() => atClient.delete(any())).thenAnswer((inv) async {
      final key = (inv.positionalArguments.first as AtKey).toString();
      local.remove(key);
      remote.remove(key);
      return true;
    });
  });

  tearDown(() => notifications.close());

  Future<AtCollection<String>> build() async {
    final collection = collectionWithInjectedNotifications<String>(
      atClient,
      namespace,
      const Duration(days: 7),
      notifications: notifications.stream,
    );
    await pumpEventQueue();
    clearInteractions(atClient);
    return collection;
  }

  test('create with an id does not overwrite when the existence check fails',
      () async {
    const original = 'first';
    seed(remote, 'i1', original);
    remoteFailure = (_) => AtTimeoutException('no answer');
    final todos = await build();

    await expectLater(
      todos.create(obj: 'second', id: 'i1'),
      throwsA(isA<AtTimeoutException>()),
      reason: 'the lookup failed, so the id is not known to be free',
    );

    expect(remote[keyFor('i1')], original);
    verifyNever(() => atClient.put(any(), any()));
  });

  test('create with an id succeeds after the item was deleted elsewhere',
      () async {
    final todos = await build();
    await todos.create(obj: 'first', id: 'i1');

    // Another client of this atSign deletes the item. Only
    // AtCollection.delete evicts the seen-id cache, so this process still
    // holds "i1" there.
    await atClient.delete(AtKey.fromString(keyFor('i1')));
    clearInteractions(atClient);

    final again = await todos.create(obj: 'second', id: 'i1');

    expect(again.id, 'i1');
    expect(remote[keyFor('i1')], isNotNull);
    verify(() => atClient.getMeta(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).called(2);

    // The same holds when the record expires instead of being deleted: the
    // store answers not-found either way, and the cache is not consulted.
    await todos.create(obj: 'first', id: 'i2');
    local.remove(keyFor('i2'));
    remote.remove(keyFor('i2'));
    clearInteractions(atClient);

    final renewed = await todos.create(obj: 'second', id: 'i2');

    expect(renewed.id, 'i2');
    expect(remote[keyFor('i2')], isNotNull);
    verify(() => atClient.getMeta(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).called(2);
  });

  test('an upsert whose existence check fails behaves as before', () async {
    remoteFailure = (_) => AtTimeoutException('no answer');
    final todos = await build();

    final item = await todos.upsert(obj: 'v', id: 'i1');

    expect(item.id, 'i1');
    expect(remote[keyFor('i1')], isNotNull);
  });

  test('create with an id whose local lookup fails is refused as existing',
      () async {
    const original = 'first';
    seed(local, 'i1', original);
    localFailure = (_) => AtClientException.message('local store is down');
    final todos = await build();

    await expectLater(
      todos.create(obj: 'second', id: 'i1'),
      throwsA(isA<StateError>()),
      reason: 'a local lookup that fails for any reason but absence counts '
          'as held',
    );

    expect(local[keyFor('i1')], original);
    verifyNever(() => atClient.put(any(), any()));
  });
}
