// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:io';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';

/// What an app reaches through `package:at_client_flutter` alone.
void main() {
  test('HiveAtClientStorage comes through package:at_client_flutter, as it did '
      'in 2.0.0-rc4', () {
    final storage = HiveAtClientStorage(
      atSign: '@alice',
      storagePath: '/nowhere',
    );

    expect(
      storage,
      isA<AtClientStorage>(),
      reason:
          'an app written against 2.0.0-rc4 builds its Hive store with '
          'this package as its only import',
    );
  });

  test('the other storage backends and the mixins come through it too', () {
    expect(InMemoryAtClientStorage, isA<Type>());
    expect(SqliteAtClientStorage, isA<Type>());
    expect(EnrollmentUpdater, isA<Type>());
  });

  group('A program that imports only its platform package signs and verifies '
      'an envelope', () {
    test('package:at_client_flutter/at_client_flutter.dart', () async {
      // NOTE: a test-only keyfile: @alice's enrollment enroll-e holding one
      // ML-DSA-65 client data signing key, its private half included.
      final keys = AtKeys.fromJson(
        jsonDecode(
              File('test/data/alice_signing_keyfile.json').readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      final atClient = _SigningClient();
      when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
      when(() => atClient.enrollmentId).thenReturn('enroll-e');
      when(
        () => atClient.atKeysIo,
      ).thenReturn(InMemoryAtKeysIo.holding('@alice', keys));
      final signer = AtClientEnvelopeSigner(
        atClient,
        publicKeyCacheSettings: null,
      );
      final published = await signer.publicSigningKeyValue;
      registerFallbackValue(AtKey());
      when(
        () => atClient.get(
          any(),
          getRequestOptions: any(named: 'getRequestOptions'),
        ),
      ).thenAnswer((_) async => AtValue()..value = published);

      final SignedEnvelope envelope = await signer.wrapAndSign({'result': 1});
      final PublishedApsk apsk = await signer.fetchPublishedApsk(
        '@alice',
        'enroll-e',
      );
      final EnvelopeVerification result = await verifySignedEnvelope(
        envelope,
        signer: apsk,
        minimumAlgorithm: SigningAlgoType.mldsa65,
      );

      switch (result) {
        case EnvelopeVerified(:final KeyEntryStatus keyStatus):
          expect(keyStatus, KeyEntryStatus.active);
        case EnvelopeRefused(:final EnvelopeRefusal refusal, :final reason):
          fail('refused as ${refusal.name}: $reason');
      }
      final EnvelopeKeySelection selection = selectEnvelopeKey(
        envelope,
        signer: apsk,
      );
      expect(selection, isA<EnvelopeKeySelected>());
      final List<ApskSigningKey> listed = apsk.keys;
      expect(listed.single.alg, SigningAlgoType.mldsa65);
      final Atsign? named = envelope.signerAtSign;
      expect(named, '@alice');
      expect(
        () => SignedEnvelope.parse('{}', maxLength: 1),
        throwsA(isA<AtSigningVerificationException>()),
      );
    });
  });

  group(
    'Given what package:at_client_flutter/at_client_flutter.dart exports',
    () {
      test('when its exports are followed, then no test-support library is '
          'among them', () async {
        final exported = await _exportClosure(
          Uri.parse('package:at_client_flutter/at_client_flutter.dart'),
        );

        expect(
          exported,
          contains(
            Uri.parse(
              'package:at_client/src/signing/envelope_verification.dart',
            ),
          ),
          reason: 'the control: the walk reaches the verifier itself',
        );
        expect(
          exported.where((uri) => uri.pathSegments.last == 'testing.dart'),
          isEmpty,
        );
      });
    },
  );
}

/// Every library [library] exports, directly or through what it exports,
/// followed through the at_client packages.
Future<Set<Uri>> _exportClosure(Uri library) async {
  final resolve = _packageResolver();
  final export = RegExp(r"^\s*export\s+'([^']+)'", multiLine: true);
  final seen = <Uri>{};
  final pending = [library];
  while (pending.isNotEmpty) {
    final uri = pending.removeLast();
    if (!seen.add(uri)) continue;
    final file = resolve(uri);
    if (file == null) continue;
    for (final match in export.allMatches(
      File.fromUri(file).readAsStringSync(),
    )) {
      final target = uri.resolve(match[1]!);
      if (target.scheme == 'package' &&
          target.pathSegments.first.startsWith('at_client')) {
        pending.add(target);
      }
    }
  }
  return seen;
}

class _SigningClient extends Mock implements AtClient {}

/// Resolves a `package:` URI to its file through the nearest
/// `.dart_tool/package_config.json` above the current directory.
Uri? Function(Uri) _packageResolver() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/.dart_tool/package_config.json').existsSync()) {
    if (dir.parent.path == dir.path) {
      fail('no .dart_tool/package_config.json above ${Directory.current.path}');
    }
    dir = dir.parent;
  }
  final config = File('${dir.path}/.dart_tool/package_config.json');
  final roots = <String, Uri>{
    for (final package
        in (jsonDecode(config.readAsStringSync())
                as Map<String, dynamic>)['packages']
            as List)
      (package as Map)['name'] as String: config.uri
          .resolve('${package['rootUri']}/')
          .resolve(package['packageUri'] as String),
  };
  return (uri) {
    final root = roots[uri.pathSegments.first];
    return root?.resolve(uri.pathSegments.skip(1).join('/'));
  };
}
