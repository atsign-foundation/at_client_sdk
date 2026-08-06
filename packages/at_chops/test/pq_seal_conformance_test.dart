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
            info: _optHex(v['info']));
        expect(_toHex(d.key), v['key']);
        expect(_toHex(d.nonce), v['nonce']);
      });
    }

    test('a null info and a zero-length info derive the same key', () {
      // Worth pinning rather than leaving implicit: a port that distinguishes
      // "absent" from "empty" would diverge on the nskey path, where callers
      // pass no info at all.
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
          info: _optHex(v['info']),
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
            info: _optHex(v['info']), aad: Uint8List.fromList([0])),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.authFailure)),
      );
    });

    test('an unknown version is refused before anything is parsed', () {
      final e = _hex(v['envelope'] as String)..[0] = 0x02;
      expect(
        () => pqOpen(kem, _hex(v['recipientSeed'] as String), e,
            info: _optHex(v['info']), aad: _optHex(v['aad'])),
        throwsA(isA<PqOpenException>()
            .having((e) => e.reason, 'reason', PqOpenFailure.versionMismatch)),
      );
    });
  });
}
