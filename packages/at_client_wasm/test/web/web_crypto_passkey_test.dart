@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client_wasm/src/keys/dom_exception_name.dart';
import 'package:at_client_wasm/src/keys/web_crypto_passkey.dart';
import 'package:at_commons/at_commons.dart' show InvalidAtSignException;
import 'package:test/test.dart';
import 'package:web/web.dart';

/// A record sealed under the @alice key derived from the PRF output 0..31,
/// with iv 0..11, by a raw-bytes sealer.
const _aliceRecord =
    '{"v":2,"alg":"A256GCM","kdf":"HKDF-SHA256","typ":"atkeys",'
    '"iv":"AAECAwQFBgcICQoL","ct":"f3rZoUxXXO/L6zydQWw5shl+FShvyys3jiWO87nV9/Ld76zW/yGNcsCxxQsU13TMQ+vh3FlObhquNMt2lCtEo/UDGN5tDs6/jwEWrGHR81Oog/N0Tip3bFpXpqN3KO8YofwHq34Me7Kx9IvF79PXcqMYs1M="}';

/// `{"selfEncryptionKey":"self"}` sealed by a raw-bytes sealer under the @bob
/// key, with iv 0..11 and the aad `aad`.
const _bobSealed =
    'OuBPH3jARbJUY1QXfqI7/iOyZJaxBd03BlkkrMVVS2EpGWIa2hSQ90BIclc=';

/// The @alice seal key (`at_auth/custody/kek/v1|@alice`) the derivation
/// vectors give for the PRF output 0..31.
const _aliceSealKey =
    '926e411c042496d783b7c01687562cc76b11cfe6fd683ddeeb285b7adfab83ce';

