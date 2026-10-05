import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  late Directory library;

  setUpAll(() async {
    final Uri? entryPoint = await Isolate.resolvePackageUri(
      Uri.parse('package:at_telemetry/at_telemetry.dart'),
    );
    if (entryPoint == null) {
      throw StateError('Unable to resolve at_telemetry');
    }
    library = File.fromUri(entryPoint).parent;
  });

  test('public entry points do not export implementation libraries', () async {
    await for (final FileSystemEntity entity in library.list()) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final String source = await entity.readAsString();
      expect(source, isNot(contains('dartastic')), reason: entity.path);
      expect(source, isNot(contains('AtTelemetryOtel')), reason: entity.path);
    }
  });

  test('OpenTelemetry dependency imports stay in the logs codec', () async {
    final String codecPath = File.fromUri(
      library.uri.resolve('src/codec/at_telemetry_logs_codec.dart'),
    ).path;
    final RegExp dependency = RegExp(
      r'''(?:import|export)\s+['"]package:(?:dartastic_opentelemetry|dartastic_opentelemetry_api|fixnum)/''',
    );
    await for (final FileSystemEntity entity in library.list(recursive: true)) {
      if (entity is! File ||
          !entity.path.endsWith('.dart') ||
          entity.path == codecPath) {
        continue;
      }
      final String source = await entity.readAsString();
      expect(dependency.hasMatch(source), isFalse, reason: entity.path);
    }
  });
}
