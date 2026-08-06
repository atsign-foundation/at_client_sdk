import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

void main() {
  final alice = '@alice🛠'.toAtsign();
  const rootDomain = AtRootDomain.atsignDomain;

  group('buildAtLookUp', () {
    test('builds a CRAM-only connection when there are no keys', () {
      // Activation starts before any key material exists. The connection still
      // has to be constructible — it just cannot PKAM.
      for (final signing in ApkamSigningScheme.values) {
        expect(() => buildAtLookUp(signing, alice, rootDomain, null),
            returnsNormally,
            reason: '$signing');
      }
    });

    test('carries the enrollmentId onto the connection', () {
      // at_lookup 4 takes enrollmentId at construction and exposes it read-only;
      // it is the default the pkam verb is stamped with.
      final lookUp = buildAtLookUp(ApkamSigningScheme.legacy, alice, rootDomain,
          legacyAtKeys(atsign: alice),
          enrollmentId: 'enroll-42');

      expect(lookUp.enrollmentId, 'enroll-42');
    });

    test('legacy signs with the RSA apkamPrivateKey', () {
      expect(
          () => buildAtLookUp(ApkamSigningScheme.legacy, alice, rootDomain,
              legacyAtKeys(atsign: alice)),
          returnsNormally);
    });

    test('postQuantum signs with the ML-DSA-65 material', () async {
      final pqOnly = await AtKeys.generate(alice, mintLegacy: false);
      expect(pqOnly.keysForKeyId(KeyIds.apkamPQ), isNotEmpty);

      expect(
          () => buildAtLookUp(
              ApkamSigningScheme.postQuantum, alice, rootDomain, pqOnly),
          returnsNormally);
    });

    test('a keyset without the configured scheme\'s key is rejected', () async {
      // The scheme is the caller's decision, so a keyset that cannot satisfy it
      // is an error rather than a silent fall back to the other one — falling
      // back would authenticate as an identity the caller did not ask for.
      final pqOnly = await AtKeys.generate(alice, mintLegacy: false);
      expect(
          () => buildAtLookUp(
              ApkamSigningScheme.legacy, alice, rootDomain, pqOnly),
          throwsA(isA<AtAuthenticationException>()));

      final legacyOnly = legacyAtKeys(atsign: alice);
      expect(
          () => buildAtLookUp(
              ApkamSigningScheme.postQuantum, alice, rootDomain, legacyOnly),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('a keyset with no APKAM private key at all is rejected', () {
      expect(
          () => buildAtLookUp(ApkamSigningScheme.legacy, alice, rootDomain,
              AtKeys(atsign: alice)),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('a keyset carrying both satisfies either scheme', () async {
      // AtKeys.generate mints both, which is exactly why the scheme cannot be
      // inferred from the material — both answers would be defensible.
      final both = await AtKeys.generate(alice);

      for (final signing in ApkamSigningScheme.values) {
        expect(() => buildAtLookUp(signing, alice, rootDomain, both),
            returnsNormally,
            reason: '$signing');
      }
    });
  });

  group('ApkamSigningScheme.lookUpFactory', () {
    // The fallback when a caller injects no AtLookUpFactory. Asserted here
    // rather than through authenticate(), which would need a network.
    test('applies its own scheme to the keys it is handed', () async {
      final legacyOnly = legacyAtKeys(atsign: alice);
      final pqOnly = await AtKeys.generate(alice, mintLegacy: false);

      expect(
          () => ApkamSigningScheme.legacy
              .lookUpFactory(alice, rootDomain, legacyOnly),
          returnsNormally);
      expect(
          () => ApkamSigningScheme.postQuantum
              .lookUpFactory(alice, rootDomain, pqOnly),
          returnsNormally);

      // Same rejection as buildAtLookUp — the factory is that function curried
      // with the scheme, not a laxer path to a connection.
      expect(
          () => ApkamSigningScheme.legacy
              .lookUpFactory(alice, rootDomain, pqOnly),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('passes the enrollmentId through', () {
      final lookUp = ApkamSigningScheme.legacy.lookUpFactory(
          alice, rootDomain, legacyAtKeys(atsign: alice),
          enrollmentId: 'enroll-42');

      expect(lookUp.enrollmentId, 'enroll-42');
    });
  });

  group('AtAuth.create', () {
    test('defaults to the classical scheme every atServer verifies today', () {
      expect(AtAuth.create().signing, ApkamSigningScheme.legacy);
    });

    test('takes the scheme from the caller', () {
      expect(AtAuth.create(signing: ApkamSigningScheme.postQuantum).signing,
          ApkamSigningScheme.postQuantum);
    });
  });
}
