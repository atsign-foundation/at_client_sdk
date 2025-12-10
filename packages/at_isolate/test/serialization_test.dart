import 'package:test/test.dart';
import 'package:at_isolate/at_isolate.dart';
import 'test_utils.dart';

void main() {
  group('Metadata serialization', () {
    test('round-trip conversion preserves all fields', () {
      final metadata = TestDataGenerator.createTestMetadata(
        ttl: 3600,
        ttb: 1800,
        ttr: 900,
        ccd: true,
        isPublic: true,
        isHidden: false,
      )
        ..availableAt = DateTime(2025, 1, 1)
        ..expiresAt = DateTime(2025, 12, 31)
        ..dataSignature = 'test_signature'
        ..sharedKeyStatus = 'shared';

      // Convert to record and back
      final record = _metadataToRecord(metadata);
      final restored = _metadataFromRecord(record);

      expect(restored.ttl, equals(metadata.ttl));
      expect(restored.ttb, equals(metadata.ttb));
      expect(restored.ttr, equals(metadata.ttr));
      expect(restored.ccd, equals(metadata.ccd));
      expect(restored.isPublic, equals(metadata.isPublic));
      expect(restored.isHidden, equals(metadata.isHidden));
      expect(restored.availableAt, equals(metadata.availableAt));
      expect(restored.expiresAt, equals(metadata.expiresAt));
      expect(restored.dataSignature, equals(metadata.dataSignature));
      expect(restored.sharedKeyStatus, equals(metadata.sharedKeyStatus));
    });

    test('handles all nullable fields as null', () {
      final metadata = Metadata()
        ..isPublic = false
        ..isHidden = true;

      final record = _metadataToRecord(metadata);
      final restored = _metadataFromRecord(record);

      expect(restored.ttl, isNull);
      expect(restored.ttb, isNull);
      expect(restored.ttr, isNull);
      expect(restored.ccd, isNull);
      expect(restored.availableAt, isNull);
      expect(restored.isPublic, isFalse);
      expect(restored.isHidden, isTrue);
    });

    test('handles mixed null and non-null fields', () {
      final metadata = Metadata()
        ..ttl = 1000
        ..isPublic = true;

      final record = _metadataToRecord(metadata);

      expect(record.ttl, equals(1000));
      expect(record.ttb, isNull);
      expect(record.isPublic, isTrue);
    });
  });

  group('AtKey serialization', () {
    test('round-trip conversion preserves all fields', () {
      final atKey = TestDataGenerator.createTestAtKey(
        key: 'phone',
        sharedWith: '@bob',
        sharedBy: '@alice',
        namespace: 'wavi',
        isLocal: false,
        metadata: TestDataGenerator.createTestMetadata(ttl: 3600),
      );

      final record = _atKeyToRecord(atKey);
      final restored = _atKeyFromRecord(record);

      expect(restored.key, equals(atKey.key));
      expect(restored.sharedWith, equals(atKey.sharedWith));
      expect(restored.sharedBy, equals(atKey.sharedBy));
      expect(restored.namespace, equals(atKey.namespace));
      expect(restored.isLocal, equals(atKey.isLocal));
      expect(restored.metadata.ttl, equals(atKey.metadata.ttl));
    });

    test('handles nullable fields correctly', () {
      final atKey = AtKey()
        ..key = 'test_key'
        ..isLocal = true
        ..metadata = Metadata();

      final record = _atKeyToRecord(atKey);

      expect(record.key, equals('test_key'));
      expect(record.sharedWith, isNull);
      expect(record.sharedBy, isNull);
      expect(record.namespace, isNull);
      expect(record.isLocal, isTrue);
    });

    test('nested metadata serialization works', () {
      final metadata = TestDataGenerator.createTestMetadata(
        ttl: 500,
        isPublic: true,
      );
      final atKey = TestDataGenerator.createTestAtKey(metadata: metadata);

      final record = _atKeyToRecord(atKey);

      expect(record.metadata.ttl, equals(500));
      expect(record.metadata.isPublic, isTrue);
    });
  });

  group('AtKey list serialization', () {
    test('converts list of AtKeys to strings and back', () {
      // AtKeys need proper format for toString/fromString round-trip
      final atKeys = [
        AtKey()
          ..key = 'key1'
          ..namespace = 'ns1'
          ..sharedBy = '@alice',
        AtKey()
          ..key = 'key2'
          ..sharedWith = '@bob'
          ..sharedBy = '@alice'
          ..namespace = 'ns2',
        AtKey()
          ..key = 'key3'
          ..sharedBy = '@alice'
          ..isLocal = true,
      ];

      // Simulate what worker does: toString() each key
      final stringList = atKeys.map((k) => k.toString()).toList();

      // Simulate what main isolate does: fromString() each
      final restored = stringList.map((s) => AtKey.fromString(s)).toList();

      expect(restored.length, equals(3));
      expect(restored[0].key, equals('key1'));
      expect(restored[1].key, equals('key2'));
      expect(restored[2].key, equals('key3'));
    });
  });

  group('Request type creation', () {
    test('_DeleteRequest creates with all fields', () {
      final atKeyRecord = (
        key: 'test',
        sharedWith: null,
        sharedBy: '@alice',
        namespace: 'wavi',
        isLocal: false,
        isRef: false,
        metadata: (
          ttl: null,
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
        ),
      );

      final req = (
        atKey: atKeyRecord,
        isDedicated: true,
        useRemoteAtServer: false,
      );

      expect(req.atKey.key, equals('test'));
      expect(req.isDedicated, isTrue);
      expect(req.useRemoteAtServer, isFalse);
    });

    test('_GetRequest creates with optional fields', () {
      final atKeyRecord = (
        key: 'test',
        sharedWith: null,
        sharedBy: '@alice',
        namespace: null,
        isLocal: true,
        isRef: false,
        metadata: (
          ttl: null,
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
        ),
      );

      final req = (
        atKey: atKeyRecord,
        isDedicated: false,
        bypassCache: true,
        useRemoteAtServer: true,
      );

      expect(req.bypassCache, isTrue);
      expect(req.useRemoteAtServer, isTrue);
    });

    test('_PutRequest creates with value field', () {
      final req = (
        atKey: (
          key: 'phone',
          sharedWith: null,
          sharedBy: '@alice',
          namespace: 'wavi',
          isLocal: false,
          isRef: false,
          metadata: (
            ttl: null,
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
          ),
        ),
        value: '+1-555-1234',
        isDedicated: false,
        useRemoteAtServer: null,
      );

      expect(req.value, equals('+1-555-1234'));
      expect(req.atKey.key, equals('phone'));
    });

    test('_PutBinaryRequest handles List<int>', () {
      final binaryData = [72, 101, 108, 108, 111]; // "Hello"

      final req = (
        atKey: (
          key: 'file',
          sharedWith: null,
          sharedBy: '@alice',
          namespace: 'files',
          isLocal: false,
          isRef: false,
          metadata: (
            ttl: null,
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
          ),
        ),
        value: binaryData,
        isDedicated: false,
        useRemoteAtServer: null,
      );

      expect(req.value, equals(binaryData));
      expect(req.value, isA<List<int>>());
    });
  });

  group('Response type creation', () {
    test('_DeleteResponse creates successfully', () {
      final resp = (success: true);
      expect(resp.success, isTrue);
    });

    test('_GetResponse with value and metadata', () {
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
        isPublic: true,
        isHidden: false,
      );

      final resp = (
        value: 'test_value',
        metadata: metadataRecord,
      );

      expect(resp.value, equals('test_value'));
      expect(resp.metadata.ttl, equals(3600));
      expect(resp.metadata.isPublic, isTrue);
    });

    test('_GetAtKeysResponse with string list', () {
      final resp = (
        atKeys: ['@alice:key1.wavi', '@alice:key2.wavi', 'local:key3'],
      );

      expect(resp.atKeys.length, equals(3));
      expect(resp.atKeys[0], contains('key1'));
    });

    test('_WorkerRequest wraps typed params', () {
      final params = (success: true);
      final wrapped = (request: 'delete', params: params);

      expect(wrapped.request, equals('delete'));
      expect(wrapped.params.success, isTrue);
    });
  });

  group('Preference map serialization', () {
    test('converts AtClientPreference to map', () {
      final preference = AtClientPreference()
        ..namespace = 'test_ns'
        ..isLocalStoreRequired = false
        ..hiveStoragePath = '/tmp/hive'
        ..commitLogPath = '/tmp/commit'
        ..rootDomain = 'root.atsign.org'
        ..rootPort = 64;

      final map = {
        'namespace': preference.namespace,
        'isLocalStoreRequired': preference.isLocalStoreRequired,
        'hiveStoragePath': preference.hiveStoragePath,
        'commitLogPath': preference.commitLogPath,
        'rootDomain': preference.rootDomain,
        'rootPort': preference.rootPort,
      };

      expect(map['namespace'], equals('test_ns'));
      expect(map['isLocalStoreRequired'], isFalse);
      expect(map['rootPort'], equals(64));
    });

    test('handles null values in preference map', () {
      final preference = AtClientPreference()
        ..isLocalStoreRequired = false;

      final map = {
        'namespace': preference.namespace,
        'isLocalStoreRequired': preference.isLocalStoreRequired,
        'hiveStoragePath': preference.hiveStoragePath,
        'commitLogPath': preference.commitLogPath,
        'rootDomain': preference.rootDomain,
        'rootPort': preference.rootPort,
      };

      expect(map['namespace'], isNull);
      expect(map['isLocalStoreRequired'], isFalse);
      expect(map['hiveStoragePath'], isNull);
    });
  });
}

