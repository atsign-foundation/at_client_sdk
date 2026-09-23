import 'dart:convert';
import 'dart:io';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryPersistence', () {
    late AtTelemetryPersistence persistence;

    setUp(() {
      persistence = AtTelemetrySqlitePersistence.inMemory();
    });

    tearDown(() async {
      await persistence.close();
    });

    test('stores and reads a detached event snapshot', () async {
      final Map<String, Object?> attributes = <String, Object?>{
        'healthy': true,
        'load': 0.5,
        'ports': <int>[64, 128],
        'optional': null,
      };
      final DateTime eventTimestamp = DateTime.utc(2026, 2, 23, 12);
      final DateTime receivedAt = DateTime.utc(2026, 2, 23, 12, 0, 1);

      final AtTelemetryRecord stored = await persistence.store(
        tenantId: 'tenant-a',
        event: AtTelemetryEvent(
          name: 'atsign.server.heartbeat',
          timestamp: eventTimestamp,
          attributes: attributes,
        ),
        receivedAt: receivedAt,
      );
      attributes['healthy'] = false;

      final List<AtTelemetryRecord> records = await persistence.query(
        AtTelemetryQuery(tenantId: 'tenant-a'),
      );

      expect(stored.id, greaterThan(0));
      expect(stored.tenantId, 'tenant-a');
      expect(stored.event.timestamp, eventTimestamp);
      expect(stored.receivedAt, receivedAt);
      expect(records, hasLength(1));
      expect(records.single.id, stored.id);
      expect(records.single.event.name, 'atsign.server.heartbeat');
      expect(
        records.single.event.attributes,
        <String, Object?>{
          'healthy': true,
          'load': 0.5,
          'ports': <Object?>[64, 128],
          'optional': null,
        },
      );
    });

    test('stores a batch with one received timestamp', () async {
      final DateTime receivedAt = DateTime.utc(2026, 2, 23, 14);

      final List<AtTelemetryRecord> stored = await persistence.storeAll(
        tenantId: 'tenant-a',
        events: <AtTelemetryEvent>[
          _event('heartbeat', 10),
          _event('request', 11),
        ],
        receivedAt: receivedAt,
      );

      expect(stored, hasLength(2));
      expect(
        stored.map((AtTelemetryRecord record) => record.receivedAt),
        <DateTime>[receivedAt, receivedAt],
      );
      expect(
        (await persistence.query(AtTelemetryQuery(tenantId: 'tenant-a')))
            .map((AtTelemetryRecord record) => record.event.name),
        <String>['request', 'heartbeat'],
      );
    });

    test('does not partially store an invalid batch', () async {
      await expectLater(
        persistence.storeAll(
          tenantId: 'tenant-a',
          events: <AtTelemetryEvent>[
            _event('heartbeat', 10),
            AtTelemetryEvent(
              name: ' ',
              timestamp: DateTime.utc(2026, 2, 23, 11),
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        await persistence.query(AtTelemetryQuery(tenantId: 'tenant-a')),
        isEmpty,
      );
    });

    test('isolates queries by tenant', () async {
      await persistence.store(
        tenantId: 'tenant-a',
        event: _event('tenant-a-event', 10),
      );
      await persistence.store(
        tenantId: 'tenant-b',
        event: _event('tenant-b-event', 11),
      );

      final List<AtTelemetryRecord> tenantARecords = await persistence.query(
        AtTelemetryQuery(tenantId: 'tenant-a'),
      );
      final List<AtTelemetryRecord> tenantBRecords = await persistence.query(
        AtTelemetryQuery(tenantId: 'tenant-b'),
      );

      expect(
        tenantARecords.map((AtTelemetryRecord record) => record.event.name),
        <String>['tenant-a-event'],
      );
      expect(
        tenantBRecords.map((AtTelemetryRecord record) => record.event.name),
        <String>['tenant-b-event'],
      );
    });

    test('filters, orders, and paginates queries', () async {
      await persistence.store(
        tenantId: 'tenant-a',
        event: _event('heartbeat', 10),
      );
      await persistence.store(
        tenantId: 'tenant-a',
        event: _event('request', 11),
      );
      await persistence.store(
        tenantId: 'tenant-a',
        event: _event('heartbeat', 12),
      );
      await persistence.store(
        tenantId: 'tenant-a',
        event: _event('request', 13),
      );

      final List<AtTelemetryRecord> heartbeats = await persistence.query(
        AtTelemetryQuery(
          tenantId: 'tenant-a',
          name: 'heartbeat',
        ),
      );
      final List<AtTelemetryRecord> timeRange = await persistence.query(
        AtTelemetryQuery(
          tenantId: 'tenant-a',
          startTime: DateTime.utc(2026, 2, 23, 11),
          endTime: DateTime.utc(2026, 2, 23, 12),
          order: AtTelemetryOrder.oldestFirst,
        ),
      );
      final List<AtTelemetryRecord> page = await persistence.query(
        AtTelemetryQuery(
          tenantId: 'tenant-a',
          limit: 2,
          offset: 1,
        ),
      );

      expect(
        heartbeats.map(
          (AtTelemetryRecord record) => record.event.timestamp.hour,
        ),
        <int>[12, 10],
      );
      expect(
        timeRange.map(
          (AtTelemetryRecord record) => record.event.timestamp.hour,
        ),
        <int>[11, 12],
      );
      expect(
        page.map((AtTelemetryRecord record) => record.event.timestamp.hour),
        <int>[12, 11],
      );
    });

    test('rejects writes after close', () async {
      await persistence.close();

      await expectLater(
        persistence.store(
          tenantId: 'tenant-a',
          event: _event('heartbeat', 10),
        ),
        throwsStateError,
      );
      await expectLater(
        persistence.query(AtTelemetryQuery(tenantId: 'tenant-a')),
        throwsStateError,
      );
    });
  });

  group('AtTelemetryQuery', () {
    test('validates tenant, range, limit, and offset', () {
      expect(
        () => AtTelemetryQuery(tenantId: ' '),
        throwsArgumentError,
      );
      expect(
        () => AtTelemetryQuery(
          tenantId: 'tenant-a',
          startTime: DateTime.utc(2026, 2, 24),
          endTime: DateTime.utc(2026, 2, 23),
        ),
        throwsArgumentError,
      );
      expect(
        () => AtTelemetryQuery(tenantId: 'tenant-a', limit: 0),
        throwsRangeError,
      );
      expect(
        () => AtTelemetryQuery(tenantId: 'tenant-a', limit: 1001),
        throwsRangeError,
      );
      expect(
        () => AtTelemetryQuery(tenantId: 'tenant-a', offset: -1),
        throwsRangeError,
      );
    });

    test('round-trips through query parameters without the tenant', () {
      final AtTelemetryQuery query = AtTelemetryQuery(
        tenantId: 'tenant-a',
        name: 'atsign.server.heartbeat',
        startTime: DateTime.utc(2026, 2, 23),
        endTime: DateTime.utc(2026, 2, 24),
        limit: 25,
        offset: 50,
        order: AtTelemetryOrder.oldestFirst,
      );

      final Map<String, String> parameters = query.toQueryParameters();
      expect(parameters, isNot(contains('tenantId')));

      final AtTelemetryQuery decoded = AtTelemetryQuery.fromQueryParameters(
        tenantId: 'tenant-b',
        parameters: parameters,
      );
      expect(decoded.tenantId, 'tenant-b');
      expect(decoded.name, query.name);
      expect(decoded.startTime, query.startTime);
      expect(decoded.endTime, query.endTime);
      expect(decoded.limit, query.limit);
      expect(decoded.offset, query.offset);
      expect(decoded.order, query.order);
    });

    test('rejects unknown and malformed query parameters', () {
      for (final Map<String, String> parameters in <Map<String, String>>[
        <String, String>{'tenantId': 'tenant-b'},
        <String, String>{'limit': 'ten'},
        <String, String>{'start': 'yesterday'},
        <String, String>{'order': 'sideways'},
      ]) {
        expect(
          () => AtTelemetryQuery.fromQueryParameters(
            tenantId: 'tenant-a',
            parameters: parameters,
          ),
          throwsFormatException,
          reason: '$parameters',
        );
      }
    });
  });

  test('round-trips a record through JSON', () {
    final AtTelemetryRecord record = AtTelemetryRecord(
      id: 7,
      tenantId: 'tenant-a',
      event: AtTelemetryEvent(
        name: 'atsign.server.heartbeat',
        timestamp: DateTime.utc(2026, 2, 24, 12),
        attributes: const <String, Object?>{'healthy': true},
      ),
      receivedAt: DateTime.utc(2026, 2, 24, 12, 0, 1),
    );

    final AtTelemetryRecord decoded = AtTelemetryRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
    );
    expect(decoded.id, record.id);
    expect(decoded.tenantId, record.tenantId);
    expect(decoded.event.name, record.event.name);
    expect(decoded.event.timestamp, record.event.timestamp);
    expect(decoded.event.attributes, record.event.attributes);
    expect(decoded.receivedAt, record.receivedAt);
  });

  test('persists events across file database reopen', () async {
    final Directory temporaryDirectory =
        Directory.systemTemp.createTempSync('at_telemetry_persistence_');
    addTearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });
    final String databasePath =
        '${temporaryDirectory.path}/nested/telemetry.db';

    final AtTelemetrySqlitePersistence writer =
        AtTelemetrySqlitePersistence.open(databasePath);
    await writer.store(
      tenantId: 'tenant-a',
      event: _event('heartbeat', 10),
    );
    await writer.close();

    final AtTelemetrySqlitePersistence reader =
        AtTelemetrySqlitePersistence.open(databasePath);
    addTearDown(reader.close);
    final List<AtTelemetryRecord> records = await reader.query(
      AtTelemetryQuery(tenantId: 'tenant-a'),
    );

    expect(records, hasLength(1));
    expect(records.single.event.name, 'heartbeat');
  });

  test('preserves tables owned by another component', () async {
    final Directory temporaryDirectory =
        Directory.systemTemp.createTempSync('at_telemetry_persistence_');
    addTearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });
    final String databasePath = '${temporaryDirectory.path}/shared.db';

    final AtTelemetrySqlitePersistence first =
        AtTelemetrySqlitePersistence.open(databasePath);
    await first.close();

    final Database authenticationDatabase = sqlite3.open(databasePath);
    authenticationDatabase.execute('''
CREATE TABLE authentication_sessions (
  id TEXT PRIMARY KEY NOT NULL
);
''');
    authenticationDatabase.execute(
      'INSERT INTO authentication_sessions (id) VALUES (?);',
      <Object?>['session-1'],
    );
    authenticationDatabase.dispose();

    final AtTelemetrySqlitePersistence second =
        AtTelemetrySqlitePersistence.open(databasePath);
    await second.store(
      tenantId: 'tenant-a',
      event: _event('heartbeat', 10),
    );
    await second.close();

    final Database verificationDatabase = sqlite3.open(databasePath);
    final ResultSet sessions = verificationDatabase.select(
      'SELECT id FROM authentication_sessions;',
    );
    verificationDatabase.dispose();
    expect(sessions.single['id'], 'session-1');
  });

  test('rejects a database with a newer telemetry schema version', () async {
    final Directory temporaryDirectory =
        Directory.systemTemp.createTempSync('at_telemetry_persistence_');
    addTearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });
    final String databasePath = '${temporaryDirectory.path}/telemetry.db';

    final AtTelemetrySqlitePersistence persistence =
        AtTelemetrySqlitePersistence.open(databasePath);
    await persistence.close();
    final Database database = sqlite3.open(databasePath);
    database.execute(
      '''
UPDATE at_telemetry_schema_versions
SET version = 999
WHERE component = 'at_telemetry_persistence';
''',
    );
    database.dispose();

    expect(
      () => AtTelemetrySqlitePersistence.open(databasePath),
      throwsStateError,
    );
  });
}

AtTelemetryEvent _event(String name, int hour) {
  return AtTelemetryEvent(
    name: name,
    timestamp: DateTime.utc(2026, 2, 23, hour),
  );
}
