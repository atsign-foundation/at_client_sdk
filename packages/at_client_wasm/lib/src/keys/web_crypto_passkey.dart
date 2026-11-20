import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_chops/at_chops.dart' show HkdfSha256;
import 'package:at_commons/atsign.dart';
import 'package:web/web.dart';

import 'dom_exception_name.dart';

const _derivedBytes = 32;
const _tagBits = 128;

/// The `DOMException` name WebCrypto rejects an AES-GCM decrypt with when the
/// record fails to authenticate: its tag does not verify, or it is shorter
/// than the tag.
const _notAuthentic = 'OperationError';

JSObject _params(Map<String, JSAny> fields) {
  final params = JSObject();
  fields.forEach((name, value) => params.setProperty(name.toJS, value));
  return params;
}

JSArray<JSString> _usages(List<String> names) =>
    [for (final name in names) name.toJS].toJS;

/// [buffer]'s bytes as a Dart list of their own; the JS buffer itself is
/// overwritten with zeroes once copied, whether or not `toDart` hands back a
/// view of it.
Uint8List _bytesOf(JSAny? buffer) {
  final jsBuffer = buffer as JSArrayBuffer;
  final copy = Uint8List.fromList(jsBuffer.toDart.asUint8List());
  final jsView = (globalContext['Uint8Array'] as JSFunction)
      .callAsConstructor<JSObject>(jsBuffer);
  jsView.callMethod('fill'.toJS, 0.toJS);
  return copy;
}

/// A [RecordSealer] over a non-extractable WebCrypto AES-GCM-256 key.
///
/// The key is a handle the page cannot read back. A ciphertext is the
/// encrypted bytes followed by the 16-byte tag. A record that fails to
/// authenticate, because its tag does not verify or it is shorter than the
/// tag, throws a [PasskeyRecordAuthenticationException]; any other rejection
/// from WebCrypto propagates as itself.
class WebCryptoRecordSealer implements RecordSealer {
  /// A sealer over [key], run on [subtle].
  WebCryptoRecordSealer(this._subtle, this._key);

  /// A sealer over [keyBytes], imported on [subtle] as a non-extractable
  /// AES-GCM key whose only usages are encrypt and decrypt.
  ///
  /// Overwrites [keyBytes], and the JS buffer WebCrypto reads them from, with
  /// zeroes once the import settles, whether or not it succeeded.
  static Future<WebCryptoRecordSealer> importKey(
      SubtleCrypto subtle, Uint8List keyBytes) async {
    final jsKey = keyBytes.toJS;
    try {
      final key = await subtle
          .importKey('raw', jsKey, 'AES-GCM'.toJS, false,
              _usages(['encrypt', 'decrypt']))
          .toDart;
      return WebCryptoRecordSealer(subtle, key);
    } finally {
      jsKey.callMethod('fill'.toJS, 0.toJS);
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  final SubtleCrypto _subtle;
  CryptoKey? _key;

  JSObject _algorithm(Uint8List iv, List<int> aad) => _params({
        'name': 'AES-GCM'.toJS,
        'iv': Uint8List.fromList(iv).toJS,
        'additionalData': Uint8List.fromList(aad).toJS,
        'tagLength': _tagBits.toJS,
      });

  CryptoKey get _live =>
      _key ?? (throw StateError('the record sealer is closed'));

  @override
  Future<Uint8List> seal(
      Uint8List iv, List<int> plaintext, List<int> aad) async {
    final input = Uint8List.fromList(plaintext);
    final jsInput = input.toJS;
    try {
      return _bytesOf(
          await _subtle.encrypt(_algorithm(iv, aad), _live, jsInput).toDart);
    } finally {
      jsInput.callMethod('fill'.toJS, 0.toJS);
      input.fillRange(0, input.length, 0);
    }
  }

  @override
  Future<Uint8List> open(
      Uint8List iv, Uint8List ciphertext, List<int> aad) async {
    final key = _live;
    final JSAny? plain;
    try {
      plain = await _subtle
          .decrypt(_algorithm(iv, aad), key, ciphertext.toJS)
          .toDart;
    } catch (e) {
      if (domExceptionName(e) == _notAuthentic) {
        throw PasskeyRecordAuthenticationException();
      }
      rethrow;
    }
    return _bytesOf(plain);
  }

  @override
  void close() => _key = null;
}

/// [bytes] as lowercase hex; [bytes] are overwritten with zeroes once read.
String _wipedHex(Uint8List bytes) {
  try {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}

/// A [PasskeyKeyDeriver] over at_chops' [HkdfSha256] with an empty salt and
/// the info `<label>|<canonical atSign>`.
///
/// One extract of the PRF output is expanded to the 32-byte record id,
/// namespace, auth seed and seal key. Of the buffers the deriver holds, it
/// overwrites with zeroes the PRF output and the extracted key on every exit,
/// the record id and namespace once read as hex, and the seal key through
/// [WebCryptoRecordSealer.importKey]; it returns the auth seed's buffer, and
/// zeroes it only when the import fails. The copies HkdfSha256 makes while
/// computing these bytes, the seal key's among them, stay in Dart memory
/// until they are garbage collected.
class WebCryptoKeyDeriver implements PasskeyKeyDeriver {
  /// A deriver that imports the seal key on [subtle], by default the page's
  /// `crypto.subtle`, and expands with [expand], by default at_chops'
  /// [HkdfSha256.expand].
  WebCryptoKeyDeriver(
      {SubtleCrypto? subtle,
      Uint8List Function(Uint8List prk, {Uint8List? info, required int length})?
          expand})
      : _subtle = subtle ?? window.crypto.subtle,
        _expand = expand ?? HkdfSha256.expand;

  final SubtleCrypto _subtle;
  final Uint8List Function(Uint8List prk,
      {Uint8List? info, required int length}) _expand;

  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) async {
    final String lookupHex;
    final String ns;
    final Uint8List authSeed;
    final Uint8List sealKey;
    try {
      final canonical = atSign.toAtsign();
      final prk = HkdfSha256.extract(prf.output, salt: Uint8List(0));
      try {
        Uint8List expand(String label) => _expand(prk,
            info: utf8.encode('$label|$canonical'), length: _derivedBytes);
        lookupHex = _wipedHex(expand(recordIdLabel));
        ns = _wipedHex(expand(recordNsLabel));
        authSeed = expand(recordAuthSeedLabel);
        sealKey = expand(recordSealLabel);
      } finally {
        prk.fillRange(0, prk.length, 0);
      }
    } finally {
      prf.wipe();
    }
    try {
      final RecordSealer sealer =
          await WebCryptoRecordSealer.importKey(_subtle, sealKey);
      return (lookupHex: lookupHex, ns: ns, authSeed: authSeed, sealer: sealer);
    } on Object {
      authSeed.fillRange(0, authSeed.length, 0);
      rethrow;
    }
  }
}
