@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_client_web/src/js/bridge_surface.dart' show bridgeSurface;
import 'package:test/test.dart';

import 'exported_surface.dart';

/// Runs the generator from the package root, capturing stdout as bytes so a
/// BOM or a missing trailing newline cannot be normalised away.
ProcessResult _runManifest(Directory root) => Process.runSync(
      Platform.resolvedExecutable,
      ['tool/manifest.dart'],
      workingDirectory: root.path,
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );

void main() {
  // `dart test` runs from packages/at_client_web, where the tool and the
  // committed manifest live.
  final root = Directory.current;
  final committed = File('${root.path}/bridge-manifest.json').readAsBytesSync();

  test('The generator writes the manifest from the constants byte for byte',
      () {
    final run = _runManifest(root);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect(run.stdout as List<int>, equals(committed));
  });

  test('The surface is pinned to the public members of every @JSExport class',
      () {
    final source =
        File('${root.path}/lib/src/js/bridge.dart').readAsStringSync();
    final scanned = exportedSurface(source);
    expect(scanned.keys, isNotEmpty);
    expect(scanned, bridgeSurface,
        reason: 'a new exported member or a stale const entry fails here');
  });
}
