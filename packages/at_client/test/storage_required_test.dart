import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:test/test.dart';

/// Catalogue: features/at_client/web_safe.feature
void main() {
  // NOTE: inside the package so it resolves against the package's own
  // dependencies; it exists only as an overlay, never on disk.
  final probe = '${Directory.current.absolute.path}/test/_storage_probe.dart';

  /// An app that builds a client through every entry point that builds one,
  /// each call ending in [storage].
  String app(String storage) => '''
import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart'
    show pqNativeOnboard, selfRetrofit;

Future<void> app(AtClientPreference preference, AtKeysIo keys,
    WrittenAtKeysIo written, PendingEnrollment pending, AtAuthSession session,
    AtClientStorage store) async {
  await Atsign('@alice').open(keys: keys, preference: preference$storage);
  await Atsign('@alice').activate(
      cramSecret: 'x', keys: written, preference: preference$storage);
  await pending.client(preference$storage);
  await buildAtClient(
      atSign: '@alice', preference: preference, atKeysIo: keys$storage);
  await AtClientImpl.create('@alice', null, preference,
      atKeysIo: keys$storage);
  await selfRetrofit(
      session: session,
      preference: preference,
      appName: 'a',
      deviceName: 'd',
      namespaces: const {}$storage);
  await pqNativeOnboard(
      atSign: '@alice',
      cramSecret: 'x',
      preference: preference,
      atKeysIo: keys$storage);
}
''';

  /// The compile errors in [source], as `line: message`.
  Future<List<String>> errorsIn(String source) async {
    final provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE)
      ..setOverlay(probe, content: source, modificationStamp: 0);
    final collection = AnalysisContextCollection(
        includedPaths: [probe], resourceProvider: provider);
    final result = await collection
        .contextFor(probe)
        .currentSession
        .getResolvedUnit(probe);
    if (result is! ResolvedUnitResult) fail('$probe did not resolve: $result');
    return [
      for (final d in result.diagnostics)
        if (d.severity.name == 'error')
          '${result.lineInfo.getLocation(d.offset).lineNumber}: ${d.message}'
    ];
  }

  test('Every client is given its storage', () async {
    expect(await errorsIn(app(', storage: store')), isEmpty,
        reason: 'the control: the app compiles once every call names its '
            'storage, so each refusal below is about storage alone');

    final refused = await errorsIn(app(''));

    expect(refused, hasLength(7), reason: refused.join('\n'));
    for (final error in refused) {
      expect(error, contains("'storage'"),
          reason: 'every call that builds a client is refused for want of a '
              'storage, and for nothing else');
    }
    expect(refused.map((e) => e.split(':').first).toSet(), hasLength(7),
        reason: 'one refusal for each of the seven calls');
  });
}
