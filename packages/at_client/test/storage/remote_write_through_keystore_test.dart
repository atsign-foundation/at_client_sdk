// Unit tests for RemoteWriteThroughKeyStore — the AtKeyValueStore that goes
// straight to the atServer via RemoteSecondary, with no local commit log,
// per D-18 item 3 ("a write-through implementation satisfies the durable-
// keystore contract"). See plans/wasm/spike/pb3-stage2b-plan.md.

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

      expect(result, isNull, reason: 'no commit log — every write returns null');
      final captured = verify(() => remoteSecondary.executeCommand(
              captureAny(), auth: true))
          .captured
          .single as String;
      expect(captured, 'update:@alice:phone@bob 12345');
    });
  });

  group('putMeta / putAll — metadata fragment is not hand-mapped and dropped', () {
    test('putMeta appends the fragment after the key', () async {
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:1');

      final meta = AtMetaData()
        ..ttl = 60000
        ..isBinary = true;
      await store.putMeta('@alice:phone@bob', meta);

      final captured = verify(() => remoteSecondary.executeCommand(
              captureAny(), auth: true))
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
      await store.putAll(
          '@alice:phone@bob', AtData()..data = '12345', meta);

      final captured = verify(() => remoteSecondary.executeCommand(
              captureAny(), auth: true))
          .captured
          .single as String;
      expect(captured, startsWith('update:ttl:60000'));
      expect(captured, contains(':@alice:phone@bob 12345'));
    });
  });

  group('remove', () {
    test('sends delete:key via executeCommand', () async {
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:1');

      await store.remove('@alice:phone@bob');

      verify(() => remoteSecondary.executeCommand(
          'delete:@alice:phone@bob', auth: true)).called(1);
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

      final captured =
          verify(() => remoteSecondary.executeVerb(captureAny()))
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
  });

  group('getKeys', () {
    test('sends a ScanVerbBuilder(regex) via executeVerb and decodes the list',
        () async {
      when(() => remoteSecondary.executeVerb(any()))
          .thenAnswer((_) async => 'data:["@alice:k1@bob","@alice:k2@bob"]');

      final keys = await (await store.getKeys(regex: '.*')).toList();

      expect(keys, ['@alice:k1@bob', '@alice:k2@bob']);
      final captured =
          verify(() => remoteSecondary.executeVerb(captureAny()))
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

  group('unsupported members', () {
    test('throw UnsupportedError', () async {
      expect(() => store.create('k', AtData()), throwsUnsupportedError);
      expect(() => store.scanKeys(KeyPattern()), throwsUnsupportedError);
      expect(
          () => store.queryByPath(
              keyPattern: KeyPattern(), predicate: const PathEquals(['data'], null)),
          throwsUnsupportedError);
      expect(() => store.snapshot(), throwsUnsupportedError);
      expect(() => store.exists('k'), throwsUnsupportedError);
      expect(() => store.getMany(['k']), throwsUnsupportedError);
      expect(() => store.removeMany(['k']), throwsUnsupportedError);
      expect(() => store.transaction((txn) async => null), throwsUnsupportedError);
      expect(() => store.stats(), throwsUnsupportedError);
      expect(() => store.getExpiredKeys(), throwsUnsupportedError);
      expect(() => store.deleteExpiredKeys(), throwsUnsupportedError);
      expect(() => store.peekExpired(), throwsUnsupportedError);
      expect(
          () => store.peekNewlyAvailable(since: DateTime(0)),
          throwsUnsupportedError);
      expect(() => store.compact(true), throwsUnsupportedError);
    });
  });

  group('dead-but-must-answer and safe defaults', () {
    test('nextExpiresAt / nextAvailableAt return null', () async {
      expect(await store.nextExpiresAt(), isNull);
      expect(await store.nextAvailableAt(), isNull);
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
}

String _jsonEncode(Map<String, dynamic> map) {
  final entries = map.entries.map((e) {
    final value = e.value is String ? '"${e.value}"' : '${e.value}';
    return '"${e.key}":$value';
  });
  return '{${entries.join(',')}}';
}
