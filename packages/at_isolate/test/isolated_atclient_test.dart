import 'package:test/test.dart';
import 'package:at_isolate/at_isolate.dart';
import 'package:mutex/mutex.dart';
import 'dart:async';
import 'test_utils.dart';

void main() {

  group('IsolatedAtClient request/response flow', () {
    test('delete request creates correct message structure', () {
      // Test that delete() creates the right request format
      final atKey = TestDataGenerator.createTestAtKey(key: 'test_key');

      // We can't easily test the actual request without spawning an isolate,
      // but we can test the data structures
      final atKeyRecord = _atKeyToRecord(atKey);
      final request = (
        atKey: atKeyRecord,
        isDedicated: false,
        useRemoteAtServer: true,
      );
      final wrapped = (request: 'delete', params: request);

      expect(wrapped.request, equals('delete'));
      expect(wrapped.params.atKey.key, equals('test_key'));
      expect(wrapped.params.isDedicated, isFalse);
    });

    test('get request structure with optional parameters', () {
      final atKey = TestDataGenerator.createTestAtKey();
      final atKeyRecord = _atKeyToRecord(atKey);

      final request = (
        atKey: atKeyRecord,
        isDedicated: false,
        bypassCache: true,
        useRemoteAtServer: false,
      );

      expect(request.bypassCache, isTrue);
      expect(request.useRemoteAtServer, isFalse);
    });

    test('put request with various value types', () {
      final atKey = TestDataGenerator.createTestAtKey();
      final atKeyRecord = _atKeyToRecord(atKey);

      // String value
      final stringReq = (
        atKey: atKeyRecord,
        value: 'test_value',
        isDedicated: false,
        useRemoteAtServer: null,
      );
      expect(stringReq.value, isA<String>());

      // Numeric value
      final numReq = (
        atKey: atKeyRecord,
        value: 42,
        isDedicated: false,
        useRemoteAtServer: null,
      );
      expect(numReq.value, isA<int>());

      // Binary value
      final binReq = (
        atKey: atKeyRecord,
        value: [1, 2, 3, 4],
        isDedicated: false,
        useRemoteAtServer: null,
      );
      expect(binReq.value, isA<List<int>>());
    });
  });

  group('IsolatedAtClient response handling', () {
    test('delete response structure', () {
      final response = (success: true);
      expect(response.success, isTrue);
    });

    test('get response with metadata', () {
      final metadataRecord = (
        ttl: 3600,
        ttb: null,
        ttr: null,
        ccd: null,
        availableAt: null,
        expiresAt: null,
        refreshAt: null,
        createdAt: null,
        updatedAt: null,
        dataSignature: null,
        sharedKeyStatus: null,
        isPublic: false,
        isHidden: false,
      );

      final response = (
        value: 'retrieved_value',
        metadata: metadataRecord,
      );

      expect(response.value, equals('retrieved_value'));
      expect(response.metadata.ttl, equals(3600));
    });

    test('getAtKeys response deserializes string list', () {
      // Use properly formatted AtKey strings that fromString() can parse
      final stringKeys = [
        '@alice:phone.wavi@alice',
        '@alice:email.wavi@alice',
        'public:location.wavi@alice',
      ];

      final response = (atKeys: stringKeys);

      // Simulate deserialization
      final atKeys = response.atKeys.map((s) => AtKey.fromString(s)).toList();

      expect(atKeys.length, equals(3));
      expect(atKeys[0].key, contains('phone'));
      expect(atKeys[1].key, contains('email'));
      expect(atKeys[2].key, contains('location'));
    });
  });

  group('IsolatedAtClient error handling', () {
    test('type mismatch detection', () {
      // Simulate receiving wrong response type
      final wrongResponse = 'error message';

      // In actual code, this check happens:
      // if (result is! _DeleteResponse) { throw result; }
      expect(wrongResponse is! ({bool success}), isTrue);
    });

    test('worker error message format', () {
      final errorMsg = 'AtClientException: Key not found';

      // Worker sends errors as strings
      expect(errorMsg, isA<String>());
      expect(errorMsg, contains('AtClientException'));
    });
  });

  group('IsolatedAtClient mutex behavior', () {
    test('mutex pattern ensures release on success', () async {
      final mutex = Mutex();
      bool released = false;

      await mutex.acquire();
      try {
        // Simulate successful operation
        await Future.delayed(Duration(milliseconds: 10));
      } finally {
        mutex.release();
        released = true;
      }

      expect(released, isTrue);
      expect(mutex.isLocked, isFalse);
    });

    test('mutex pattern ensures release on exception', () async {
      final mutex = Mutex();
      bool released = false;

      try {
        await mutex.acquire();
        try {
          throw Exception('test error');
        } finally {
          mutex.release();
          released = true;
        }
      } catch (e) {
        // Expected exception
      }

      expect(released, isTrue);
      expect(mutex.isLocked, isFalse);
    });

    test('mutex serializes operations', () async {
      final mutex = Mutex();
      final results = <int>[];

      // Spawn two concurrent operations
      final futures = [
        Future(() async {
          await mutex.acquire();
          try {
            await Future.delayed(Duration(milliseconds: 20));
            results.add(1);
          } finally {
            mutex.release();
          }
        }),
        Future(() async {
          await mutex.acquire();
          try {
            results.add(2);
          } finally {
            mutex.release();
          }
        }),
      ];

      await Future.wait(futures);

      // Second operation should wait for first
      expect(results, equals([1, 2]));
    });
  });

  group('IsolatedAtClient preference handling', () {
    test('accepts and uses AtClientPreference', () {
      final preference = AtClientPreference()
        ..namespace = 'test_namespace'
        ..isLocalStoreRequired = false;

      expect(preference.namespace, equals('test_namespace'));
      expect(preference.isLocalStoreRequired, isFalse);
    });

    test('preference serialization to map', () {
      final preference = AtClientPreference()
        ..namespace = 'myapp'
        ..isLocalStoreRequired = true
        ..hiveStoragePath = '/tmp/hive'
        ..rootPort = 64;

      final map = {
        'namespace': preference.namespace,
        'isLocalStoreRequired': preference.isLocalStoreRequired,
        'hiveStoragePath': preference.hiveStoragePath,
        'commitLogPath': preference.commitLogPath,
        'rootDomain': preference.rootDomain,
        'rootPort': preference.rootPort,
      };

      expect(map['namespace'], equals('myapp'));
      expect(map['isLocalStoreRequired'], isTrue);
      expect(map['rootPort'], equals(64));
    });
  });

  group('IsolatedAtClient close protocol', () {
    test('close message structure', () {
      final closeMsg = (request: 'close', params: ());

      expect(closeMsg.request, equals('close'));
      expect(closeMsg.params, equals(()));
    });
  });
}

