import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:cryptography/cryptography.dart';

import 'envelope_exceptions.dart';
import 'unlock_secret.dart';

/// An AES-GCM nonce and its ciphertext with the 16-byte tag appended.
typedef _Sealed = ({Uint8List iv, Uint8List ct});

/// One way into an envelope: the content key wrapped under a KEK derived from
/// an [UnlockSecret] with [salt] and, for a passphrase, [params].
typedef _Unlock = ({
  String kind,
  Uint8List salt,
  KdfParams? params,
  _Sealed wrap
});

final _gcm = AesGcm.with256bits();
const _macLength = 16;
const _hkdfAlg = 'hkdf-sha256';

/// Seals a JSON document under a random content key, wrapped once per
/// [UnlockSecret], into the `v: 1` key envelope:
///
/// ```
/// { v: 1, atSign,
///   content: { alg: A256GCM, iv, ct },
///   unlocks: [ { kind: prf | passphrase,
///                kdf: { alg, salt, params? },
///                wrap: { iv, ct } } ] }
/// ```
///
/// Each passphrase unlock carries the [KdfParams] it was derived with, so a
/// change to [passphraseParams] never orphans an existing envelope.
class KeyEnvelopeCodec {
  const KeyEnvelopeCodec({this.passphraseParams = defaultPassphraseParams});

  static const defaultPassphraseParams =
      Argon2idParams(memoryKiB: 19456, iterations: 2, parallelism: 1);

  /// The parameters new passphrase unlocks are derived with.
  final KdfParams passphraseParams;

  /// Seals [plaintext] for [atSign], openable by each of [secrets].
  ///
  /// Throws [ArgumentError] when [secrets] is empty.
  Future<Uint8List> seal(String atSign, Map<String, dynamic> plaintext,
      List<UnlockSecret> secrets) async {
    if (secrets.isEmpty) {
      throw ArgumentError.value(secrets, 'secrets', 'at least one is required');
    }
    final contentKey = _randomBytes(32);
    final unlocks = [
      for (final secret in secrets)
        await _wrap(atSign, secret, contentKey, passphraseParams)
    ];
    return _encode(atSign, plaintext, contentKey, unlocks);
  }

  /// Opens [envelope] for [atSign] with [secret].
  ///
  /// Throws [UnsupportedEnvelopeException] for a malformed envelope or an
  /// unknown version, algorithm or unlock kind;
  /// [EnvelopeAtSignMismatchException] when it was sealed for another atSign;
  /// [NoMatchingUnlockException] when it has no unlock of [secret]'s kind;
  /// [EnvelopeUnlockFailedException] when no such unlock opens with [secret]
  /// or the content fails authentication.
  Future<OpenedEnvelope> open(
      String atSign, Uint8List envelope, UnlockSecret secret) async {
    final (content, unlocks) = _parse(atSign, envelope);
    final contentKey = await _unwrapContentKey(atSign, unlocks, secret);
    final plaintext =
        await _gcmOpen(contentKey, content, _contentAad(atSign)) ??
            (throw EnvelopeUnlockFailedException(
                'the content of $atSign\'s envelope failed authentication'));
    return OpenedEnvelope._(
        atSign,
        jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
        contentKey,
        unlocks,
        passphraseParams);
  }
}

Future<_Unlock> _wrap(String atSign, UnlockSecret secret, Uint8List contentKey,
    KdfParams? passphraseParams) async {
  final kind = _kindOf(secret);
  final salt = _randomBytes(16);
  final params = secret is PassphraseSecret ? passphraseParams : null;
  final kek = await _kek(secret, salt, params);
  return (
    kind: kind,
    salt: salt,
    params: params,
    wrap: await _gcmSeal(kek, contentKey, _wrapAad(atSign, kind, salt, params)),
  );
}

/// An envelope opened with one of its secrets.
final class OpenedEnvelope {
  OpenedEnvelope._(this.atSign, this.plaintext, this._contentKey, this._unlocks,
      this._passphraseParams);

  final String atSign;

  /// The sealed document.
  final Map<String, dynamic> plaintext;

  final Uint8List _contentKey;
  final List<_Unlock> _unlocks;
  final KdfParams? _passphraseParams;

