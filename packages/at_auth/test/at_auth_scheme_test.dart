import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

const allAuthSchemes = [
  AtAuthScheme.legacy,
  AtAuthScheme.postQuantum,
];

void main() {
  final alice = '@alice🛠'.toAtsign();
  const rootDomain = AtRootDomain.atsignDomain;

  group('AtAuthScheme class surface', () {
    test('exposes singleton class values, not enum values', () {
      expect(AtAuthScheme.legacy, same(AtAuthScheme.legacy));
      expect(AtAuthScheme.postQuantum, same(AtAuthScheme.postQuantum));
      expect(AtAuthScheme.legacy, isNot(isA<Enum>()));
    });
  });

  group('buildAtLookUp', () {
    test('builds a CRAM-only connection when there are no keys', () {
      // Activation starts before any key material exists. The connection still
      // has to be constructible — it just cannot PKAM.
      for (final scheme in allAuthSchemes) {
        expect(() => buildAtLookUp(scheme, alice, rootDomain, null),
            returnsNormally,
            reason: scheme.signingAlgo);
      }
    });

    test('carries the enrollmentId onto the connection', () {
      // at_lookup 4 takes enrollmentId at construction and exposes it read-only;
      // it is the default the pkam verb is stamped with.
      final lookUp = buildAtLookUp(
          AtAuthScheme.legacy, alice, rootDomain, legacyAtKeys(atsign: alice),
          enrollmentId: 'enroll-42');

      expect(lookUp.enrollmentId, 'enroll-42');
    });

    test('legacy signs with the RSA apkamPrivateKey', () {
      expect(
          () => buildAtLookUp(AtAuthScheme.legacy, alice, rootDomain,
              legacyAtKeys(atsign: alice)),
          returnsNormally);
    });

    test('postQuantum signs with the ML-DSA-65 material', () async {
      final pqOnly = await AtKeys.generate(alice, mintLegacy: false);
      expect(pqOnly.keysForKeyId(KeyIds.apkamPQ), isNotEmpty);

      expect(
          () => buildAtLookUp(
              AtAuthScheme.postQuantum, alice, rootDomain, pqOnly),
          returnsNormally);
    });

    test('a keyset without the configured scheme\'s key is rejected', () async {
      // The scheme is the caller's decision, so a keyset that cannot satisfy it
      // is an error rather than a silent fall back to the other one — falling
      // back would authenticate as an identity the caller did not ask for.
      final pqOnly = await AtKeys.generate(alice, mintLegacy: false);
      expect(
          () => buildAtLookUp(AtAuthScheme.legacy, alice, rootDomain, pqOnly),
          throwsA(isA<AtAuthenticationException>()));

      final legacyOnly = legacyAtKeys(atsign: alice);
      expect(
          () => buildAtLookUp(
              AtAuthScheme.postQuantum, alice, rootDomain, legacyOnly),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('a keyset with no APKAM private key at all is rejected', () {
      expect(
          () => buildAtLookUp(
              AtAuthScheme.legacy, alice, rootDomain, AtKeys(atsign: alice)),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('a keyset carrying both satisfies either scheme', () async {
      // AtKeys.generate mints both, which is exactly why the scheme cannot be
      // inferred from the material — both answers would be defensible.
      final both = await AtKeys.generate(alice);

      for (final scheme in allAuthSchemes) {
        expect(() => buildAtLookUp(scheme, alice, rootDomain, both),
            returnsNormally,
            reason: scheme.signingAlgo);
      }
    });
  });

  group('the scheme owns derived auth behavior', () {
    test('names the algorithm it signs with', () {
      expect(AtAuthScheme.legacy.signatureAlgorithm, isA<RsaSigningAlgo>());
      expect(AtAuthScheme.postQuantum.signatureAlgorithm,
          isA<MlDsa65PureDartAlgo>());
    });

    test('the wire token is the one the keyfile and the verb both use', () {
      // The enroll verb's `signingAlgo`, at_chops's SigningAlgoType and an
      // AtKeysMaterial's keyAlgorithmType are three vocabularies that coincide.
      // If they ever diverge, an enrollment record and the key it was minted
      // from would disagree — so pin the coincidence here.
      expect(AtAuthScheme.legacy.signingAlgo, 'rsa2048');
      expect(AtAuthScheme.legacy.signingAlgo, KeyAlgorithmType.rsa2048);
      expect(AtAuthScheme.postQuantum.signingAlgo, 'mldsa65');
      expect(AtAuthScheme.postQuantum.signingAlgo, KeyAlgorithmType.mlDsa65);
    });

    test('legacy mints into the flat fields', () async {
      final keys = AtKeys(atsign: alice);
      await AtAuthScheme.legacy.mintKeys(keys);

      expect(keys.apkamPublicKey, isNotNull);
      expect(keys.apkamPrivateKey, isNotNull);
      expect(keys.keysForKeyId(KeyIds.apkamPQ), isEmpty,
          reason: 'a legacy mint has no post-quantum material to write');
    });

    test('postQuantum mints ML-DSA material under KeyIds.apkamPQ', () async {
      final keys = AtKeys(atsign: alice);
      await AtAuthScheme.postQuantum.mintKeys(keys);

      final public =
          keys.getKey(KeyIds.apkamPQ, CryptographicKeyType.publicVerification);
      final private =
          keys.getKey(KeyIds.apkamPQ, CryptographicKeyType.privateSigning);
      expect(public?.keyAlgorithmType, KeyAlgorithmType.mlDsa65);
      expect(private?.keyAlgorithmType, KeyAlgorithmType.mlDsa65);
      // ML-DSA-65 per FIPS 204.
      expect(public?.bytes, hasLength(1952));
      expect(private?.bytes, hasLength(4032));
      // A material belongs to the AtKeys' enrollment, never carrying one of its
      // own — mirroring AtKeys.generate.
      expect(keys.enrollmentId, isNull);
      expect(keys.apkamPublicKey, isNull,
          reason: 'a PQ mint must not write the legacy flat fields');
      expect(keys.apkamPrivateKey, isNull);
    });

    test('mints only the APKAM keypair, leaving the rest of the keyset alone',
        () async {
      final keys = legacyAtKeys(atsign: alice);
      final encryptionPrivateKey = keys.defaultEncryptionPrivateKey;

      await AtAuthScheme.postQuantum.mintKeys(keys);

      expect(keys.defaultEncryptionPrivateKey, encryptionPrivateKey);
    });

    test('postQuantum mints an enrollment-scoped X-Wing keypackage', () async {
      final minted = await pqAtKeys(atsign: alice);

      Set<String> shape(AtKeys keys) =>
          keys.keys.map((m) => '${m.keyId}/${m.keyPartType}').toSet();

      expect(
          shape(minted),
          containsAll({
            '${KeyIds.apkamPQ}/${CryptographicKeyType.publicVerification}',
            '${KeyIds.apkamPQ}/${CryptographicKeyType.privateSigning}',
            '${KeyIds.keyPackageXWing}/${CryptographicKeyType.publicEncryption}',
            '${KeyIds.keyPackageXWing}/${CryptographicKeyType.privateDecryption}',
          }));
      expect(minted.keysForKeyId(KeyIds.globalXWing), isEmpty);
    });

    test('reads back exactly what it minted', () async {
      // Each scheme keeps its APKAM keypair somewhere different, so "did the
      // mint land where the reader looks" is a per-scheme question.
      final legacyOnly = AtKeys(atsign: alice);
      await AtAuthScheme.legacy.mintKeys(legacyOnly);
      expect(legacyOnly.apkamPublicKey, isNotNull);
      expect(legacyOnly.apkamPrivateKey, isNotNull);

      final pqOnly = await pqAtKeys(atsign: alice);
      final pq = AtAuthScheme.postQuantum;
      expect(
          pq.requireApkamPublicKey(pqOnly).bytes,
          pqOnly
              .getKey(KeyIds.apkamPQ, CryptographicKeyType.publicVerification)!
              .bytes);
      expect(
          pq.requireApkamPrivateKey(pqOnly).bytes,
          pqOnly
              .getKey(KeyIds.apkamPQ, CryptographicKeyType.privateSigning)!
              .bytes);
    });

    test('a scheme reading the other scheme\'s keyset finds nothing', () async {
      final legacyOnly = AtKeys(atsign: alice);
      await AtAuthScheme.legacy.mintKeys(legacyOnly);
      final pqOnly = await pqAtKeys(atsign: alice);

      // Neither keyset carries the other scheme's material at all.
      expect(legacyOnly.keysForKeyId(KeyIds.apkamPQ), isEmpty);
      expect(pqOnly.apkamPublicKey, isNull);
      expect(pqOnly.apkamPrivateKey, isNull);

      // Nothing found is an error for the callers that must have the key —
      // never a silent fall back to the other scheme's.
      expect(() => AtAuthScheme.postQuantum.requireApkamPublicKey(legacyOnly),
          throwsA(isA<AtAuthenticationException>()));
      expect(() => AtAuthScheme.postQuantum.requireApkamPrivateKey(legacyOnly),
          throwsA(isA<AtAuthenticationException>()));
      // The legacy side has no accessor of its own — buildAtLookUp is where a
      // legacy scheme meeting a PQ-only keyset is rejected.
      expect(
          () => buildAtLookUp(AtAuthScheme.legacy, alice, rootDomain, pqOnly),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('the minted key is the one a connection then signs with', () async {
      // The whole point of the seam: mint and buildAtLookUp must agree on where
      // the key lives, or PQ enrollment cannot authenticate at all.
      for (final scheme in allAuthSchemes) {
        final keys = AtKeys(atsign: alice);
        await scheme.mintKeys(keys);

        expect(() => buildAtLookUp(scheme, alice, rootDomain, keys),
            returnsNormally,
            reason: scheme.signingAlgo);
      }
    });
  });

  group('AtAuthScheme.lookUpFactory', () {
    // The fallback when a caller injects no AtLookUpFactory. Asserted here
    // rather than through authenticate(), which would need a network.
    test('applies its own scheme to the keys it is handed', () async {
      final legacyOnly = legacyAtKeys(atsign: alice);
      final pqOnly = await AtKeys.generate(alice, mintLegacy: false);

      expect(
          () =>
              AtAuthScheme.legacy.lookUpFactory(alice, rootDomain, legacyOnly),
          returnsNormally);
      expect(
          () =>
              AtAuthScheme.postQuantum.lookUpFactory(alice, rootDomain, pqOnly),
          returnsNormally);

      // Same rejection as buildAtLookUp — the factory is that function curried
      // with the scheme, not a laxer path to a connection.
      expect(() => AtAuthScheme.legacy.lookUpFactory(alice, rootDomain, pqOnly),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('passes the enrollmentId through', () {
      final lookUp = AtAuthScheme.legacy.lookUpFactory(
          alice, rootDomain, legacyAtKeys(atsign: alice),
          enrollmentId: 'enroll-42');

      expect(lookUp.enrollmentId, 'enroll-42');
    });
  });

  group('AtAuth.create', () {
    test('defaults to the classical scheme every atServer verifies today', () {
      expect(AtAuth.create().scheme, AtAuthScheme.legacy);
    });

    test('takes the scheme from the caller', () {
      expect(AtAuth.create(scheme: AtAuthScheme.postQuantum).scheme,
          AtAuthScheme.postQuantum);
    });
  });
}