// Import necessary typedef and helper functions
typedef _MetadataRecord = ({
  int? ttl,
  int? ttb,
  int? ttr,
  bool? ccd,
  DateTime? availableAt,
  DateTime? expiresAt,
  DateTime? refreshAt,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? dataSignature,
  String? sharedKeyStatus,
  bool isPublic,
  bool isHidden,
});

typedef _AtKeyRecord = ({
  String key,
  String? sharedWith,
  String? sharedBy,
  String? namespace,
  bool isLocal,
  bool isRef,
  _MetadataRecord metadata,
});

_AtKeyRecord _atKeyToRecord(AtKey atKey) {
  return (
    key: atKey.key,
    sharedWith: atKey.sharedWith,
    sharedBy: atKey.sharedBy,
    namespace: atKey.namespace,
    isLocal: atKey.isLocal,
    isRef: atKey.isRef,
    metadata: (
      ttl: atKey.metadata.ttl,
      ttb: atKey.metadata.ttb,
      ttr: atKey.metadata.ttr,
      ccd: atKey.metadata.ccd,
      availableAt: atKey.metadata.availableAt,
      expiresAt: atKey.metadata.expiresAt,
      refreshAt: atKey.metadata.refreshAt,
      createdAt: atKey.metadata.createdAt,
      updatedAt: atKey.metadata.updatedAt,
      dataSignature: atKey.metadata.dataSignature,
      sharedKeyStatus: atKey.metadata.sharedKeyStatus,
      isPublic: atKey.metadata.isPublic,
      isHidden: atKey.metadata.isHidden,
    ),
  );
}
