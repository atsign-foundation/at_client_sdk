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
  final probe = '${Directory.current.absolute.path}/test/_client_probe.dart';

  /// An app that builds a client through every entry point that builds one,
  /// naming its storage only when [storage] and its keys only when [keys].
  String app({required bool storage, required bool keys}) {
    final s = storage ? ', storage: store' : '';
    final k = keys ? ', keys: keys' : '';
    final kio = keys ? ', atKeysIo: keys' : '';
    return '''
import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart'
    show pqNativeOnboard, selfRetrofit;

Future<void> app(AtClientPreference preference, WrittenAtKeysIo keys,
    PendingEnrollment pending, AtAuthSession session,
    AtClientStorage store) async {
  await Atsign('@alice').open(preference: preference$k$s);
  await Atsign('@alice').activate(
      cramSecret: 'x', preference: preference$k$s);
  await pending.client(preference$s);
  await buildAtClient(atSign: '@alice', preference: preference$kio$s);
  await AtClientImpl.create('@alice', null, preference$kio$s);
  await selfRetrofit(
      session: session,
      preference: preference,
      appName: 'a',
      deviceName: 'd',
      namespaces: const {}$s);
  await pqNativeOnboard(
      atSign: '@alice', cramSecret: 'x', preference: preference$kio$s);
}
''';
  }

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

  test('the control: an app naming storage and keys everywhere compiles',
      () async {
    expect(await errorsIn(app(storage: true, keys: true)), isEmpty,
        reason: 'so each refusal below is about the one argument left out');
  });

  test('Every client is given its storage', () async {
    final refused = await errorsIn(app(storage: false, keys: true));

    expect(refused, hasLength(7), reason: refused.join('\n'));
    for (final error in refused) {
      expect(error, contains("'storage'"),
          reason: 'every call that builds a client is refused for want of a '
              'storage, and for nothing else');
    }
    expect(refused.map((e) => e.split(':').first).toSet(), hasLength(7),
        reason: 'one refusal for each of the seven calls');
  });

  test('Every client is given its keys', () async {
    final refused = await errorsIn(app(storage: true, keys: false));

    expect(refused, hasLength(5), reason: refused.join('\n'));
    for (final error in refused) {
      expect(error, anyOf(contains("'keys'"), contains("'atKeysIo'")),
          reason: 'every call that takes the client\'s keys is refused for '
              'want of them, and for nothing else');
    }
    expect(refused.map((e) => e.split(':').first).toSet(), hasLength(5),
        reason: 'one refusal for each of the five calls that take keys: '
            'PendingEnrollment.client and selfRetrofit take theirs from the '
            'enrollment and the session');
  });
}
