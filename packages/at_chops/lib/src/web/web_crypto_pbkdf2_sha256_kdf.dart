import 'dart:js_interop';
import 'dart:typed_data';

import '../algorithm/kdf/kdf_params.dart';
import '../algorithm/kdf/passphrase_kdf.dart';
import 'subtle_crypto.dart';

/// PBKDF2-HMAC-SHA256 through the browser's WebCrypto; the same bytes as
/// `Pbkdf2Sha256Kdf`.
///
/// Throws a [StateError] outside a secure context.
class WebCryptoPbkdf2Sha256Kdf implements PassphraseKdf {
  const WebCryptoPbkdf2Sha256Kdf();

  @override
  Future<Uint8List> derive(Uint8List secret, Uint8List salt, KdfParams params,
      {int length = 32}) async {
    if (params is! Pbkdf2Sha256Params) {
      throw ArgumentError.value(params, 'params', 'not Pbkdf2Sha256Params');
    }
    final subtle = subtleCrypto();
    final key = await subtle
        .importKey(
            'raw', secret.toJS, 'PBKDF2'.toJS, false, ['deriveBits'.toJS].toJS)
        .toDart;
    final bits = await subtle
        .deriveBits(
            Pbkdf2Params(
                name: 'PBKDF2',
                hash: 'SHA-256',
                salt: salt.toJS,
                iterations: params.iterations),
            key,
            length * 8)
        .toDart;
    return bits.toDart.asUint8List();
  }
}