  /// Seals [replacement] under the same content key and unlocks, with a
  /// fresh content nonce.
  Future<Uint8List> reseal(Map<String, dynamic> replacement) =>
      _encode(atSign, replacement, _contentKey, _unlocks);

  /// Seals [plaintext] under the same content key with every existing unlock
  /// plus a new one for [secret].
  Future<Uint8List> withUnlock(UnlockSecret secret) async {
    final newUnlock =
        await _wrap(atSign, secret, _contentKey, _passphraseParams);
    return _encode(atSign, plaintext, _contentKey, [..._unlocks, newUnlock]);
  }

  /// The server copy [other] with this envelope's unlocks added to its own.
  ///
  /// Keeps [other]'s content unchanged and appends each unlock of this
  /// envelope whose kind and salt [other] does not already hold.
  ///
  /// Throws [EnvelopeContentKeyMismatchException] when [other]'s content does
  /// not open under this envelope's content key.
  Future<Uint8List> mergeUnlocksFrom(Uint8List other) async {
    final (otherContent, otherUnlocks) = _parse(atSign, other);
    if (await _gcmOpen(_contentKey, otherContent, _contentAad(atSign)) ==
        null) {
      throw EnvelopeContentKeyMismatchException(
          'the other envelope is not sealed under this content key');
    }
    final held = otherUnlocks.map(_identity).toSet();
    return _encodeSealed(atSign, otherContent, [
      ...otherUnlocks,
      ..._unlocks.where((u) => !held.contains(_identity(u))),
    ]);
  }
}

String _identity(_Unlock unlock) =>
    '${unlock.kind}|${base64Encode(unlock.salt)}';

Future<Uint8List> _unwrapContentKey(
    String atSign, List<_Unlock> unlocks, UnlockSecret secret) async {
  final kind = _kindOf(secret);
  final candidates = unlocks.where((u) => u.kind == kind);
  if (candidates.isEmpty) {
    throw NoMatchingUnlockException('$atSign\'s envelope has no $kind unlock');
  }
  for (final unlock in candidates) {
    final kek = await _kek(secret, unlock.salt, unlock.params);
    final contentKey = await _gcmOpen(kek, unlock.wrap,
        _wrapAad(atSign, unlock.kind, unlock.salt, unlock.params));
    if (contentKey != null) return contentKey;
  }
  throw EnvelopeUnlockFailedException(
      'no $kind unlock of $atSign\'s envelope opens with this secret');
}

/// The additional data each wrap is authenticated with.
///
/// Binds a wrap to its envelope's [atSign] and to every input of its KEK, so
/// a changed kind, salt or parameter fails authentication rather than
/// deriving a different key silently.
List<int> _wrapAad(
    String atSign, String kind, Uint8List salt, KdfParams? params) {
  return utf8.encode(jsonEncode([
    'at_client_wasm/wrap/v1',
    atSign,
    kind,
    base64Encode(salt),
    params?.toJson(),
  ]));
}

List<int> _contentAad(String atSign) =>
    utf8.encode('at_client_wasm/content/v1|$atSign');

String _kindOf(UnlockSecret secret) => switch (secret) {
      PrfSecret() => 'prf',
      PassphraseSecret() => 'passphrase',
    };

Future<Uint8List> _kek(
        UnlockSecret secret, Uint8List salt, KdfParams? params) =>
    switch (secret) {
      PrfSecret(:final output) => _hkdf(output, salt),
      PassphraseSecret(:final passphrase) =>
        kdfFor(params!).derive(utf8.encode(passphrase), salt, params),
    };

Future<Uint8List> _hkdf(Uint8List prfOutput, Uint8List salt) async {
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(prfOutput),
      nonce: salt,
      info: utf8.encode('at_client_wasm/kek/prf/v1'));
  return Uint8List.fromList(await key.extractBytes());
}

Future<_Sealed> _gcmSeal(
    List<int> key, List<int> plaintext, List<int> aad) async {
  final box = await _gcm.encrypt(plaintext,
      secretKey: SecretKey(key), nonce: _randomBytes(12), aad: aad);
  return (
    iv: Uint8List.fromList(box.nonce),
    ct: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
  );
}

