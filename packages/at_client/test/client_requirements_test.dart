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
  /// naming its storage only when [storage], its keys only when [keys] and
  /// its transport only when [transport].
  String app(
      {required bool storage, required bool keys, bool transport = true}) {
    final s = storage ? ', storage: store' : '';
    final k = keys ? ', keys: keys' : '';
    final kio = keys ? ', atKeysIo: keys' : '';
    final t =
        transport ? ', lookUps: lookUps, secondaryAddressFinder: finder' : '';
    return '''
import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart'
    show pqNativeOnboard, selfRetrofit;

Future<void> app(AtClientPreference preference, WrittenAtKeysIo keys,
    PendingEnrollment pending, AtAuthSession session,
    AtClientStorage store, AtLookUpFactory lookUps,
    SecondaryAddressFinder finder) async {
  await Atsign('@alice').open(preference: preference$k$s$t);
  await Atsign('@alice').activate(
      cramSecret: 'x', preference: preference$k$s$t);
  await pending.client(preference$s);
  await buildAtClient(atSign: '@alice', preference: preference$kio$s$t);
  await AtClientImpl.create('@alice', null, preference$kio$s$t);
  await selfRetrofit(
      session: session,
      preference: preference,
      appName: 'a',
      deviceName: 'd',
      namespaces: const {}$s$t);
  await pqNativeOnboard(
      atSign: '@alice', cramSecret: 'x', preference: preference$kio$s$t);
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

  test(
      'the control: an app naming storage, keys and transport everywhere '
      'compiles', () async {
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

  test('Every client is given its transport', () async {
    final refused =
        await errorsIn(app(storage: true, keys: true, transport: false));

    expect(refused, hasLength(12), reason: refused.join('\n'));
    for (final name in ['lookUps', 'secondaryAddressFinder']) {
      expect(refused.where((e) => e.contains("'$name'")), hasLength(6),
          reason: 'every call that takes a transport is refused for want of '
              '$name');
    }
    expect(refused.map((e) => e.split(':').first).toSet(), hasLength(6),
        reason: 'refusals at each of the six calls that take a transport: '
            'PendingEnrollment.client takes its own from the enrollment');
  });
}
