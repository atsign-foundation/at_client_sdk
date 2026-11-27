import 'dart:typed_data';
import 'dart:convert';

import 'package:at_auth/passkey.dart';
import 'package:at_chops/at_chops.dart'
    show AESKey, AesGcm256EncryptionAlgo, HkdfSha256, InitialisationVector;
import 'package:at_commons/atsign.dart';
import 'package:at_commons/at_commons.dart' show AtDecryptionException;

/// A [RecordSealer] over a raw 32-byte key held in memory. Test support only:
/// no library under lib/ ships a sealer.
class BytesRecordSealer implements RecordSealer {
  /// Takes ownership of [key]: [close] zeroes it. Each call builds the
  /// at_chops algo from the key's base64, a `String` nothing can zero.
  BytesRecordSealer(Uint8List key) : _key = key;

  final Uint8List _key;

  /// Whether [close] was called.
  bool closed = false;

  AesGcm256EncryptionAlgo get _algo {
    if (closed) throw StateError('BytesRecordSealer is closed');
    return AesGcm256EncryptionAlgo(AESKey(base64Encode(_key)));
  }

  @override
  Future<Uint8List> seal(
          Uint8List iv, List<int> plaintext, List<int> aad) async =>
      _algo.encrypt(Uint8List.fromList(plaintext),
          iv: InitialisationVector(iv), aad: aad);

  @override
  Future<Uint8List> open(
      Uint8List iv, Uint8List ciphertext, List<int> aad) async {
    final algo = _algo;
    try {
      return await algo.decrypt(ciphertext,
          iv: InitialisationVector(iv), aad: aad);
    } on AtDecryptionException {
      throw PasskeyRecordAuthenticationException();
    }
  }

  @override
  void close() {
    closed = true;
    _key.fillRange(0, _key.length, 0);
  }
}

/// A [PasskeyKeyDeriver] over HKDF-SHA256 (empty salt, info
/// `<label>|<canonical atSign>`) using the exported label constants.
class BytesPasskeyKeyDeriver implements PasskeyKeyDeriver {
  const BytesPasskeyKeyDeriver();

  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) async {
    final canonical = atSign.toAtsign();
    Uint8List expand(String label) => HkdfSha256.deriveKey(prf.output,
        info: utf8.encode('$label|$canonical'), length: 32);
    String hexOf(String label) {
      final bytes = expand(label);
      try {
        return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }

    final derivation = (
      lookupHex: hexOf(recordIdLabel),
      ns: hexOf(recordNsLabel),
      authSeed: expand(recordAuthSeedLabel),
      sealer: BytesRecordSealer(expand(recordSealLabel)) as RecordSealer,
    );
    prf.wipe();
    return derivation;
  }
}