/// The plaintext, or null when [sealed] fails authentication under [key].
Future<Uint8List?> _gcmOpen(
    List<int> key, _Sealed sealed, List<int> aad) async {
  if (sealed.ct.length < _macLength) return null;
  final split = sealed.ct.length - _macLength;
  try {
    return Uint8List.fromList(await _gcm.decrypt(
        SecretBox(sealed.ct.sublist(0, split),
            nonce: sealed.iv, mac: Mac(sealed.ct.sublist(split))),
        secretKey: SecretKey(key),
        aad: aad));
  } on SecretBoxAuthenticationError {
    return null;
  } on ArgumentError {
    return null;
  }
}

Future<Uint8List> _encode(String atSign, Map<String, dynamic> plaintext,
    Uint8List contentKey, List<_Unlock> unlocks) async {
  final content = await _gcmSeal(
      contentKey, utf8.encode(jsonEncode(plaintext)), _contentAad(atSign));
  return _encodeSealed(atSign, content, unlocks);
}

Uint8List _encodeSealed(String atSign, _Sealed content, List<_Unlock> unlocks) {
  return utf8.encode(jsonEncode({
    'v': 1,
    'atSign': atSign,
    'content': {'alg': 'A256GCM', ..._sealedJson(content)},
    'unlocks': [
      for (final u in unlocks)
        {
          'kind': u.kind,
          'kdf': {
            'alg': u.params?.toJson()['alg'] ?? _hkdfAlg,
            'salt': base64Encode(u.salt),
            if (u.params != null) 'params': u.params!.toJson(),
          },
          'wrap': _sealedJson(u.wrap),
        }
    ],
  }));
}

Map<String, String> _sealedJson(_Sealed s) =>
    {'iv': base64Encode(s.iv), 'ct': base64Encode(s.ct)};

(_Sealed, List<_Unlock>) _parse(String atSign, Uint8List envelope) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(envelope));
  } on FormatException {
    throw UnsupportedEnvelopeException('not a JSON document');
  }
  if (json is! Map<String, Object?>) {
    throw UnsupportedEnvelopeException('not a JSON object');
  }
  if (json['v'] != 1) {
    throw UnsupportedEnvelopeException('unknown version ${json['v']}');
  }
  if (json['atSign'] != atSign) {
    throw EnvelopeAtSignMismatchException(
        'sealed for ${json['atSign']}, opened for $atSign');
  }
  return switch (json) {
    {
      'content': {'alg': 'A256GCM', 'iv': String iv, 'ct': String ct},
      'unlocks': List<Object?> unlocks,
    } =>
      (_sealed(iv, ct), [for (final u in unlocks) _parseUnlock(u)]),
    _ => throw UnsupportedEnvelopeException(
        'unknown content algorithm or malformed content/unlocks'),
  };
}

_Unlock _parseUnlock(Object? unlock) => switch (unlock) {
      {
        'kind': 'prf',
        'kdf': {'alg': _hkdfAlg, 'salt': String salt},
        'wrap': {'iv': String iv, 'ct': String ct},
      } =>
        (kind: 'prf', salt: _b64(salt), params: null, wrap: _sealed(iv, ct)),
      {
        'kind': 'passphrase',
        'kdf': {
          'alg': String alg,
          'salt': String salt,
          'params': Map<String, Object?> params,
        },
        'wrap': {'iv': String iv, 'ct': String ct},
      }
          when params['alg'] == alg =>
        (
          kind: 'passphrase',
          salt: _b64(salt),
          params: _kdfParams(params),
          wrap: _sealed(iv, ct),
        ),
      {'kind': final kind} => throw UnsupportedEnvelopeException(
          'unknown or malformed unlock of kind $kind'),
      _ => throw UnsupportedEnvelopeException('malformed unlock'),
    };

KdfParams _kdfParams(Map<String, Object?> json) {
  try {
    return KdfParams.fromJson(json);
  } on UnsupportedKdfException catch (e) {
    throw UnsupportedEnvelopeException(e.message);
  }
}

_Sealed _sealed(String iv, String ct) => (iv: _b64(iv), ct: _b64(ct));

Uint8List _b64(String value) {
  try {
    return base64Decode(value);
  } on FormatException {
    throw UnsupportedEnvelopeException('not base64: $value');
  }
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}
