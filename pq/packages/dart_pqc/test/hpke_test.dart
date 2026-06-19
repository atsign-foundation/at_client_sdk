import 'dart:typed_data';

import 'package:dart_pqc/dart_pqc.dart';
import 'package:test/test.dart';

/// HPKE-base-over-X-Wing primitive tests.
///
/// These exercise [pqSeal]/[pqOpen]/[pqDeriveConfirmationTag] using the
/// pure-Dart X-Wing implementation, so they run on any runner with no
/// libcrypto (ML-DSA is never touched here).
void main() {
  final XWingAlgorithm xwing = XWingPureDart.instance;

  Future<PqcKeyPair> freshKey() => xwing.generateKeyPair();

  group('pqSeal / pqOpen round-trip', () {
    test('empty, small, 1KB and binary plaintexts round-trip', () async {
      final kp = await freshKey();
      final cases = <Uint8List>[
        Uint8List(0),
        Uint8List.fromList('hello'.codeUnits),
        Uint8List.fromList(List<int>.generate(1024, (i) => i & 0xff)),
        Uint8List.fromList([0, 255, 0, 128, 7, 7, 7]),
      ];
      for (final pt in cases) {
        final env = await pqSeal(kp.publicKey, pt);
        final out = await pqOpen(kp.secretKey, env);
        expect(out, equals(pt));
      }
    });

    test('round-trips with matching info + aad', () async {
      final kp = await freshKey();
      final info = Uint8List.fromList('recipient-key-id'.codeUnits);
      final aad = Uint8List.fromList('sender@:purpose'.codeUnits);
      final pt = Uint8List.fromList('secret payload'.codeUnits);
      final env = await pqSeal(kp.publicKey, pt, info: info, aad: aad);
      final out = await pqOpen(kp.secretKey, env, info: info, aad: aad);
      expect(out, equals(pt));
    });
  });

  group('pqOpen rejects', () {
    final pt = Uint8List.fromList('top secret'.codeUnits);

    test('aad mismatch → authFailure', () async {
      final kp = await freshKey();
      final env = await pqSeal(kp.publicKey, pt,
          aad: Uint8List.fromList('A'.codeUnits));
      await expectLater(
        pqOpen(kp.secretKey, env, aad: Uint8List.fromList('B'.codeUnits)),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('info mismatch → authFailure (different key derived)', () async {
      final kp = await freshKey();
      final env = await pqSeal(kp.publicKey, pt,
          info: Uint8List.fromList('ctx-1'.codeUnits));
      await expectLater(
        pqOpen(kp.secretKey, env, info: Uint8List.fromList('ctx-2'.codeUnits)),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('tampered KEM ciphertext → authFailure', () async {
      final kp = await freshKey();
      final env = await pqSeal(kp.publicKey, pt);
      env[10] ^= 0xff; // flip a byte inside the KEM ciphertext region
      await expectLater(
        pqOpen(kp.secretKey, env),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('tampered GCM tail → authFailure', () async {
      final kp = await freshKey();
      final env = await pqSeal(kp.publicKey, pt);
      env[env.length - 1] ^= 0xff; // flip a byte in the GCM tag
      await expectLater(
        pqOpen(kp.secretKey, env),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('cross-key (seal to A, open with B) → authFailure, no crash',
        () async {
      final a = await freshKey();
      final b = await freshKey();
      final env = await pqSeal(a.publicKey, pt);
      await expectLater(
        pqOpen(b.secretKey, env),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('version mismatch → versionMismatch', () async {
      final kp = await freshKey();
      final env = await pqSeal(kp.publicKey, pt);
      env[0] = 0x02;
      await expectLater(
        pqOpen(kp.secretKey, env),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.versionMismatch)),
      );
    });

    test('truncated envelope → malformedEnvelope', () async {
      final kp = await freshKey();
      final env = await pqSeal(kp.publicKey, pt);
      await expectLater(
        pqOpen(kp.secretKey, Uint8List.sublistView(env, 0, 2)),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.malformedEnvelope)),
      );
    });

    test('ctLen overrun → malformedEnvelope', () async {
      final kp = await freshKey();
      final env = await pqSeal(kp.publicKey, pt);
      env[1] = 0xff; // huge declared ctLen
      env[2] = 0xff;
      await expectLater(
        pqOpen(kp.secretKey, env),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.malformedEnvelope)),
      );
    });
  });

  group('envelope shape', () {
    test('starts with version byte and big-endian X-Wing ctLen (1120)',
        () async {
      final kp = await freshKey();
      final env = await pqSeal(kp.publicKey, Uint8List.fromList([1, 2, 3]));
      expect(env[0], equals(0x01));
      expect((env[1] << 8) | env[2], equals(1120));
    });

    test('two seals to same key differ (fresh KEM secret each time)', () async {
      final kp = await freshKey();
      final pt = Uint8List.fromList('same'.codeUnits);
      final e1 = await pqSeal(kp.publicKey, pt);
      final e2 = await pqSeal(kp.publicKey, pt);
      expect(e1, isNot(equals(e2)));
    });
  });

  group('pqDeriveConfirmationTag', () {
    test('is 32 bytes and deterministic for same ss + info', () async {
      final ss = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final info = Uint8List.fromList('sid@bob'.codeUnits);
      final t1 = await pqDeriveConfirmationTag(ss, info);
      final t2 = await pqDeriveConfirmationTag(ss, info);
      expect(t1.length, equals(32));
      expect(t1, equals(t2));
    });

    test('differs for different info, and is not the raw secret', () async {
      final ss = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final t1 = await pqDeriveConfirmationTag(
          ss, Uint8List.fromList('sid-A'.codeUnits));
      final t2 = await pqDeriveConfirmationTag(
          ss, Uint8List.fromList('sid-B'.codeUnits));
      expect(t1, isNot(equals(t2)));
      expect(t1, isNot(equals(ss)));
    });
  });

  group('pqDeriveSessionKey', () {
    test('is 32 bytes and deterministic for same ss + info', () async {
      final ss = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final info = Uint8List.fromList('sid@bob'.codeUnits);
      final k1 = await pqDeriveSessionKey(ss, info);
      final k2 = await pqDeriveSessionKey(ss, info);
      expect(k1.length, equals(32));
      expect(k1, equals(k2));
    });

    test('differs from pqDeriveConfirmationTag for same inputs', () async {
      final ss = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final info = Uint8List.fromList('sid@bob'.codeUnits);
      final tag = await pqDeriveConfirmationTag(ss, info);
      final key = await pqDeriveSessionKey(ss, info);
      expect(key, isNot(equals(tag)),
          reason: 'Session key must be domain-separated from confirmation tag');
    });

    test('differs for different info', () async {
      final ss = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final k1 = await pqDeriveSessionKey(
          ss, Uint8List.fromList('sid-A'.codeUnits));
      final k2 = await pqDeriveSessionKey(
          ss, Uint8List.fromList('sid-B'.codeUnits));
      expect(k1, isNot(equals(k2)));
    });
  });
}
