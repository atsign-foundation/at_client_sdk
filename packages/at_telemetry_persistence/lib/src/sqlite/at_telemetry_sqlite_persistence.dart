import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

import '../at_telemetry_persistence.dart';
import '../at_telemetry_query.dart';
import '../at_telemetry_record.dart';
import 'at_telemetry_sqlite_schema.dart';

final class AtTelemetrySqlitePersistence implements AtTelemetryPersistence {
  Database? _database;

  AtTelemetrySqlitePersistence._(Database database) : _database = database;

  static bool _libraryConfigured = false;

  static AtTelemetrySqlitePersistence open(String databasePath) {
    if (databasePath.trim().isEmpty) {
      throw ArgumentError.value(
        databasePath,
        'databasePath',
        'must not be empty',
      );
    }

    _configureLibrary();
    final String parentDirectory = p.dirname(databasePath);
    if (parentDirectory.isNotEmpty && parentDirectory != '.') {
      Directory(parentDirectory).createSync(recursive: true);
    }

    return _initialize(sqlite3.open(databasePath));
  }

  static AtTelemetrySqlitePersistence inMemory() {
    _configureLibrary();
    return _initialize(sqlite3.openInMemory());
  }

  static AtTelemetrySqlitePersistence _initialize(Database database) {
    try {
      AtTelemetrySqliteSchema.apply(database);
      return AtTelemetrySqlitePersistence._(database);
    } catch (_) {
      database.dispose();
      rethrow;
    }
  }

  static void _configureLibrary() {
    if (_libraryConfigured) {
      return;
    }
    _libraryConfigured = true;

    if (!Platform.isLinux) {
      return;
    }

    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so.0');
      } on ArgumentError {
        return DynamicLibrary.open('libsqlite3.so');
      }
    });
  }

  @override
  Future<AtTelemetryRecord> store({
    required String tenantId,
    required AtTelemetryEvent event,
    DateTime? receivedAt,
  }) async {
    final List<AtTelemetryRecord> records = await storeAll(
      tenantId: tenantId,
      events: <AtTelemetryEvent>[event],
      receivedAt: receivedAt,
    );
    return records.single;
  }

  @override
  Future<List<AtTelemetryRecord>> storeAll({
    required String tenantId,
    required Iterable<AtTelemetryEvent> events,
    DateTime? receivedAt,
  }) async {
    if (tenantId.trim().isEmpty) {
      throw ArgumentError.value(tenantId, 'tenantId', 'must not be empty');
    }

    final Database database = _openDatabase;
    final DateTime receivedTimestamp = (receivedAt ?? DateTime.now()).toUtc();
    final List<_PreparedEvent> preparedEvents =
        events.map<_PreparedEvent>(_prepareEvent).toList(growable: false);
    if (preparedEvents.isEmpty) {
      return const <AtTelemetryRecord>[];
    }

    database.execute('BEGIN IMMEDIATE;');
    try {
      final List<AtTelemetryRecord> records = <AtTelemetryRecord>[];
      for (final _PreparedEvent event in preparedEvents) {
        database.execute(
          '''
INSERT INTO at_telemetry_events (
  tenant_id,
  event_name,
  event_timestamp_us,
  received_at_us,
  attributes_json
) VALUES (?, ?, ?, ?, ?);
''',
          <Object?>[
            tenantId,
            event.name,
            event.timestamp.microsecondsSinceEpoch,
            receivedTimestamp.microsecondsSinceEpoch,
            event.attributesJson,
          ],
        );
        records.add(
          AtTelemetryRecord(
            id: database.lastInsertRowId,
            tenantId: tenantId,
            event: AtTelemetryEvent(
              name: event.name,
              timestamp: event.timestamp,
              attributes: event.attributes,
            ),
            receivedAt: receivedTimestamp,
          ),
        );
      }
      database.execute('COMMIT;');
      return List<AtTelemetryRecord>.unmodifiable(records);
    } catch (_) {
      database.execute('ROLLBACK;');
      rethrow;
    }
  }

  static _PreparedEvent _prepareEvent(AtTelemetryEvent event) {
    if (event.name.trim().isEmpty) {
      throw ArgumentError.value(
        event.name,
        'event.name',
        'must not be empty',
      );
    }

    final String attributesJson = jsonEncode(event.attributes);
    return _PreparedEvent(
      name: event.name,
      timestamp: event.timestamp.toUtc(),
      attributesJson: attributesJson,
      attributes: _decodeAttributes(attributesJson),
    );
  }

  @override
  Future<List<AtTelemetryRecord>> query(AtTelemetryQuery query) async {
    final Database database = _openDatabase;
    final StringBuffer sql = StringBuffer('''
SELECT
  id,
  tenant_id,
  event_name,
  event_timestamp_us,
  received_at_us,
  attributes_json
FROM at_telemetry_events
WHERE tenant_id = ?
''');
    final List<Object?> parameters = <Object?>[query.tenantId];

    if (query.name != null) {
      sql.write('AND event_name = ?\n');
      parameters.add(query.name);
    }
    if (query.startTime != null) {
      sql.write('AND event_timestamp_us >= ?\n');
      parameters.add(query.startTime!.toUtc().microsecondsSinceEpoch);
    }
    if (query.endTime != null) {
      sql.write('AND event_timestamp_us <= ?\n');
      parameters.add(query.endTime!.toUtc().microsecondsSinceEpoch);
    }

    final String direction =
        query.order == AtTelemetryOrder.newestFirst ? 'DESC' : 'ASC';
    sql.write('ORDER BY event_timestamp_us $direction, id $direction\n');
    sql.write('LIMIT ? OFFSET ?;');
    parameters
      ..add(query.limit)
      ..add(query.offset);

    final ResultSet rows = database.select(sql.toString(), parameters);
    return rows.map(_recordFromRow).toList(growable: false);
  }

  @override
  Future<void> close() async {
    final Database? database = _database;
    if (database == null) {
      return;
    }

    _database = null;
    database.dispose();
  }

  Database get _openDatabase {
    final Database? database = _database;
    if (database == null) {
      throw StateError('AtTelemetrySqlitePersistence is closed');
    }
    return database;
  }

  static AtTelemetryRecord _recordFromRow(Row row) {
    final String attributesJson = row['attributes_json'] as String;
    return AtTelemetryRecord(
      id: row['id'] as int,
      tenantId: row['tenant_id'] as String,
      event: AtTelemetryEvent(
        name: row['event_name'] as String,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(
          row['event_timestamp_us'] as int,
          isUtc: true,
        ),
        attributes: _decodeAttributes(attributesJson),
      ),
      receivedAt: DateTime.fromMicrosecondsSinceEpoch(
        row['received_at_us'] as int,
        isUtc: true,
      ),
    );
  }

  static Map<String, Object?> _decodeAttributes(String attributesJson) {
    final Object? decoded = jsonDecode(attributesJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Telemetry attributes must be a JSON object');
    }
    return Map<String, Object?>.from(decoded);
  }
}

final class _PreparedEvent {
  final String name;
  final DateTime timestamp;
  final String attributesJson;
  final Map<String, Object?> attributes;

  const _PreparedEvent({
    required this.name,
    required this.timestamp,
    required this.attributesJson,
    required this.attributes,
  });
}
