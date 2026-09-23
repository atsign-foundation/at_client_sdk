import 'dart:io';

import 'package:at_telemetry_persistence/at_telemetry_persistence_sqlite.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 || arguments.first != '--database') {
    stderr.writeln(
      'Usage: dart run tools/initialize_at_telemetry_sqlite.dart '
      '--database <path>',
    );
    exitCode = 64;
    return;
  }

  final String databasePath = File(arguments.last).absolute.path;
  final AtTelemetrySqlitePersistence persistence =
      AtTelemetrySqlitePersistence.open(databasePath);
  await persistence.close();

  stdout.writeln('Initialized telemetry SQLite database at $databasePath');
}
