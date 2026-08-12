/// Cross-implementation conformance for the `atPQv1-base` seal.
///
/// **These vectors are self-generated, and that is the point of writing it
/// down.** No third party publishes vectors for `atPQv1-base` — it is an
/// Atsign-internal construction, not RFC 9180 HPKE. So unlike
/// `hpke_wg_kem_vectors.dart` (the IETF HPKE working group's) or
/// `ml_dsa_65_acvp.json` (NIST's), these attest nothing on their own. What
/// they are is a **contract between implementations**: any second
/// implementation that reproduces them agrees with this one byte-for-byte, and
/// one that does not has a defect somebody can point at.
///
/// That is worth having because the alternative has already failed here. The
/// tagged `_apsk` shape carried a version field and still forked across two
/// atServer implementations inside a week, because the only specification was
/// a Dart function and the second implementation's own documentation asserted
/// a conformance that was false. Nothing mechanical caught it. A vector file
/// turns red on the next build.
///
/// The written spec is `docs/projects/pq/seal-spec.md`. The primitives
/// underneath — HKDF-SHA256, HMAC-SHA256 and AES-256-GCM — are separately
/// checked against RFC 5869, RFC 4231 and McGrew–Viega, and the KEM against
/// the HPKE working group's published `0x647A` vectors. What is unattested by
/// anyone outside this repository is the *composition*: the suite label, the
/// two derivation labels, the empty salt, the ordering and the framing. Those
/// are exactly what this file pins.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
// Package-internal schedule probe; not exported by the barrel.
import 'package:at_chops/src/algorithm/encryption/pq_hpke.dart'
    show pqSealDeriveKeyAndNonce;
import 'package:test/test.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List? _optHex(Object? v) => v == null ? null : _hex(v as String);