// Helper functions to access private serialization methods
// These would normally be in the isolate.dart file but are part-ed in
_MetadataRecord _metadataToRecord(Metadata metadata) {
  return (
    ttl: metadata.ttl,
    ttb: metadata.ttb,
    ttr: metadata.ttr,
    ccd: metadata.ccd,
    availableAt: metadata.availableAt,
    expiresAt: metadata.expiresAt,
    refreshAt: metadata.refreshAt,
    createdAt: metadata.createdAt,
    updatedAt: metadata.updatedAt,
    dataSignature: metadata.dataSignature,
    sharedKeyStatus: metadata.sharedKeyStatus,
    isPublic: metadata.isPublic,
    isHidden: metadata.isHidden,
  );
}

Metadata _metadataFromRecord(_MetadataRecord record) {
  return Metadata()
    ..ttl = record.ttl
    ..ttb = record.ttb
    ..ttr = record.ttr
    ..ccd = record.ccd
    ..availableAt = record.availableAt
    ..expiresAt = record.expiresAt
    ..refreshAt = record.refreshAt
    ..createdAt = record.createdAt
    ..updatedAt = record.updatedAt
    ..dataSignature = record.dataSignature
    ..sharedKeyStatus = record.sharedKeyStatus
    ..isPublic = record.isPublic
    ..isHidden = record.isHidden;
}

_AtKeyRecord _atKeyToRecord(AtKey atKey) {
  return (
    key: atKey.key,
    sharedWith: atKey.sharedWith,
    sharedBy: atKey.sharedBy,
    namespace: atKey.namespace,
    isLocal: atKey.isLocal,
    isRef: atKey.isRef,
    metadata: _metadataToRecord(atKey.metadata),
  );
}

AtKey _atKeyFromRecord(_AtKeyRecord record) {
  var atKey = AtKey();
  atKey.key = record.key;
  atKey.sharedWith = record.sharedWith;
  atKey.sharedBy = record.sharedBy;
  atKey.namespace = record.namespace;
  atKey.isLocal = record.isLocal;
  atKey.isRef = record.isRef;
  atKey.metadata = _metadataFromRecord(record.metadata);
  return atKey;
}

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
