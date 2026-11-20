import 'dart:convert';
import 'dart:typed_data';

import 'dart:math';

import 'package:at_commons/at_commons.dart';

import '../util/message_text.dart';
import 'passkey_derivation.dart';

/// Thrown when a passkey record is malformed or of an unknown version,
/// algorithm or KDF.
class UnsupportedPasskeyRecordException extends AtException {
  /// Initializes the exception with an error [message].
  UnsupportedPasskeyRecordException(super.message);

  @override
  String toString() => 'UnsupportedPasskeyRecordException: $message';
}

/// Thrown when a passkey record fails AES-GCM authentication under the passkey's sealer.
class PasskeyRecordAuthenticationException extends AtException {
  /// Initializes the exception.
  PasskeyRecordAuthenticationException()
      : super('the record does not open under this passkey');

  @override
  String toString() =>
      'PasskeyRecordAuthenticationException: the record does not open under '
      'this passkey';
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
/// `ct` is a JSON object sealed by a [RecordSealer] with a random 96-bit `iv`;
/// its AAD is the canonical JSON of every other field, keys sorted, and the
/// canonical `atSign` the record belongs to, which the record does not carry:
/// a record opens only for the atSign and type it was sealed for.
abstract final class PasskeyRecordCodec {
  /// [document] of type [typ] for [atSign] sealed by [sealer], as the
  /// record's JSON text.
  static Future<String> seal(RecordSealer sealer, String atSign,
      PasskeyRecordType typ, Map<String, dynamic> document) async {
    final iv = _randomIv();
    final ct = await sealer.seal(
        iv, utf8.encode(jsonEncode(document)), _aad(atSign, typ.name, iv));
    return jsonEncode({
      'v': _v,
      'alg': _alg,
      'kdf': _kdf,
      'typ': typ.name,
      'iv': base64Encode(iv),
      'ct': base64Encode(ct),
    });
  }

  /// The document in [record] for [atSign], opened by [sealer].
  ///
  /// Throws [UnsupportedPasskeyRecordException] for a malformed or unknown
  /// record, or one whose type is not [typ];
  /// [PasskeyRecordAuthenticationException] when it does not open, as when it
  /// was sealed for another atSign.
  static Future<Map<String, dynamic>> open(RecordSealer sealer, String atSign,
      PasskeyRecordType typ, String record) async {
    final parsed = _parse(record);
    if (parsed.typ != typ.name) {
      throw UnsupportedPasskeyRecordException(
          'record type is ${parsed.typ}, expected ${typ.name}');
    }
    final plaintext = await sealer.open(
        parsed.iv, parsed.ct, _aad(atSign, typ.name, parsed.iv));
    return switch (_json(utf8.decode(plaintext))) {
      Map<String, dynamic> document => document,
      _ => throw UnsupportedPasskeyRecordException(
          'record document is not a JSON object'),
    };
  }
}

Uint8List _randomIv() {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(12, (_) => random.nextInt(256)));
}

List<int> _aad(String atSign, String typ, Uint8List iv) =>
    utf8.encode(jsonEncode({
      'alg': _alg,
      'atSign': atSign,
      'iv': base64Encode(iv),
      'kdf': _kdf,
      'typ': typ,
      'v': _v
    }));

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
      {'v': final v} when v != _v => throw UnsupportedPasskeyRecordException(
          'unknown version ${clipForMessage('$v')}'),
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
    throw UnsupportedPasskeyRecordException(
        'not base64: ${clipForMessage(value)}');
  }
}