JSObject _params(Map<String, JSAny> fields) {
  final params = JSObject();
  fields.forEach((name, value) => params.setProperty(name.toJS, value));
  return params;
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

bool _allZero(JSAny? buffer) {
  final view = buffer.isA<JSArrayBuffer>()
      ? (buffer as JSArrayBuffer).toDart.asUint8List()
      : (buffer as JSUint8Array).toDart;
  return view.every((b) => b == 0);
}

/// One `importKey` call seen by [_importSpy]: the key data it was handed, a
/// copy of those bytes taken at the call, and the key it resolved to.
class _Import {
  _Import(this.data, this.bytesAtCall);

  final JSAny? data;
  final List<int> bytesAtCall;
  CryptoKey? key;
}

/// A subtle that forwards `importKey`, `encrypt` and `decrypt` to the page's
/// and records each `importKey` call in [calls].
SubtleCrypto _importSpy(List<_Import> calls) {
  final real = window.crypto.subtle as JSObject;
  JSAny? forward(String method, List<JSAny?> args) =>
      real.callMethodVarArgs<JSAny?>(method.toJS, args);
  return (JSObject()
    ..setProperty(
        'importKey'.toJS,
        ((JSAny? f, JSAny? d, JSAny? a, JSAny? e, JSAny? u) {
          final call = _Import(d, List.of((d as JSUint8Array).toDart));
          calls.add(call);
          return (forward('importKey', [f, d, a, e, u]) as JSObject)
              .callMethod<JSAny?>(
                  'then'.toJS,
                  ((JSAny? key) {
                    call.key = key as CryptoKey;
                    return key;
                  }).toJS);
        }).toJS)
    ..setProperty('encrypt'.toJS,
        ((JSAny? a, JSAny? k, JSAny? d) => forward('encrypt', [a, k, d])).toJS)
    ..setProperty(
        'decrypt'.toJS,
        ((JSAny? a, JSAny? k, JSAny? d) => forward('decrypt', [a, k, d]))
            .toJS)) as SubtleCrypto;
}

/// Catalogue: features/at_client_wasm/passkey_derivation.feature
void main() {
  final deriver = WebCryptoKeyDeriver();
  Uint8List prfBytes() => Uint8List.fromList(List.generate(32, (i) => i));
  PrfSecret prf() => PrfSecret(prfBytes());
  final iv = Uint8List.fromList(List.generate(12, (i) => i));

  test("The browser's derivation matches the vectors", () async {
    final alice = await deriver.derive(prf(), '@alice');
    final bob = await deriver.derive(prf(), '@bob');
    expect(alice.lookupHex,
        '562dd8ceae1d04851c10847fea609250dc0c74d92af520a4ab96565bfea6c4b6',
        reason: 'the @alice lookup id vector');
    expect(alice.ns,
        '10781e72da94f814194f90c4c40d75d7b0b029d06253d40a610b0ad977b2d620',
        reason: 'the @alice namespace vector');
    expect(_hex(alice.authSeed),
        'b0e85850ef5407a914408bc6ccdc6a32baeb6446127275414199179a2cf79fc6',
        reason: 'the @alice auth seed vector');
    expect(bob.lookupHex,
        'ac8dabc6a3f6c618517f650bf7de7f34d1f8bc604c100768d9e3418aaa56b5fb',
        reason: 'the @bob lookup id vector');
    expect(bob.ns,
        '50e50b134d591ebbf53d1ebe9d8cbde9654259659520783786cc298dea3f7e07',
        reason: 'the @bob namespace vector');

    final record = jsonDecode(_aliceRecord) as Map<String, dynamic>;
    final aad = utf8.encode(jsonEncode({
      'alg': 'A256GCM',
      'iv': record['iv'],
      'kdf': 'HKDF-SHA256',
      'typ': 'atkeys',
      'v': 2
    }));
    Future<String> opened(Future<Uint8List> open) =>
        open.then((plain) => utf8.decode(plain),
            onError: (Object e) => 'refused: $e');
    final alicePlain = await opened(
        alice.sealer.open(iv, base64Decode(record['ct'] as String), aad));
    expect(alicePlain, contains('"selfEncryptionKey":"self"'),
        reason: 'the @alice record vector opens with the derived seal key');
    final bobPlain = await opened(
        bob.sealer.open(iv, base64Decode(_bobSealed), utf8.encode('aad')));
    expect(bobPlain, '{"selfEncryptionKey":"self"}',
        reason: 'the @bob sealed vector opens with the derived seal key');
  });

  test("The seal key can't be exported once derived", () async {
    final calls = <_Import>[];
    final alice = await WebCryptoKeyDeriver(subtle: _importSpy(calls))
        .derive(prf(), '@alice');
    expect(calls, hasLength(1),
        reason: 'the seal key is the one key the deriver imports');
    final key = calls.single.key!;
    final real = window.crypto.subtle;

    final sealed =
        await alice.sealer.seal(iv, utf8.encode('hello'), utf8.encode('a'));
    final opened = await real
        .decrypt(
            _params({
              'name': 'AES-GCM'.toJS,
              'iv': Uint8List.fromList(iv).toJS,
              'additionalData': utf8.encode('a').toJS,
              'tagLength': 128.toJS,
            }),
            key,
            sealed.toJS)
        .toDart as JSArrayBuffer;
    expect(utf8.decode(opened.toDart.asUint8List()), 'hello',
        reason: 'the imported key is the one the sealer seals with');

    for (final format in ['raw', 'jwk']) {
      Object? refusal;
      try {
        await real.exportKey(format, key).toDart;
      } catch (e) {
        refusal = e;
      }
      expect(refusal, isNotNull,
          reason: 'exportKey($format) of the seal key must be refused');
      expect(domExceptionName(refusal!), 'InvalidAccessError',
          reason: 'exportKey($format) is refused because the key is '
              'not extractable');
    }
    expect(key.extractable, isFalse,
        reason: 'the seal key must be imported non-extractable');
    expect(
        (key.usages as JSArray<JSString>).toDart.map((u) => u.toDart).toList(),
        unorderedEquals(['encrypt', 'decrypt']),
        reason: "the seal key's only usages are encrypt and decrypt");
    final algorithm = key.algorithm;
    expect(algorithm.getProperty<JSString>('name'.toJS).toDart, 'AES-GCM',
        reason: 'the seal key is an AES-GCM key');
    expect(algorithm.getProperty<JSNumber>('length'.toJS).toDartInt, 256,
        reason: 'the seal key is 256 bits');
  });

  test("The seal key's bytes are overwritten once imported", () async {
    final calls = <_Import>[];
    await WebCryptoKeyDeriver(subtle: _importSpy(calls))
        .derive(prf(), '@alice');
    expect(calls, hasLength(1),
        reason: 'the seal key is the one key the deriver imports');
    expect(_hex(calls.single.bytesAtCall), _aliceSealKey,
        reason: 'the bytes handed to importKey are the @alice seal key of '
            'the derivation vectors');
    expect(_allZero(calls.single.data), isTrue,
        reason: 'the seal key bytes handed to WebCrypto must be zeroes once '
            'imported');
  });

  group('WebCryptoKeyDeriver', () {
    test('every spelling of the atSign derives the same values', () async {
      final canonical = await deriver.derive(prf(), '@alice');
      final variant = await deriver.derive(prf(), 'ALICE');
      expect(variant.lookupHex, canonical.lookupHex);
      expect(variant.ns, canonical.ns);
      expect(variant.authSeed, canonical.authSeed);
    });

    test('the PRF bytes are zeroed once derived', () async {
      final bytes = prfBytes();
      await deriver.derive(PrfSecret(bytes), '@alice');
      expect(bytes, everyElement(0),
          reason: 'the PRF bytes must be zeroes once derived');
    });

    test('the PRF bytes are zeroed when the atSign is invalid', () async {
      final bytes = prfBytes();
      await expectLater(deriver.derive(PrfSecret(bytes), '@al ice'),
          throwsA(isA<InvalidAtSignException>()));
      expect(bytes, everyElement(0),
          reason: 'an invalid atSign must not leave the PRF bytes unwiped');
    });

    test('the @alice sealer does not open a @bob record', () async {
      final alice = await deriver.derive(prf(), '@alice');
      await expectLater(
          alice.sealer.open(iv, base64Decode(_bobSealed), utf8.encode('aad')),
          throwsA(isA<PasskeyRecordAuthenticationException>()));
    });

    test('a bytes-sealed record is the ciphertext this sealer produces',
        () async {
      final bob = await deriver.derive(prf(), '@bob');
      final sealed = await bob.sealer.seal(
          iv, utf8.encode('{"selfEncryptionKey":"self"}'), utf8.encode('aad'));
      expect(base64Encode(sealed), _bobSealed);
    });
  });

  group('WebCryptoRecordSealer.importKey', () {
    test('overwrites the key bytes it was given once imported', () async {
      final keyBytes = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final calls = <_Import>[];
      await WebCryptoRecordSealer.importKey(_importSpy(calls), keyBytes);
      expect(keyBytes, everyElement(0),
          reason: 'the Dart key bytes must be zeroes once imported');
      expect(_allZero(calls.single.data), isTrue,
          reason: 'the JS key bytes must be zeroes once imported');
    });

    test('overwrites the key bytes it was given when the import fails',
        () async {
      final keyBytes = Uint8List.fromList(List.generate(31, (i) => i + 1));
      final calls = <_Import>[];
      Object? refusal;
      try {
        await WebCryptoRecordSealer.importKey(_importSpy(calls), keyBytes);
      } catch (e) {
        refusal = e;
      }
      expect(domExceptionName(refusal ?? Object()), 'DataError',
          reason: 'WebCrypto refuses a 31-byte AES key');
      expect(keyBytes, everyElement(0),
          reason: 'the Dart key bytes must be zeroes after a failed import');
      expect(_allZero(calls.single.data), isTrue,
          reason: 'the JS key bytes must be zeroes after a failed import');
    });
  });

  group('the buffers WebCrypto sees', () {
    Future<CryptoKey> aesKey() => window.crypto.subtle
        .generateKey(
            _params({'name': 'AES-GCM'.toJS, 'length': 256.toJS}),
            false,
            [
              for (final u in ['encrypt', 'decrypt']) u.toJS
            ].toJS)
        .toDart
        .then((k) => k as CryptoKey);

    /// A subtle that forwards to the real one and hands each argument list
    /// and result of [method] to [seen].
    SubtleCrypto spying(
        String method, void Function(List<JSAny?> args, JSAny? result) seen) {
      final real = window.crypto.subtle as JSObject;
      return (JSObject()
        ..setProperty(
            method.toJS,
            ((JSAny? a, JSAny? k, JSAny? d) =>
                (real.callMethodVarArgs<JSAny?>(method.toJS, [a, k, d])
                        as JSPromise)
                    .toDart
                    .then((r) {
                  seen([a, k, d], r);
                  return r;
                }).toJS).toJS)) as SubtleCrypto;
    }

    test('the plaintext given to encrypt is zeroed once sealed', () async {
      JSAny? given;
      final s = WebCryptoRecordSealer(
          spying('encrypt', (args, _) => given = args[2]), await aesKey());
      await s.seal(iv, utf8.encode('secret'), utf8.encode('a'));

      expect(given, isNotNull);
      expect(_allZero(given), isTrue);
    });

    test('the plaintext decrypt returns is zeroed once opened', () async {
      final key = await aesKey();
      final sealed = await WebCryptoRecordSealer(window.crypto.subtle, key)
          .seal(iv, utf8.encode('secret'), utf8.encode('a'));
      JSAny? returned;
      final s = WebCryptoRecordSealer(
          spying('decrypt', (_, result) => returned = result), key);
      final plain = await s.open(iv, sealed, utf8.encode('a'));

      expect(utf8.decode(plain), 'secret');
      expect(returned, isNotNull);
      expect(_allZero(returned), isTrue);
    });
  });

  group('WebCryptoRecordSealer', () {
    Future<RecordSealer> sealer() async =>
        (await deriver.derive(prf(), '@alice')).sealer;

    test('a sealed record opens to the plaintext', () async {
      final s = await sealer();
      final sealed = await s.seal(iv, utf8.encode('hello'), utf8.encode('a'));
      expect(sealed, hasLength(5 + 16));
      expect(utf8.decode(await s.open(iv, sealed, utf8.encode('a'))), 'hello');
    });

    test('a different aad fails with an authentication exception', () async {
      final s = await sealer();
      final sealed = await s.seal(iv, utf8.encode('hello'), utf8.encode('a'));
      await expectLater(s.open(iv, sealed, utf8.encode('b')),
          throwsA(isA<PasskeyRecordAuthenticationException>()));
    });

    test('a changed ciphertext fails with an authentication exception',
        () async {
      final s = await sealer();
      final sealed = await s.seal(iv, utf8.encode('hello'), utf8.encode('a'));
      sealed[0] ^= 1;
      await expectLater(s.open(iv, sealed, utf8.encode('a')),
          throwsA(isA<PasskeyRecordAuthenticationException>()));
    });

    test('a rejection other than a failed tag check propagates as itself',
        () async {
      final encryptOnly = await window.crypto.subtle
          .generateKey(_params({'name': 'AES-GCM'.toJS, 'length': 256.toJS}),
              false, ['encrypt'.toJS].toJS)
          .toDart as CryptoKey;
      final s = WebCryptoRecordSealer(window.crypto.subtle, encryptOnly);
      final sealed = await s.seal(iv, utf8.encode('hello'), utf8.encode('a'));
      Object? rejection;
      try {
        await s.open(iv, sealed, utf8.encode('a'));
      } catch (e) {
        rejection = e;
      }
      expect(rejection, isNotNull,
          reason: 'a key without decrypt usage must not open a record');
      expect(rejection, isNot(isA<PasskeyRecordAuthenticationException>()),
          reason: 'only a failed tag check is an authentication failure');
      expect(domExceptionName(rejection!), 'InvalidAccessError',
          reason: 'the WebCrypto rejection must reach the caller as itself');
    });

    test('use after close throws a StateError', () async {
      final s = await sealer();
      s.close();
      await expectLater(
          s.seal(iv, utf8.encode('x'), const []), throwsA(isA<StateError>()));
      await expectLater(
          s.open(iv, Uint8List(16), const []), throwsA(isA<StateError>()));
    });
  });
}
