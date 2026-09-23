import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../algorithm/at_algorithm.dart';
import '../algorithm/padding/pkcs7.dart';
import '../algorithm/padding/types.dart';
import '../key/impl/aes_key.dart';
import '../algorithm/at_iv.dart';
import 'subtle_crypto.dart';

/// AES-CTR through the browser's WebCrypto, byte-identical to
/// `AESEncryptionAlgo` on the VM: PKCS7 padding to 16-byte blocks, the IV as
/// the whole 128-bit counter block, and a zero IV when none is given.
///
/// Throws a [StateError] outside a secure context.
class WebCryptoAesCtr
    implements SymmetricEncryptionAlgorithm<Uint8List, Uint8List> {
  final AESKey _aesKey;
  final PaddingAlgorithm _padding =
      PKCS7Padding(PaddingParams()..blockSize = 16);
  Future<web.CryptoKey>? _cryptoKey;

  WebCryptoAesCtr(this._aesKey);

  @override
  Future<Uint8List> encrypt(Uint8List plainData,
      {InitialisationVector? iv}) async {
    final subtle = subtleCrypto();
    final cipherText = await subtle
        .encrypt(_params(iv), await _key(subtle),
            Uint8List.fromList(_padding.addPadding(plainData)).toJS)
        .toDart;
    return (cipherText as JSArrayBuffer).toDart.asUint8List();
  }

  @override
  Future<Uint8List> decrypt(Uint8List encryptedData,
      {InitialisationVector? iv}) async {
    final subtle = subtleCrypto();
    final padded = await subtle
        .decrypt(_params(iv), await _key(subtle), encryptedData.toJS)
        .toDart;
    return Uint8List.fromList(
        _padding.removePadding((padded as JSArrayBuffer).toDart.asUint8List()));
  }

  Future<web.CryptoKey> _key(web.SubtleCrypto subtle) => _cryptoKey ??= subtle
      .importKey('raw', base64Decode(_aesKey.key).toJS, 'AES-CTR'.toJS, false,
          ['encrypt'.toJS, 'decrypt'.toJS].toJS)
      .toDart;

  static AesCtrParams _params(InitialisationVector? iv) => AesCtrParams(
      name: 'AES-CTR',
      counter: (iv?.ivBytes ?? Uint8List(16)).toJS,
      length: 128);
}
