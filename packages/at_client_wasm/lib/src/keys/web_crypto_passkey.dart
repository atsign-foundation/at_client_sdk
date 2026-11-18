import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_commons/atsign.dart';
import 'package:web/web.dart';

import 'dom_exception_name.dart';

const _hkdfBits = 256;
const _tagBits = 128;

/// The `DOMException` name WebCrypto rejects an AES-GCM decrypt with when the
/// tag does not verify.
const _failedTagCheck = 'OperationError';

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
/// encrypted bytes followed by the 16-byte tag. A record whose tag check fails
/// throws a [PasskeyRecordAuthenticationException]; any other rejection from
/// WebCrypto propagates as itself.
class WebCryptoRecordSealer implements RecordSealer {
  /// A sealer over [key], run on [subtle].
  WebCryptoRecordSealer(this._subtle, this._key);

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
      if (domExceptionName(e) == _failedTagCheck) {
        throw PasskeyRecordAuthenticationException();
      }
      rethrow;
    }
    return _bytesOf(plain);
  }

  @override
  void close() => _key = null;
}

/// A [PasskeyKeyDeriver] over WebCrypto HKDF-SHA256 with an empty salt and
/// the info `<label>|<atSign>`.
///
/// The PRF output is imported as a non-extractable HKDF key; the record id,
/// namespace and auth seed are read out as bytes, and the sealing key is
/// derived straight into a non-extractable AES-GCM handle, so its bytes never
/// reach Dart.
class WebCryptoKeyDeriver implements PasskeyKeyDeriver {
  /// A deriver on [subtle], by default the page's `crypto.subtle`.
  WebCryptoKeyDeriver({SubtleCrypto? subtle})
      : _subtle = subtle ?? window.crypto.subtle;

  final SubtleCrypto _subtle;

  JSObject _hkdf(String label, String atSign) => _params({
        'name': 'HKDF'.toJS,
        'hash': 'SHA-256'.toJS,
        'salt': Uint8List(0).toJS,
        'info': Uint8List.fromList(utf8.encode('$label|$atSign')).toJS,
      });

  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) async {
    final bytes = Uint8List.fromList(prf.output);
    final jsPrf = bytes.toJS;
    final String canonical;
    final CryptoKey master;
    try {
      canonical = atSign.toAtsign();
      master = await _subtle
          .importKey('raw', jsPrf, 'HKDF'.toJS, false,
              _usages(['deriveBits', 'deriveKey']))
          .toDart;
    } finally {
      jsPrf.callMethod('fill'.toJS, 0.toJS);
      bytes.fillRange(0, bytes.length, 0);
      prf.wipe();
    }

    Future<Uint8List> bits(String label) async => _bytesOf(await _subtle
        .deriveBits(_hkdf(label, canonical), master, _hkdfBits)
        .toDart);
    Future<String> hexOf(String label) async {
      final bytes = await bits(label);
      try {
        return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }

    final lookupHex = await hexOf(recordIdLabel);
    final ns = await hexOf(recordNsLabel);
    final authSeed = await bits(recordAuthSeedLabel);
    try {
      final sealKey = await _subtle
          .deriveKey(
              _hkdf(recordSealLabel, canonical),
              master,
              _params({'name': 'AES-GCM'.toJS, 'length': 256.toJS}),
              false,
              _usages(['encrypt', 'decrypt']))
          .toDart as CryptoKey;
      return (
        lookupHex: lookupHex,
        ns: ns,
        authSeed: authSeed,
        sealer: WebCryptoRecordSealer(_subtle, sealKey) as RecordSealer,
      );
    } on Object {
      authSeed.fillRange(0, authSeed.length, 0);
      rethrow;
    }
  }
}
