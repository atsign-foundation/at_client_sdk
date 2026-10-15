import 'dart:convert';
import 'dart:typed_data';

import 'aes_gcm.dart';

/// Thrown when a passkey record is malformed or of an unknown version,
/// algorithm or KDF.
class UnsupportedPasskeyRecordException implements Exception {
  /// Initializes the exception with an error [message].
  UnsupportedPasskeyRecordException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'UnsupportedPasskeyRecordException: $message';
}

/// Thrown when a passkey record fails AES-GCM authentication under the kek.
class PasskeyRecordAuthenticationException implements Exception {
  @override
  String toString() =>
      'PasskeyRecordAuthenticationException: the record does not open under '
      'this kek';
}

const _v = 2;
const _alg = 'A256GCM';
const _kdf = 'HKDF-SHA256';

/// Seals and opens the `v: 2` per-passkey @keys record:
///
/// ```
/// { v: 2, alg: A256GCM, kdf: HKDF-SHA256, iv, ct }
/// ```
///
/// `ct` is the @keys JSON sealed under the kek with a random 96-bit `iv`;
/// its AAD is the canonical JSON of every other field, keys sorted.
abstract final class PasskeyRecordCodec {
  /// [atKeys] sealed under the 32-byte [kek], as the record's JSON text.
  static Future<String> seal(Uint8List kek, Map<String, dynamic> atKeys) async {
    _checkKek(kek);
    final iv = randomBytes(12);
    final sealed =
        await gcmSeal(kek, utf8.encode(jsonEncode(atKeys)), _aad(iv), iv: iv);
    return jsonEncode({
      'v': _v,
      'alg': _alg,
      'kdf': _kdf,
      'iv': base64Encode(sealed.iv),
      'ct': base64Encode(sealed.ct),
    });
  }

  /// The @keys document in [record], opened under the 32-byte [kek].
  ///
  /// Throws [UnsupportedPasskeyRecordException] for a malformed or unknown
  /// record; [PasskeyRecordAuthenticationException] when it does not open
  /// under [kek].
  static Future<Map<String, dynamic>> open(Uint8List kek, String record) async {
    _checkKek(kek);
    final sealed = _parse(record);
    final plaintext = await gcmOpen(kek, sealed, _aad(sealed.iv));
    if (plaintext == null) throw PasskeyRecordAuthenticationException();
    return switch (_json(utf8.decode(plaintext))) {
      Map<String, dynamic> atKeys => atKeys,
      _ => throw UnsupportedPasskeyRecordException(
          '@keys document is not a JSON object'),
    };
  }
}

void _checkKek(Uint8List kek) {
  if (kek.length != 32) {
    throw ArgumentError.value(kek.length, 'kek', 'must be 32 bytes');
  }
}

List<int> _aad(Uint8List iv) => utf8.encode(
    jsonEncode({'alg': _alg, 'iv': base64Encode(iv), 'kdf': _kdf, 'v': _v}));

Sealed _parse(String record) => switch (_json(record)) {
      {
              'v': _v,
              'alg': _alg,
              'kdf': _kdf,
              'iv': String iv,
              'ct': String ct,
            } &&
            Map(length: 5) =>
        (iv: _b64(iv), ct: _b64(ct)),
      {'v': final v} when v != _v =>
        throw UnsupportedPasskeyRecordException('unknown version $v'),
      _ => throw UnsupportedPasskeyRecordException(
          'unknown alg/kdf or malformed record'),
    };

Object? _json(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    throw UnsupportedPasskeyRecordException('not a JSON document');
  }
}

Uint8List _b64(String value) {
  try {
    return base64Decode(value);
  } on FormatException {
    throw UnsupportedPasskeyRecordException('not base64: $value');
  }
}
