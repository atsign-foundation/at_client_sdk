/// Exact-value pins over the wire literals at_chops owns, ahead of the PQ
/// refactor that will relocate their definitions.
///
/// The seal family (version bytes, envelope framing, key schedules) is
/// already pinned hard — byte-exact golden envelopes in pq_hpke_test.dart,
/// and third-party IETF WG vectors in rfc9180_hpke_test.dart. What this file
/// pins is the
/// residue those leave open: values every test elsewhere asserts through the
/// very enum members and constants a refactor would rename, so a changed
/// VALUE keeps the whole suite green while changing the wire.
///
/// Everything here is FROZEN: records, verb commands and keyfiles already in
/// the world carry these values.
library;

import 'dart:convert';

import 'package:at_chops/at_chops.dart';
// HpkeSuite is package-internal; its wire identities stay pinned here.
import 'package:at_chops/src/algorithm/encryption/rfc9180_hpke.dart'
    show HpkeSuite;
import 'package:test/test.dart';

void main() {
  group('algorithm-name strings ARE the wire vocabulary', () {
    test('SigningAlgoType member names, values and order', () {
      // The member NAME is the wire literal: `pkam:signingAlgo:<name>:...`,
      // the enroll-request JSON's "signingAlgo", the signed envelope's
      // claim, and the keyfile's keyAlgorithmType all emit `.name`. No other
      // at_chops test asserts the string form, so an enum rename would pass
      // the entire suite while changing the PKAM verb.
      expect(SigningAlgoType.values.map((a) => a.name).toList(),
          ['ecc_secp256r1', 'rsa2048', 'rsa4096', 'ed25519', 'mldsa65']);
    });

    test('HashingAlgoType member names, values and order', () {
      expect(HashingAlgoType.values.map((a) => a.name).toList(),
          ['sha256', 'sha512', 'md5', 'argon2id']);
    });

    test('HashingAlgoType.fromString lowercases its input', () {
      expect(HashingAlgoType.fromString('SHA256'), HashingAlgoType.sha256);
      expect(HashingAlgoType.fromString('argon2id'), HashingAlgoType.argon2id);
    });
  });

  group('the pqSeal version-byte vocabulary', () {
    test('the default emitted version is 0x02', () {
      expect(pqSealDefaultVersion, 0x02);
    });

    test('the supported set is exactly {0x02, 0x03}', () {
      // The FULL set, not membership: NARROWING it turns records already
      // sealed under the dropped version into permanent versionMismatch
      // failures, and widening it silently changes every default computed
      // from it — with no emitting site having changed either way. 0x01 was
      // dropped deliberately; nothing published could write a durable one.
      expect(pqSealSupportedVersions, {0x02, 0x03});
    });
  });

  group('RFC 9180 suite identities', () {
    // Never emitted as wire bytes — they are key-derivation inputs, whose
    // change breaks interop invisibly. The WG-vector tests pin them
    // end-to-end; these direct pins say which constant carries which id so a
    // relocation cannot swap them.
    test('the ver-0x02 suite is KEM 0x647A, HKDF-SHA256, ChaCha20-Poly1305',
        () {
      final suite = HpkeSuite.xWingHkdfSha256ChaCha20Poly1305;
      expect(suite.kemId, 0x647A);
      expect(suite.kdfId, 0x0001);
      expect(suite.aeadId, 0x0003);
      expect(suite.suiteId,
          [0x48, 0x50, 0x4b, 0x45, 0x64, 0x7a, 0x00, 0x01, 0x00, 0x03]);
      // Nenc decides which KEM pqSeal will accept at this version, so a wrong
      // value here refuses the right KEM and admits the wrong one.
      expect(suite.nEnc, 1120);
      expect(suite.nEnc, XWingPureDartAlgo.ciphertextLength);
    });

    test('the ver-0x03 suite is KEM 0x0042, HKDF-SHA384, AES-256-GCM', () {
      final suite = HpkeSuite.mlKem1024HkdfSha384Aes256Gcm;
      expect(suite.kemId, 0x0042);
      expect(suite.kdfId, 0x0002);
      expect(suite.aeadId, 0x0002);
      expect(suite.suiteId,
          [0x48, 0x50, 0x4b, 0x45, 0x00, 0x42, 0x00, 0x02, 0x00, 0x02]);
      expect(suite.nEnc, 1568);
      expect(suite.nEnc, MlKem1024PureDartAlgo.ciphertextLength);
    });
  });

  group('KEM sizes that frame the envelope', () {
    test('X-Wing: 1120-byte ciphertext (the 0x0460 in every v1/v2 header)', () {
      expect(XWingPureDartAlgo.ciphertextLength, 1120);
      expect(XWingPureDartAlgo.publicKeyLength, 1216);
      expect(XWingPureDartAlgo.seedLength, 32);
    });

    test('ML-KEM-1024: 1568-byte ciphertext (the 0x0620 in every v3 header)',
        () {
      expect(MlKem1024PureDartAlgo.ciphertextLength, 1568);
      expect(MlKem1024PureDartAlgo.publicKeyLength, 1568);
      expect(MlKem1024PureDartAlgo.secretKeyLength, 3168);
      expect(MlKem1024PureDartAlgo.seedLength, 64,
          reason: 'the 64-byte d||z seed is the at-rest private form — never '
              'the expanded key, which no seeded call reproduces');
    });
  });

  group('the passphrase-envelope JSON keys (at rest)', () {
    test('AtEncrypted emits content, iv, hashingAlgoType — and no v, no salt',
        () {
      // Deprecated but still writing files (the CLI's passphrase-protected
      // keyfile wraps in exactly this legacy unsalted form). A renamed JSON
      // key orphans every existing encrypted keyfile; the absence of
      // 'v'/'salt' is what tells this generation from at_auth's v1 salted
      // envelope, whose reader dispatches on their presence.
      // ignore: deprecated_member_use_from_same_package
      final json = (AtEncrypted()
            ..content = 'Y3Q='
            ..iv = 'aXY='
            ..hashingAlgoType = HashingAlgoType.argon2id)
          .toJson();
      expect(jsonEncode(json),
          '{"content":"Y3Q=","iv":"aXY=","hashingAlgoType":"argon2id"}');
    });
  });
}
