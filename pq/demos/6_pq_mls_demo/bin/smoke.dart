// FFI smoke test. Round-trips each primitive against itself.
//
// Run: dart run bin/smoke.dart

import 'dart:io';
import 'dart:typed_data';
import '../lib/openssl.dart';

final _failures = <String>[];

void check(String label, bool ok, [String? detail]) {
  final mark = ok ? '[PASS]' : '[FAIL]';
  print('$mark $label${detail != null ? "  ($detail)" : ""}');
  if (!ok) _failures.add(label);
}

void main() {
  final c = Crypto.load();

  print('=== FFI smoke test (OpenSSL 3.6 via libcrypto) ===\n');

  // ── SHA-256 ──────────────────────────────────────────────────────────────
  final h = c.sha256.hash(Uint8List.fromList('abc'.codeUnits));
  check(
      'SHA-256(\'abc\') matches known vector',
      bytesEqual(h, [
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, //
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23, //
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c, //
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad //
      ]),
      hex(h));

  // ── HMAC-SHA256 ──────────────────────────────────────────────────────────
  final hmac1 =
      c.hmac.mac(Uint8List.fromList('key'.codeUnits), Uint8List.fromList([1]));
  final hmac2 =
      c.hmac.mac(Uint8List.fromList('key'.codeUnits), Uint8List.fromList([2]));
  check('HMAC-SHA256: 0x01 vs 0x02 outputs differ',
      !bytesEqual(hmac1, hmac2) && hmac1.length == 32);

  // ── HKDF-SHA256 ──────────────────────────────────────────────────────────
  final out = c.hkdf.derive(
      Uint8List.fromList('salt'.codeUnits),
      Uint8List.fromList('ikm-bytes-32-bytes-of-keymat-aa'.codeUnits),
      Uint8List.fromList('info'.codeUnits),
      64);
  check('HKDF-SHA256 produces 64 B', out.length == 64);

  // ── AES-256-GCM ──────────────────────────────────────────────────────────
  final key = c.rand.bytes(32);
  final nonce = c.rand.bytes(12);
  final pt = Uint8List.fromList('Hello, post-quantum world!'.codeUnits);
  final (ct, tag) = c.aesGcm.seal(key, nonce, pt, aad: Uint8List(0));
  check('AES-GCM seal produced ct + tag', ct.isNotEmpty && tag.length == 16);
  final ptRoundtrip = c.aesGcm.open(key, nonce, ct, tag, aad: Uint8List(0));
  check('AES-GCM open roundtrip',
      bytesEqual(ptRoundtrip, pt), String.fromCharCodes(ptRoundtrip));

  // ── ML-KEM-768 (already proved in demo 3 — sanity only) ──────────────────
  final (kemPk, kemKeyPtr) = c.mlKem.generateKeypair();
  final (kemCt, ssAlice) =
      c.mlKem.encapsulate(c.mlKem.importPublicKey(kemPk));
  final ssBob = c.mlKem.decapsulate(kemKeyPtr, kemCt);
  check('ML-KEM encaps + decaps match', bytesEqual(ssAlice, ssBob),
      '${ssAlice.length} B');
  c.mlKem.freeKey(kemKeyPtr);

  // ── ML-DSA-65 ────────────────────────────────────────────────────────────
  final (dsaPk, dsaSk) = c.mlDsa.generateKeypair();
  check('ML-DSA keygen produced reasonable sizes',
      dsaPk.length > 1000 && dsaSk.length > 1000, 'pk=${dsaPk.length} sk=${dsaSk.length}');
  final msg = Uint8List.fromList('sign this'.codeUnits);
  final sig = c.mlDsa.sign(dsaSk, msg);
  check('ML-DSA sign returned signature', sig.isNotEmpty, '${sig.length} B');
  check('ML-DSA verify accepts genuine sig', c.mlDsa.verify(dsaPk, msg, sig));
  // Tamper test
  final tampered = Uint8List.fromList(sig);
  tampered[0] ^= 0xff;
  check('ML-DSA verify rejects tampered sig',
      !c.mlDsa.verify(dsaPk, msg, tampered));

  // ── HPKE round trip (Dart-built on top of X-Wing + HKDF + AES-GCM) ───────
  // X-Wing keypair is flat bytes (no FFI handle needed for open).
  final (rcptPk, rcptSk) = c.xwing.keygen();
  check('X-Wing pk size = 1216', rcptPk.length == 1216, '${rcptPk.length}');
  check('X-Wing sk size = 2464', rcptSk.length == 2464, '${rcptSk.length}');
  final info = Uint8List.fromList('demo-info'.codeUnits);
  final aad = Uint8List.fromList('demo-aad'.codeUnits);
  final hpkePt = Uint8List.fromList('hpke payload'.codeUnits);
  final (enc, hpkeCt, hpkeTag) = c.hpke.seal(rcptPk, info, aad, hpkePt);
  check('HPKE seal: enc=1120 (X-Wing ct)', enc.length == 1120, '${enc.length}');
  final hpkePtBack = c.hpke.open(rcptSk, enc, info, aad, hpkeCt, hpkeTag);
  check('HPKE open roundtrip', bytesEqual(hpkePtBack, hpkePt),
      String.fromCharCodes(hpkePtBack));

  // ── Summary ──────────────────────────────────────────────────────────────
  print('\n=== Summary ===');
  if (_failures.isEmpty) {
    print('[PASS] All ${10} primitives operational.');
  } else {
    print('[FAIL] ${_failures.length} failure(s):');
    for (final f in _failures) {
      print('  - $f');
    }
    exit(1);
  }
}
