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

/// What a per-passkey record holds; part of its authenticated header.
enum PasskeyRecordType {
  /// The enrollment pointer `{"enrollmentId": ...}`.
  eid,

  /// The @keys document.
  atkeys,
}

/// Seals and opens the `v: 2` per-passkey record:
///
/// ```
/// { v: 2, alg: A256GCM, kdf: HKDF-SHA256, typ: eid|atkeys, iv, ct }
/// ```
///
/// `ct` is a JSON object sealed under the kek with a random 96-bit `iv`;
/// its AAD is the canonical JSON of every other field, keys sorted.
abstract final class PasskeyRecordCodec {
  /// [document] of type [typ] sealed under the 32-byte [kek], as the record's
  /// JSON text.
  static Future<String> seal(Uint8List kek, PasskeyRecordType typ,
      Map<String, dynamic> document) async {
    _checkKek(kek);
    final iv = randomBytes(12);
    final sealed = await gcmSeal(
        kek, utf8.encode(jsonEncode(document)), _aad(typ.name, iv),
        iv: iv);
    return jsonEncode({
      'v': _v,
      'alg': _alg,
      'kdf': _kdf,
      'typ': typ.name,
      'iv': base64Encode(sealed.iv),
      'ct': base64Encode(sealed.ct),
    });
  }

  /// The document in [record], opened under the 32-byte [kek].
  ///
  /// Throws [UnsupportedPasskeyRecordException] for a malformed or unknown
  /// record, or one whose type is not [typ];
  /// [PasskeyRecordAuthenticationException] when it does not open under [kek].
  static Future<Map<String, dynamic>> open(
      Uint8List kek, PasskeyRecordType typ, String record) async {
    _checkKek(kek);
    final parsed = _parse(record);
    if (parsed.typ != typ.name) {
      throw UnsupportedPasskeyRecordException(
          'record type is ${parsed.typ}, expected ${typ.name}');
    }
    final plaintext = await gcmOpen(
        kek, (iv: parsed.iv, ct: parsed.ct), _aad(typ.name, parsed.iv));
    if (plaintext == null) throw PasskeyRecordAuthenticationException();
    return switch (_json(utf8.decode(plaintext))) {
      Map<String, dynamic> document => document,
      _ => throw UnsupportedPasskeyRecordException(
          'record document is not a JSON object'),
    };
  }
}

void _checkKek(Uint8List kek) {
  if (kek.length != 32) {
    throw ArgumentError.value(kek.length, 'kek', 'must be 32 bytes');
  }
}

List<int> _aad(String typ, Uint8List iv) => utf8.encode(jsonEncode(
    {'alg': _alg, 'iv': base64Encode(iv), 'kdf': _kdf, 'typ': typ, 'v': _v}));

({String typ, Uint8List iv, Uint8List ct}) _parse(String record) =>
    switch (_json(record)) {
      {
                'v': _v,
                'alg': _alg,
                'kdf': _kdf,
                'typ': String typ,
                'iv': String iv,
                'ct': String ct,
              } &&
              Map(length: 6)
          when PasskeyRecordType.values.any((t) => t.name == typ) =>
        (typ: typ, iv: _b64(iv), ct: _b64(ct)),
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
