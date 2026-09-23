import 'package:sqlite3/sqlite3.dart';

final class AtTelemetrySqliteSchema {
  static const int version = 1;
  static const String _component = 'at_telemetry_persistence';

  static const String _schemaVersions = '''
CREATE TABLE IF NOT EXISTS at_telemetry_schema_versions (
  component TEXT PRIMARY KEY NOT NULL,
  version   INTEGER NOT NULL CHECK (version >= 0)
) WITHOUT ROWID;
''';

  static const String _events = '''
CREATE TABLE IF NOT EXISTS at_telemetry_events (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id          TEXT NOT NULL,
  event_name         TEXT NOT NULL,
  event_timestamp_us INTEGER NOT NULL,
  received_at_us     INTEGER NOT NULL,
  attributes_json    TEXT NOT NULL,
  CHECK (length(trim(tenant_id)) > 0),
  CHECK (length(trim(event_name)) > 0)
);
''';

  static const List<String> _indexes = <String>[
    '''
CREATE INDEX IF NOT EXISTS at_telemetry_events_tenant_timestamp
ON at_telemetry_events (tenant_id, event_timestamp_us DESC, id DESC);
''',
    '''
CREATE INDEX IF NOT EXISTS at_telemetry_events_tenant_name_timestamp
ON at_telemetry_events (
  tenant_id,
  event_name,
  event_timestamp_us DESC,
  id DESC
);
''',
  ];

  static const List<String> _pragmas = <String>[
    'PRAGMA journal_mode = WAL;',
    'PRAGMA synchronous = NORMAL;',
    'PRAGMA busy_timeout = 5000;',
  ];

  static void apply(Database database) {
    for (final String pragma in _pragmas) {
      database.execute(pragma);
    }

    database.execute(_schemaVersions);
    final ResultSet versionRows = database.select(
      '''
SELECT version
FROM at_telemetry_schema_versions
WHERE component = ?;
''',
      <Object?>[_component],
    );
    final int storedVersion =
        versionRows.isEmpty ? 0 : versionRows.single['version'] as int;
    if (storedVersion > version) {
      throw StateError(
        'SQLite telemetry schema version $storedVersion is newer than '
        'supported version $version',
      );
    }

    database.execute(_events);
    for (final String index in _indexes) {
      database.execute(index);
    }

    if (storedVersion < version) {
      database.execute(
        '''
INSERT INTO at_telemetry_schema_versions (component, version)
VALUES (?, ?)
ON CONFLICT(component) DO UPDATE SET version = excluded.version;
''',
        <Object?>[_component, version],
      );
    }
  }
}