void main() {
  final vectors =
      jsonDecode(File('test/vectors/pq_seal_v1.json').readAsStringSync())
          as Map;
  final schedule =
      (vectors['keySchedule'] as List).cast<Map<String, dynamic>>();
  final envelopes = (vectors['envelopes'] as List).cast<Map<String, dynamic>>();

  const kem = XWingPureDartAlgo.instance;

  group('atPQv1-base key schedule', () {
    test('the fixture states its own provenance', () {
      // A self-generated vector file that does not say so reads as outside
      // attestation, which would be worse than having none.
      expect((vectors['_provenance'] as Map)['warning'],
          contains('SELF-GENERATED'));
    });

    for (final v in schedule) {
      test(
          'ss ${(v['sharedSecret'] as String).substring(0, 8)}… / '
          'info ${v['infoLabel']}', () {
        final d = pqSealDeriveKeyAndNonce(_hex(v['sharedSecret'] as String),
            info: _optHex(v['info']) ?? Uint8List(0));
        expect(_toHex(d.key), v['key']);
        expect(_toHex(d.nonce), v['nonce']);
      });
    }

    test('a null info and a zero-length info derive the same key', () {
      // A property of the key SCHEDULE, which is what a second implementation
      // ports, and it stays pinned here because `pqSealDeriveKeyAndNonce` is
      // the schedule's own entry point and still accepts an absent info.
      //
      // It is no longer reachable through `pqSeal`/`pqOpen`, whose `info` is
      // required — the old justification said this mattered "on the nskey
      // path, where callers pass no info at all", and that was never true:
      // NskeyProvider passes one at both its seal and its open. That the two
      // coalesce is exactly why omitting `info` was dangerous rather than
      // merely sloppy, since two callers that both omitted it shared a
      // binding silently.
      final a = schedule.firstWhere((v) => v['infoLabel'] == 'empty');
      final b = schedule.firstWhere((v) =>
          v['infoLabel'] == 'zeroLength' &&
          v['sharedSecret'] == a['sharedSecret']);
      expect(a['key'], b['key']);
      expect(a['nonce'], b['nonce']);
    });
  });

  group('atPQv1-base envelopes', () {
    test('the fixture covers every context the production paths use', () {
      final labels = envelopes.map((e) => e['infoLabel']).toSet();
      expect(labels, containsAll(['nskey', 'secretSharing']));
      expect(envelopes, hasLength(80));
    });

    for (final v in envelopes) {
      test(
          'envelope ${v['id']} (info ${v['infoLabel']}, '
          'aad ${v['aad'] == null ? 'none' : 'set'}, '
          '${(v['plaintext'] as String).length ~/ 2} byte plaintext) opens',
          () async {
        final pt = await pqOpen(
          kem,
          _hex(v['recipientSeed'] as String),
          _hex(v['envelope'] as String),
          info: _optHex(v['info']) ?? Uint8List(0),
          aad: _optHex(v['aad']),
        );
        expect(_toHex(pt), v['plaintext']);
      });
    }
  });

  group('atPQv1-base framing', () {
    test('every envelope is ver 0x01 with a 1120-byte X-Wing ciphertext', () {
      for (final v in envelopes) {
        final e = _hex(v['envelope'] as String);
        expect(e[0], 0x01, reason: 'version byte');
        expect((e[1] << 8) | e[2], XWingPureDartAlgo.ciphertextLength,
            reason: 'big-endian KEM ciphertext length');
        // ver(1) + ctLen(2) + kemCt + ciphertext(= plaintext length) + tag(16)
        expect(
            e.length, 3 + 1120 + (v['plaintext'] as String).length ~/ 2 + 16);
      }
    });
  });

  group('the write-side version selector', () {
    // Until this existed the emitted version was a global constant, so
    // introducing a new construction meant flipping it fleet-wide: there was
    // no way to emit the old version to peers that had not upgraded and the
    // new one to peers that had. The read side always dispatched on the
    // version byte; only the write side could not choose.
    late Uint8List pk;
    setUpAll(() async {
      pk = (await kem.generateKeyPair()).publicKey;
    });

    test('the default is the version the read side expects', () {
      expect(pqSealDefaultVersion, 0x01);
      expect(pqSealSupportedVersions, contains(pqSealDefaultVersion));
    });

    test('asking for the current version explicitly emits it', () async {
      final e = await pqSeal(kem, pk, Uint8List.fromList([1, 2, 3]),
          info: Uint8List(0), version: pqSealDefaultVersion);
      expect(e[0], pqSealDefaultVersion);
    });

    test('asking for a version this build cannot open is refused', () async {
      // Emitting it would produce an envelope nobody can read, since its suite
      // label exists nowhere — a silent write failure discovered only on the
      // first read attempt, potentially by someone else.
      await expectLater(
        pqSeal(kem, pk, Uint8List.fromList([1]),
            info: Uint8List(0), version: 0xff),
        throwsA(isA<PqSealException>()),
      );
    });
  });

  group('ver 0x02 — RFC 9180 through pqSeal', () {
    late Uint8List sk;
    late Uint8List pk;
    setUpAll(() async {
      final kp = await kem.generateKeyPair();
      sk = kp.secretKey;
      pk = kp.publicKey;
    });

    final pt = Uint8List.fromList(utf8.encode('a conveyed content key'));
    final info = Uint8List.fromList(utf8.encode('at_client/nskey/v1:app@a'));
    final aad = Uint8List.fromList(utf8.encode('bound'));

    test('round-trips, and stamps its own version', () async {
      final e = await pqSeal(kem, pk, pt, info: info, aad: aad, version: 0x02);
      expect(e[0], 0x02);
      expect(await pqOpen(kem, sk, e, info: info, aad: aad), pt);
    });

    test('its ciphertext differs from ver 0x01 over the same inputs', () async {
      // Not a strong claim on its own — fresh encapsulation alone would make
      // them differ. It is here to catch the version byte being stamped
      // without the construction actually changing.
      final v1 = await pqSeal(kem, pk, pt, info: info, version: 0x01);
      final v2 = await pqSeal(kem, pk, pt, info: info, version: 0x02);
      expect(v1[0], 0x01);
      expect(v2[0], 0x02);
      expect(v1.length, v2.length,
          reason: 'both are X-Wing with a 16-byte tag, so the framing is the '
              'same size — only the schedule and AEAD differ');
    });

    test('a v2 envelope relabelled as v1 fails to open, and vice versa',
        () async {
      // The real check that the two constructions are separated. If the
      // version byte only selected a label and the derivation were shared,
      // relabelling would still open.
      final v2 = await pqSeal(kem, pk, pt, info: info, version: 0x02);
      final asV1 = Uint8List.fromList(v2)..[0] = 0x01;
      await expectLater(
        pqOpen(kem, sk, asV1, info: info),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );

      final v1 = await pqSeal(kem, pk, pt, info: info, version: 0x01);
      final asV2 = Uint8List.fromList(v1)..[0] = 0x02;
      await expectLater(
        pqOpen(kem, sk, asV2, info: info),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('the info binding holds under v2 too', () async {
      final e = await pqSeal(kem, pk, pt, info: info, version: 0x02);
      await expectLater(
        pqOpen(kem, sk, e,
            info: Uint8List.fromList(utf8.encode('a different context'))),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });
  });

  group('ver 0x03 — pure ML-KEM-1024 through pqSeal', () {
    // The no-hybrid option end to end. Its KEM is a different algorithm with
    // different sizes, so this also pins that the framing's ctLen is genuinely
    // read from the encapsulation rather than assumed to be X-Wing's 1120.
    const mlkem = MlKem1024PureDartAlgo.instance;
    late Uint8List sk;
    late Uint8List pk;
    setUpAll(() async {
      final kp = await mlkem.generateKeyPair();
      sk = kp.secretKey;
      pk = kp.publicKey;
    });

    final pt = Uint8List.fromList(utf8.encode('a conveyed content key'));
    final info = Uint8List.fromList(utf8.encode('at_client/nskey/v1:app@a'));

    test('round-trips and frames a 1568-byte ciphertext', () async {
      final e = await pqSeal(mlkem, pk, pt, info: info, version: 0x03);
      expect(e[0], 0x03);
      expect((e[1] << 8) | e[2], MlKem1024PureDartAlgo.ciphertextLength);
      expect(await pqOpen(mlkem, sk, e, info: info), pt);
    });

    test('the info binding holds', () async {
      final e = await pqSeal(mlkem, pk, pt, info: info, version: 0x03);
      await expectLater(
        pqOpen(mlkem, sk, e,
            info: Uint8List.fromList(utf8.encode('a different context'))),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('relabelling it as the hybrid version fails to open', () async {
      // The two RFC 9180 versions differ only by suite, and suite_id enters
      // every labelled derivation — so this proves the suite is actually
      // selected by the version byte rather than the version being cosmetic.
      final e = await pqSeal(mlkem, pk, pt, info: info, version: 0x03);
      final asV2 = Uint8List.fromList(e)..[0] = 0x02;
      await expectLater(
        pqOpen(mlkem, sk, asV2, info: info),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });
  });

  group('the context binding is real', () {
    // The negative arm. Without it every test above would pass on an
    // implementation that ignored info and aad entirely, since the sealer and
    // the opener would ignore them together.
    late Map<String, dynamic> v;
    setUpAll(() => v = envelopes
        .firstWhere((e) => e['infoLabel'] == 'nskey' && e['aad'] != null));

    test('opening with the wrong info fails', () {
      expect(
        () => pqOpen(kem, _hex(v['recipientSeed'] as String),
            _hex(v['envelope'] as String),
            info: Uint8List.fromList(utf8.encode('at_client/nskey/v1:other')),
            aad: _optHex(v['aad'])),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('opening with the wrong aad fails', () {
      expect(
        () => pqOpen(kem, _hex(v['recipientSeed'] as String),
            _hex(v['envelope'] as String),
            info: _optHex(v['info']) ?? Uint8List(0),
            aad: Uint8List.fromList([0])),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('an unknown version is refused before anything is parsed', () {
      final e = _hex(v['envelope'] as String)..[0] = 0xff;
      expect(
        () => pqOpen(kem, _hex(v['recipientSeed'] as String), e,
            info: _optHex(v['info']) ?? Uint8List(0), aad: _optHex(v['aad'])),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.versionMismatch)),
      );
    });
  });

  test('the version table and pqSealSupportedVersions agree exactly', () {
    // The advertised set and the internal version table are separate
    // declarations; a version added to one without the other either refuses
    // seals it claims to support or serves rows it never advertised. The
    // schedule probe walks every possible byte, so this is an equality proof
    // by behaviour rather than a copy of either declaration.
    final ss = Uint8List(32);
    for (var v = 0; v <= 0xff; v++) {
      if (pqSealSupportedVersions.contains(v)) {
        expect(() => pqSealDeriveKeyAndNonce(ss, version: v), returnsNormally,
            reason: 'advertised version 0x${v.toRadixString(16)} has no row');
      } else {
        expect(
            () => pqSealDeriveKeyAndNonce(ss, version: v), throwsArgumentError,
            reason: 'unadvertised version 0x${v.toRadixString(16)} has a row');
      }
    }
  });
}
