// Unit tests for RemoteWriteThroughKeyStore — the AtKeyValueStore that goes
// straight to the atServer via RemoteSecondary, with no local commit log,
// per D-18 item 3 ("a write-through implementation satisfies the durable-
// keystore contract"). See plans/wasm/spike/pb3-stage2b-plan.md.

import 'package:at_client/src/storage/local_record_store.dart';
import 'package:at_client/src/storage/remote_write_through_keystore.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _TransportException implements Exception {
  final String message;
  _TransportException(this.message);
  @override
  String toString() => 'TransportException: $message';
}

void main() {
  late MockRemoteSecondary remoteSecondary;
  late RemoteWriteThroughKeyStore store;

  setUpAll(() {
    registerFallbackValue(LLookupVerbBuilder());
  });

  setUp(() {
    remoteSecondary = MockRemoteSecondary();
    store = RemoteWriteThroughKeyStore(remoteSecondary, maxAttempts: 3);
  });

  /// A `llookup:all` success body, shaped like `AtData.fromJson`/`AtMetaData.fromJson`
  /// expect: top-level `data`/`metaData`, with metaData's own `createdAt`/`updatedAt`
  /// always present (fromJson has no null guard for those two).
  String llookupAllResponse({int? ttl, bool? isBinary}) {
    final now = DateTime.now().toUtc().toString();
    final metaData = <String, dynamic>{
      'createdAt': now,
      'updatedAt': now,
      if (ttl != null) AtConstants.ttl: ttl,
      if (isBinary != null) AtConstants.isBinary: isBinary,
    };
    return 'data:{"data":"phone-value","metaData":${_jsonEncode(metaData)}}';
  }

  group('put', () {
    test('sends update:key value via executeCommand', () async {
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:1');

      final result =
          await store.put('@alice:phone@bob', AtData()..data = '12345');

      expect(result, isNull,
          reason: 'no commit log — every write returns null');
      final captured =
          verify(() => remoteSecondary.executeCommand(captureAny(), auth: true))
              .captured
              .single as String;
      expect(captured, 'update:@alice:phone@bob 12345\n');
    });
  });

  group('putMeta / putAll — metadata fragment is not hand-mapped and dropped',
      () {
    test('putMeta appends the fragment after the key', () async {
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:1');

      final meta = AtMetaData()
        ..ttl = 60000
        ..isBinary = true;
      await store.putMeta('@alice:phone@bob', meta);

      final captured =
          verify(() => remoteSecondary.executeCommand(captureAny(), auth: true))
              .captured
              .single as String;
      expect(captured, startsWith('update:meta:@alice:phone@bob'));
      expect(captured, contains(':ttl:60000'));
      expect(captured, contains(':isBinary:true'));
    });

    test('putAll prepends the fragment before the key', () async {
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:1');

      final meta = AtMetaData()..ttl = 60000;
      await store.putAll('@alice:phone@bob', AtData()..data = '12345', meta);

      final captured =
          verify(() => remoteSecondary.executeCommand(captureAny(), auth: true))
              .captured
              .single as String;
      expect(captured, startsWith('update:ttl:60000'));
      expect(captured, contains(':@alice:phone@bob 12345'));
    });
  });

  group('every write is one newline-terminated protocol line', () {
    final writes = <String, Future<void> Function(RemoteWriteThroughKeyStore)>{
      'put': (s) => s.put('@alice:phone@bob', AtData()..data = '12345'),
      'putMeta': (s) =>
          s.putMeta('@alice:phone@bob', AtMetaData()..ttl = 60000),
      'putAll': (s) => s.putAll(
          '@alice:phone@bob', AtData()..data = '12345', AtMetaData()..ttl = 1),
      'remove': (s) => s.remove('@alice:phone@bob'),
    };
    for (final MapEntry(key: name, value: write) in writes.entries) {
      test(name, () async {
        when(() => remoteSecondary.executeCommand(any(), auth: true))
            .thenAnswer((_) async => 'data:1');

        await write(store);

        final captured = verify(
                () => remoteSecondary.executeCommand(captureAny(), auth: true))
            .captured
            .single as String;
        expect(captured, endsWith('\n'));
        expect('\n'.allMatches(captured), hasLength(1));
      });
    }
  });

  group('remove', () {
    test('sends delete:key via executeCommand', () async {
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:1');

      await store.remove('@alice:phone@bob');

      verify(() => remoteSecondary.executeCommand('delete:@alice:phone@bob\n',
          auth: true)).called(1);
    });
  });

  group('get / getMeta', () {
    test('get builds an LLookupVerbBuilder(operation: all) and decodes AtData',
        () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => llookupAllResponse(ttl: 60000));

      final result = await store.get('@alice:phone@bob');

      expect(result?.data, 'phone-value');
      expect(result?.metaData?.ttl, 60000);

      final captured = verify(() => remoteSecondary.executeVerb(captureAny()))
          .captured
          .single as LLookupVerbBuilder;
      expect(captured.operation, 'all');
      expect(captured.atKey.toString(), '@alice:phone@bob');
    });

    test('getMeta returns just the metadata half of the same response',
        () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => llookupAllResponse(isBinary: true));

      final meta = await store.getMeta('@alice:phone@bob');

      expect(meta?.isBinary, true);
    });

    test('get stamps the AtData with the key it was read under', () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => llookupAllResponse());

      final result = await store.get('@alice:phone@bob');

      expect(result?.key, '@alice:phone@bob',
          reason: "LocalSecondary's llookup:all reply is AtData.toJson(), and "
              'GetResponseTransformer reads its key');
    });

    test(
        'AtKey.fromString round-trips the PKAM private key back to the '
        'exact wire string', () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => llookupAllResponse());

      await store.get('privatekey:at_pkam_privatekey');

      final captured = verify(() => remoteSecondary.executeVerb(captureAny()))
          .captured
          .single as LLookupVerbBuilder;
      expect(captured.atKey.toString(), 'privatekey:at_pkam_privatekey');
    });

    test(
        'AtKey.fromString round-trips a public key back to the exact wire '
        'string', () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => llookupAllResponse());

      await store.get('public:publickey@alice');

      final captured = verify(() => remoteSecondary.executeVerb(captureAny()))
          .captured
          .single as LLookupVerbBuilder;
      expect(captured.atKey.toString(), 'public:publickey@alice');
    });
  });

  group('getKeys', () {
    test('sends a ScanVerbBuilder(regex) via executeVerb and decodes the list',
        () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => 'data:["@alice:k1@bob","@alice:k2@bob"]');

      final keys = await (await store.getKeys(regex: '.*')).toList();

      expect(keys, ['@alice:k1@bob', '@alice:k2@bob']);
      final captured = verify(() => remoteSecondary.executeVerb(captureAny()))
          .captured
          .single as ScanVerbBuilder;
      expect(captured.regex, '.*');
      expect(captured.auth, isTrue);
    });
  });

  group('retry', () {
    test('succeeds after two transport failures — invoked exactly 3 times',
        () async {
      var calls = 0;
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async {
        calls++;
        if (calls < 3) throw _TransportException('connection reset');
        return 'data:1';
      });

      await store.put('@alice:phone@bob', AtData()..data = '12345');

      expect(calls, 3);
    });

    test('exhausts maxAttempts then rethrows the underlying exception',
        () async {
      var calls = 0;
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async {
        calls++;
        throw _TransportException('connection reset');
      });

      await expectLater(
        () => store.put('@alice:phone@bob', AtData()..data = '12345'),
        throwsA(isA<_TransportException>()),
      );
      expect(calls, 3, reason: 'exactly maxAttempts, no more, no fewer');
    });

    test('KeyNotFoundException on get propagates on the first call, uncounted',
        () async {
      var calls = 0;
      when(() => remoteSecondary.executeVerb(any())).thenAnswer((_) async {
        calls++;
        throw KeyNotFoundException('@alice:phone@bob not found');
      });

      await expectLater(
        () => store.get('@alice:phone@bob'),
        throwsA(isA<KeyNotFoundException>()),
      );
      expect(calls, 1,
          reason: 'a miss is normal control flow, not a retry-able failure');
    });
  });

  group('exists', () {
    test('a remote key the llookup finds exists', () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => llookupAllResponse());

      expect(await store.exists('@alice:phone@bob'), isTrue);
    });

    test('a remote key the atServer reports missing does not exist', () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenThrow(KeyNotFoundException('@alice:phone@bob not found'));

      expect(await store.exists('@alice:phone@bob'), isFalse);
    });

    test('a local key exists once put, and not after remove', () async {
      const localKey = 'local:lastreceivednotification@alice';
      expect(await store.exists(localKey), isFalse);

      await store.put(localKey, AtData()..data = 'n-42');
      expect(await store.exists(localKey), isTrue);

      await store.remove(localKey);
      expect(await store.exists(localKey), isFalse);
      verifyNever(() => remoteSecondary.executeVerb(any()));
    });
  });

  group('unsupported members', () {
    test('throw UnsupportedError', () async {
      expect(() => store.create('k', AtData()), throwsUnsupportedError);
      expect(() => store.scanKeys(KeyPattern()), throwsUnsupportedError);
      expect(
          () => store.queryByPath(
              keyPattern: KeyPattern(),
              predicate: const PathEquals(['data'], null)),
          throwsUnsupportedError);
      expect(() => store.snapshot(), throwsUnsupportedError);
      expect(() => store.getMany(['k']), throwsUnsupportedError);
      expect(() => store.removeMany(['k']), throwsUnsupportedError);
      expect(
          () => store.transaction((txn) async => null), throwsUnsupportedError);
      expect(() => store.stats(), throwsUnsupportedError);
      expect(() => store.getExpiredKeys(), throwsUnsupportedError);
      expect(() => store.deleteExpiredKeys(), throwsUnsupportedError);
      expect(() => store.peekExpired(), throwsUnsupportedError);
      expect(() => store.compact(true), throwsUnsupportedError);
    });
  });

  group('dead-but-must-answer and safe defaults', () {
    test('nextExpiresAt / nextAvailableAt return null', () async {
      expect(await store.nextExpiresAt(), isNull);
      expect(await store.nextAvailableAt(), isNull);
    });

    test('peekNewlyAvailable is empty: nothing is held to become available',
        () async {
      expect(
          await (await store.peekNewlyAvailable(since: DateTime(0))).toList(),
          isEmpty);
    });

    test('changes is an empty broadcast stream', () async {
      expect(store.changes.isBroadcast, isTrue);
      expect(await store.changes.isEmpty, isTrue);
    });

    test('preRemoveHooks / postRemoveHooks are empty', () {
      expect(store.preRemoveHooks, isEmpty);
      expect(store.postRemoveHooks, isEmpty);
    });

    test('supportsSnapshots / supportsPathQueries are false', () {
      expect(store.supportsSnapshots, isFalse);
      expect(store.supportsPathQueries, isFalse);
    });

    test('commitLog getter is null, setter is a no-op', () {
      expect(store.commitLog, isNull);
      store.commitLog = null;
      expect(store.commitLog, isNull);
    });
  });

  group('local: keys stay in the session and never reach the atServer', () {
    const localKey = 'local:lastreceivednotification@alice';

    tearDown(() {
      verifyNever(() =>
          remoteSecondary.executeCommand(any(), auth: any(named: 'auth')));
    });

    test('put then get round-trips without a remote call', () async {
      await store.put(localKey, AtData()..data = 'n-42');

      expect((await store.get(localKey))!.data, 'n-42');
      verifyNever(() => remoteSecondary.executeVerb(any()));
    });

    test('putAll then getMeta returns the stored metadata', () async {
      final meta = AtMetaData()..ttl = 1000;
      await store.putAll(localKey, AtData()..data = 'n-42', meta);

      expect((await store.getMeta(localKey))!.ttl, 1000);
    });

    test('putMeta replaces the metadata of an existing local value', () async {
      await store.put(localKey, AtData()..data = 'n-42');
      await store.putMeta(localKey, AtMetaData()..ttl = 7);

      final data = (await store.get(localKey))!;
      expect(data.data, 'n-42');
      expect(data.metaData!.ttl, 7);
    });

    test('get of an absent local key throws KeyNotFoundException', () async {
      expect(() => store.get(localKey), throwsA(isA<KeyNotFoundException>()));
      verifyNever(() => remoteSecondary.executeVerb(any()));
    });

    test('remove drops the value', () async {
      await store.put(localKey, AtData()..data = 'n-42');
      await store.remove(localKey);

      expect(() => store.get(localKey), throwsA(isA<KeyNotFoundException>()));
    });

    test('the local: prefix is matched case-insensitively', () async {
      await store.put('LOCAL:Mixed@alice', AtData()..data = 'x');

      expect((await store.get('LOCAL:Mixed@alice'))!.data, 'x');
    });

    test('getKeys merges regex-matching local keys into the remote scan',
        () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => 'data:["@alice:k1@bob"]');
      await store.put(localKey, AtData()..data = 'n-42');
      await store.put('local:other@alice', AtData()..data = 'x');

      final keys =
          await (await store.getKeys(regex: 'lastreceived|k1')).toList();

      expect(keys, unorderedEquals(['@alice:k1@bob', localKey]));
    });
  });

  group('local records go to the injected LocalRecordStore', () {
    const localKey = 'local:x.wavi@alice';
    late InMemoryLocalRecordStore localStore;
    late RemoteWriteThroughKeyStore keystore;

    setUp(() {
      localStore = InMemoryLocalRecordStore();
      keystore = RemoteWriteThroughKeyStore(remoteSecondary,
          maxAttempts: 3, localStore: localStore);
    });

    test('put lands in the injected store and never reaches the remote',
        () async {
      await keystore.put(localKey, AtData()..data = 'v');

      expect((await localStore.get(localKey))!.data, 'v');
      verifyNever(() =>
          remoteSecondary.executeCommand(any(), auth: any(named: 'auth')));
      verifyNever(() => remoteSecondary.executeVerb(any()));
    });

    test('get reads a local key from the injected store', () async {
      await localStore.put(localKey, AtData()..data = 'from-store');

      expect((await keystore.get(localKey))!.data, 'from-store');
    });

    test('get of an absent local key throws KeyNotFoundException', () async {
      expect(
          () => keystore.get(localKey), throwsA(isA<KeyNotFoundException>()));
    });

    test('remove deletes from the injected store', () async {
      await localStore.put(localKey, AtData()..data = 'v');
      await keystore.remove(localKey);

      expect(await localStore.get(localKey), isNull);
    });

    test('putMeta replaces the metadata of the injected value', () async {
      await localStore.put(localKey, AtData()..data = 'v');
      await keystore.putMeta(localKey, AtMetaData()..ttl = 7);

      expect((await localStore.get(localKey))!.metaData!.ttl, 7);
    });

    test('putAll stores value and metadata in the injected store', () async {
      await keystore.putAll(
          localKey, AtData()..data = 'v', AtMetaData()..ttl = 3);

      final got = await localStore.get(localKey);
      expect(got!.data, 'v');
      expect(got.metaData!.ttl, 3);
    });

    test('getKeys lists injected local keys matching the regex', () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => 'data:[]');
      await localStore.put(localKey, AtData()..data = 'v');
      await localStore.put('local:other@alice', AtData()..data = 'v');

      final keys = await (await keystore.getKeys(regex: 'x.wavi')).toList();

      expect(keys, [localKey]);
    });

    test('is a LocalRecordUpdater whose updateLocal delegates to the store',
        () async {
      expect(keystore, isA<LocalRecordUpdater>());

      final result = await (keystore as LocalRecordUpdater)
          .updateLocal(localKey, (current) => AtData()..data = 'updated');

      expect(result!.data, 'updated');
      expect((await localStore.get(localKey))!.data, 'updated');
    });

    test('a second keystore over the same store sees the first one\'s put',
        () async {
      await keystore.put(localKey, AtData()..data = 'persisted');

      final second =
          RemoteWriteThroughKeyStore(remoteSecondary, localStore: localStore);

      expect((await second.get(localKey))!.data, 'persisted');
    });
  });
}

String _jsonEncode(Map<String, dynamic> map) {
  final entries = map.entries.map((e) {
    final value = e.value is String ? '"${e.value}"' : '${e.value}';
    return '"${e.key}":$value';
  });
  return '{${entries.join(',')}}';
}
