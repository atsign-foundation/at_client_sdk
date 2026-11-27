@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_client_web/src/exceptions.dart' show maxErrorMessageLength;
import 'package:at_client_web/src/js/bridge_surface.dart'
    show bridgeSurface, createOptions, envelopes, statuses;
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
  final bridge = File('${root.path}/lib/src/js/bridge.dart').readAsStringSync();
  final session = File('${root.path}/lib/src/session/at_client_session.dart')
      .readAsStringSync();

  late final Map<String, dynamic> generated;

  setUpAll(() {
    final run = _runManifest(root);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    generated = jsonDecode(utf8.decode(run.stdout as List<int>))
        as Map<String, dynamic>;
  });

  test('The generator writes the manifest from the constants byte for byte',
      () {
    final run = _runManifest(root);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect(run.stdout as List<int>, equals(committed));
  });

  test('The surface is pinned to the public members of every @JSExport class',
      () {
    final scanned = exportedSurface(bridge);
    expect(scanned.keys, isNotEmpty);
    expect(scanned, bridgeSurface,
        reason: 'a new exported member or a stale const entry fails here');
  });

  test('the manifest lists the create options each session form reads', () {
    final read = createOptionNames(bridge);
    expect(({...read.common, ...read.passkey}.toList()..sort()),
        equals(createOptions['passkey']));
    expect(({...read.common, ...read.keys}.toList()..sort()),
        equals(createOptions['keys']));
  });

  test('the manifest lists the subscribe envelope fields', () {
    expect(subscribeEnvelopeFields(bridge), equals(envelopes['subscribe']));
    expect(envelopes.keys, equals(['subscribe']),
        reason: 'a new envelope needs its own entry and a schema bump');
  });

  test('the manifest lists every connection status', () {
    expect(statusNames(session), equals(statuses));
  });

  test('the manifest bounds match the bridge constants', () {
    expect(generated['bounds'],
        equals({'maxErrorMessageLength': maxErrorMessageLength}));
  });

  test('the manifest schema version is 2', () {
    expect(generated['schemaVersion'], 2);
  });
}
