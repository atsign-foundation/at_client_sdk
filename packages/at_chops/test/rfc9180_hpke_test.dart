/// RFC 9180 Base-mode key schedule, against the IETF HPKE working group's
/// published vector for the suite `ver = 0x02` emits.
///
/// This is the difference between the two constructions in this package.
/// `atPQv1-base`'s vectors are self-generated, because no third party
/// publishes any; these are the working group's, mirrored by the Go standard
/// library, and neither we nor anyone at Atsign produced a byte of them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
// Package-internal key-schedule machinery under test; not barrel-exported.
import 'package:at_chops/src/algorithm/encryption/rfc9180_hpke.dart';
import 'package:at_commons/at_commons.dart' show AtDecryptionException;
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

void main() {
  final v = jsonDecode(
          File('test/vectors/hpke_wg_0x647a_chacha.json').readAsStringSync())
      as Map;

  const suite = HpkeSuite.xWingHkdfSha256ChaCha20Poly1305;

  test('the vector is the suite we emit', () {
    expect(v['mode'], 0);
    expect(v['kem_id'], suite.kemId);
    expect(v['kdf_id'], suite.kdfId);
    expect(v['aead_id'], suite.aeadId);
  });

  test('suite_id is built the way RFC 9180 section 5.1 says', () {
    // Getting this wrong changes every derived key rather than failing
    // loudly, which is why the vector carries it explicitly.
    expect(_toHex(suite.suiteId), v['suite_id']);
  });

  test('the KEM reproduces the published shared secret', () async {
    final ss = await XWingPureDartAlgo.instance
        .decapsulate(_hex(v['skRm'] as String), _hex(v['enc'] as String));
    expect(_toHex(ss), v['shared_secret']);
  });

  test('the Base-mode key schedule reproduces key, base_nonce and exporter',
      () {
    final ks = hpkeKeyScheduleBase(
      suite,
      _hex(v['shared_secret'] as String),
      info: _hex(v['info'] as String),
    );
    expect(_toHex(ks.key), v['key']);
    expect(_toHex(ks.baseNonce), v['base_nonce']);
    expect(_toHex(ks.exporterSecret), v['exporter_secret']);
  });

  test('and it is driven end to end from the KEM, not from the vector\'s ss',
      () async {
    // The test above starts from a published intermediate. This one starts
    // from the encapsulation, so a KEM/schedule seam error cannot hide.
    final ss = await XWingPureDartAlgo.instance
        .decapsulate(_hex(v['skRm'] as String), _hex(v['enc'] as String));
    final ks = hpkeKeyScheduleBase(suite, ss, info: _hex(v['info'] as String));
    expect(_toHex(ks.key), v['key']);
  });

  group('the AEAD, against the published encryptions', () {
    // Ten rows, each with its own aad. Only sequence number 0 is reachable
    // from a single-shot seal — HPKE XORs the sequence into base_nonce for
    // later messages, and this construction never sends a second message
    // under one key — so the rest are checked by decrypting at the nonce the
    // vector states rather than by deriving it.
    final encryptions = (v['encryptions'] as List).cast<Map>();

    test('sequence 0 uses base_nonce unmodified', () {
      expect(encryptions.first['nonce'], v['base_nonce'],
          reason: 'single-shot sealing derives no sequence, so if these ever '
              'differ the construction has grown a counter nobody wrote');
    });

    for (var i = 0; i < 10; i++) {
      test('encryption $i decrypts to the published plaintext', () async {
        final e = encryptions[i];
        final pt = await const ChaCha20Poly1305Algo().decrypt(
          _hex(e['ct'] as String),
          key: _hex(v['key'] as String),
          nonce: _hex(e['nonce'] as String),
          aad: _hex(e['aad'] as String),
        );
        expect(_toHex(pt), e['pt']);
      });
    }

    test('and re-encrypting reproduces the published ciphertext', () async {
      final e = encryptions.first;
      final ct = await const ChaCha20Poly1305Algo().encrypt(
        _hex(e['pt'] as String),
        key: _hex(v['key'] as String),
        nonce: _hex(e['nonce'] as String),
        aad: _hex(e['aad'] as String),
      );
      expect(_toHex(ct), e['ct']);
    });

    test('the wrong aad fails, so the binding is real', () {
      final e = encryptions.first;
      expect(
        () => const ChaCha20Poly1305Algo().decrypt(
          _hex(e['ct'] as String),
          key: _hex(v['key'] as String),
          nonce: _hex(e['nonce'] as String),
          aad: const [0x00],
        ),
        throwsA(isA<AtDecryptionException>()),
      );
    });
  });

  group('the ML-KEM-1024 suite (KEM 0x0042, HKDF-SHA384, AES-256-GCM)', () {
    // The no-hybrid option. Its KDF is SHA-384, for which RFC 5869 publishes
    // no vectors — so this group is HkdfSha384's only third-party attestation,
    // exercised through the key schedule end to end.
    final w = jsonDecode(File('test/vectors/hpke_wg_0x0042_mlkem1024.json')
        .readAsStringSync()) as Map;
    const suite = HpkeSuite.mlKem1024HkdfSha384Aes256Gcm;

    test('the vector is the suite we would emit', () {
      expect(w['mode'], 0);
      expect(w['kem_id'], suite.kemId);
      expect(w['kdf_id'], suite.kdfId);
      expect(w['aead_id'], suite.aeadId);
      expect(_toHex(suite.suiteId), w['suite_id']);
    });

    test('the key schedule reproduces key, base_nonce and exporter', () {
      final ks = hpkeKeyScheduleBase(suite, _hex(w['shared_secret'] as String),
          info: _hex(w['info'] as String));
      expect(_toHex(ks.key), w['key']);
      expect(_toHex(ks.baseNonce), w['base_nonce']);
      expect(_toHex(ks.exporterSecret), w['exporter_secret'],
          reason: 'a 48-byte exporter, which is what makes this the SHA-384 '
              'arm rather than SHA-256 with a different label');
    });

    test('driven end to end from the KEM rather than the published secret',
        () async {
      final kp = await MlKem1024PureDartAlgo.instance
          .generateKeyPair(_hex(w['skRm'] as String));
      final ss = await MlKem1024PureDartAlgo.instance
          .decapsulate(kp.secretKey, _hex(w['enc'] as String));
      final ks =
          hpkeKeyScheduleBase(suite, ss, info: _hex(w['info'] as String));
      expect(_toHex(ks.key), w['key']);
    });

    test('the AEAD decrypts the published encryptions', () async {
      for (final e in (w['encryptions'] as List).cast<Map>()) {
        final pt = await AesGcm256EncryptionAlgo(
                AESKey(base64Encode(_hex(w['key'] as String))))
            .decrypt(_hex(e['ct'] as String),
                iv: InitialisationVector(_hex(e['nonce'] as String)),
                aad: _hex(e['aad'] as String));
        expect(_toHex(pt), e['pt']);
      }
    });

    test('the SHA-256 suite derives different keys from the same secret', () {
      // Without this, a build whose KDF dispatch ignored kdf_id and always used
      // SHA-256 would still pass every test above that starts from the
      // published shared secret, because suite_id alone would change the
      // output. This pins that the KDF itself differs.
      final ss = _hex(w['shared_secret'] as String);
      final a = hpkeKeyScheduleBase(suite, ss);
      final b =
          hpkeKeyScheduleBase(HpkeSuite.xWingHkdfSha256ChaCha20Poly1305, ss);
      expect(a.exporterSecret, hasLength(48));
      expect(b.exporterSecret, hasLength(32));
      expect(_toHex(a.key), isNot(_toHex(b.key)));
    });
  });
}
