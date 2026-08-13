import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

/// Collecting the `apkamSymmetricKey` an approver sealed to a new enrollment.
///
/// Every rejection on this path has to be a **skip**: an atSign's clients may
/// have several envelopes in flight at once, and one this enrollment cannot use
/// says nothing about the one it is waiting for. The case that matters most is
/// an envelope from an enrollment that has since been revoked — the atServer
/// moves a revoked enrollment's `_apsk` out from under its address, which is
/// exactly the signal this path is supposed to read as "not from an approved
/// enrollment, skip it".
void main() {
  const atSign = '@alice';
  const kpid = 'kpid-1';

  /// Files a key package — **both** halves under one keyId, which is what
  /// `enrollmentKeyPackageBuilder` produces and what identifies a package as
  /// distinct from an nskey private, which is filed under the same part type
  /// but arrives alone.
  void fileKeyPackage(
    AtKeys keys, {
    required String keyId,
    String? enrollmentId,
    int seed = 0,
    DateTime? createdAt,
  }) {
    final at = createdAt ?? DateTime.now().toUtc();
    keys
      ..addKey(AtKeysMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicKeyType.privateDecapsulation,
        keyAlgorithmType: KeyAlgorithmType.xWing,
        bytes: AtBytes(
            Uint8List.fromList(List<int>.generate(32, (i) => i + seed))),
        createdAt: at,
      ))
      ..addKey(AtKeysMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicKeyType.publicEncapsulation,
        keyAlgorithmType: KeyAlgorithmType.xWing,
        bytes: AtBytes(
            Uint8List.fromList(List<int>.generate(32, (i) => i + seed + 100))),
        createdAt: at,
      ));
  }

  /// AtKeys holding a key-package, which is what the resolver needs to
  /// identify this enrollment's kpid at all.
  AtKeys withKeyPackage() {
    final keys = AtKeys();
    fileKeyPackage(keys, keyId: kpid);
    return keys;
  }

  const envelopeKey = '@alice:abc.$kpid.__ssenv.myapp@alice';

  /// An lookup that finds one envelope addressed to this kpid, signed by
  /// [signer], and answers the `_apsk` lookup for that signer with [apsk] —
  /// or throws the atServer's AT0015 when [apsk] is null, which is what a
  /// **revoked** signer's key lookup actually returns.
  MockAtLookUp lookupWith({required String signer, String? apsk}) {
    final lookUp = MockAtLookUp();
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((inv) async {
      final command = inv.positionalArguments[0] as String;
      if (command.startsWith('scan')) {
        return 'data:${jsonEncode([envelopeKey])}';
      }
      if (command.contains('_apsk.$signer')) {
        if (apsk == null) {
          throw AtLookUpException(
              'AT0015',
              'key not found : public:_apsk.$signer.a.__e$atSign does not '
                  'exist in keystore');
        }
        return 'data:$apsk';
      }
      if (command.contains(envelopeKey)) {
        return 'data:${jsonEncode({
              'enrollmentId': signer,
              'signature': 'not-checked-because-the-apsk-lookup-decides-first',
              'signingAlgo': 'rsa2048',
              'hashingAlgo': 'sha256',
              'payload': {'toKpid': kpid},
            })}';
      }
      return null;
    });
    return lookUp;
  }

  String b64u(String text) =>
      base64Url.encode(utf8.encode(text)).replaceAll('=', '');

  /// The JWS wrapper form of [lookupWith]'s envelope: the signer claim lives
  /// in the protected header's `kid`, so the resolver must read it from there
  /// to know which `_apsk` to look up at all.
  MockAtLookUp lookupWithJws({required String signer}) {
    final lookUp = MockAtLookUp();
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((inv) async {
      final command = inv.positionalArguments[0] as String;
      if (command.startsWith('scan')) {
        return 'data:${jsonEncode([envelopeKey])}';
      }
      if (command.contains('_apsk.$signer')) {
        throw AtLookUpException(
            'AT0015',
            'key not found : public:_apsk.$signer.a.__e$atSign does not '
                'exist in keystore');
      }
      if (command.contains(envelopeKey)) {
        return 'data:${jsonEncode({
              'v': 2,
              'payload': b64u('{"toKpid":"$kpid"}'),
              'protected': b64u('{"alg":"RS256","kid":"$signer","v":2}'),
              'signature': 'unchecked-the-apsk-lookup-decides-first',
            })}';
      }
      return null;
    });
    return lookUp;
  }

  setUpAll(() => registerFallbackValue(''));

  test('an envelope whose signer has no _apsk is skipped, not fatal', () async {
    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 50));

    // The atServer answers the `_apsk` lookup with an AT0015 ERROR, which
    // AtLookupImpl throws rather than returning null. Left uncaught it escapes
    // the skip and takes the whole enrollment down — so what must come out is
    // the resolver's own "nothing arrived" timeout, never the lookup's error.
    await expectLater(
        resolve(withKeyPackage(), lookupWith(signer: 'revoked-enrollment')),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('No conveyed apkamSymmetricKey arrived'))),
        reason: 'a revoked signer is precisely the case this path documents '
            'as its intended outcome — its key is gone, so the envelope is '
            'not from an approved enrollment and is skipped. Propagating the '
            'lookup error instead means one stale envelope from a revoked '
            'enrollment fails every later enrollment that walks past it');
  });

  test('a JWS envelope from a revoked signer is skipped the same way',
      () async {
    // Same outcome as the version-1 arm above, reached through the version-2
    // claim path: the signer is named only by the protected header's kid, and
    // the resolver must route the _apsk lookup from it before anything else
    // can happen.
    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 50));

    await expectLater(
        resolve(withKeyPackage(), lookupWithJws(signer: 'revoked-enrollment')),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('No conveyed apkamSymmetricKey arrived'))));
  });

  test('and a signer whose _apsk does not verify is skipped too', () async {
    // The control arm for the shape: a present-but-wrong `_apsk` already
    // reached the skip before this fix, and must still. Without it, the test
    // above would also pass on code that skipped EVERY envelope.
    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 50));

    await expectLater(
        resolve(withKeyPackage(),
            lookupWith(signer: 'live-enrollment', apsk: 'not-a-real-key')),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('No conveyed apkamSymmetricKey arrived'))));
  });

  test('AtKeys with no key package cannot be resolved at all', () async {
    final resolve = enrollmentApkamSymmetricKeyResolver(atSign);

    await expectLater(
        resolve(AtKeys(), lookupWith(signer: 'anyone')),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('no key-establishment decapsulation private key'))),
        reason: 'nothing sealed to this enrollment could be opened, and '
            'polling for half a minute to say so helps nobody. The message '
            'names no single KEM because the lookup accepts any this build '
            'implements — an enrollment minted under either is openable here');
  });

  test('a co-tenant enrollment\'s key package is never adopted', () async {
    // A retrofitted keyfile carries the legacy enrollment's package beside
    // this one's. Taking the wrong one means polling an address nobody is
    // writing to until the enrollment times out — and the failure names the
    // co-tenant's kpid, which points the reader at the wrong enrollment.
    final keys = AtKeys();
    fileKeyPackage(keys,
        keyId: 'co-tenant-kpid',
        enrollmentId: 'someone-elses-enrollment',
        seed: 50);
    fileKeyPackage(keys, keyId: kpid);

    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: Duration(milliseconds: 1),
        pollInterval: Duration(milliseconds: 1));

    await expectLater(
        resolve(keys, lookupWith(signer: 'live-enrollment', apsk: 'whatever')),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            allOf(contains(kpid), isNot(contains('co-tenant-kpid'))))),
        reason: 'the untagged package is this enrollment\'s; one tagged for '
            'another enrollment is never a candidate');
  });

  test('an nskey private is not mistaken for a key package', () async {
    // Same part type, but filed alone — its public half lives on the
    // atServer. Adopting it as the recipient identity would make this
    // enrollment answer at an address it never advertised.
    final keys = AtKeys()
      ..addKey(AtKeysMaterial(
        keyId: 'nskey-private',
        keyPartType: CryptographicKeyType.privateDecapsulation,
        keyAlgorithmType: KeyAlgorithmType.xWing,
        bytes: AtBytes(Uint8List.fromList(List<int>.generate(32, (i) => i))),
        createdAt: DateTime.now().toUtc(),
      ));

    final resolve = enrollmentApkamSymmetricKeyResolver(atSign);

    await expectLater(
        resolve(keys, lookupWith(signer: 'anyone')),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('no key-establishment decapsulation private key'))));
  });
}
