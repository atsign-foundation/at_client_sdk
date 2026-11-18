@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client_wasm/src/keys/web_crypto_passkey.dart';
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

JSObject _params(Map<String, JSAny> fields) {
  final params = JSObject();
  fields.forEach((name, value) => params.setProperty(name.toJS, value));
  return params;
}

void main() {
  final deriver = WebCryptoKeyDeriver();
  PrfSecret prf() => PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));
  String hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  final iv = Uint8List.fromList(List.generate(12, (i) => i));

  group('WebCryptoKeyDeriver', () {
    test('lookupHex and ns match the pinned vectors for @alice and @bob',
        () async {
      final alice = await deriver.derive(prf(), '@alice');
      final bob = await deriver.derive(prf(), '@bob');
      expect(alice.lookupHex,
          '562dd8ceae1d04851c10847fea609250dc0c74d92af520a4ab96565bfea6c4b6');
      expect(alice.ns,
          '10781e72da94f814194f90c4c40d75d7b0b029d06253d40a610b0ad977b2d620');
      expect(bob.lookupHex,
          'ac8dabc6a3f6c618517f650bf7de7f34d1f8bc604c100768d9e3418aaa56b5fb');
      expect(bob.ns,
          '50e50b134d591ebbf53d1ebe9d8cbde9654259659520783786cc298dea3f7e07');
    });

    test('the auth seed matches the pinned vector for @alice', () async {
      final alice = await deriver.derive(prf(), '@alice');
      expect(hex(alice.authSeed),
          'b0e85850ef5407a914408bc6ccdc6a32baeb6446127275414199179a2cf79fc6');
    });

    test('every spelling of the atSign derives the same values', () async {
      final canonical = await deriver.derive(prf(), '@alice');
      final variant = await deriver.derive(prf(), 'ALICE');
      expect(variant.lookupHex, canonical.lookupHex);
      expect(variant.ns, canonical.ns);
      expect(variant.authSeed, canonical.authSeed);
    });

    test('the PRF bytes are zeroed once derived', () async {
      final secret = prf();
      final bytes = secret.output;
      await deriver.derive(secret, '@alice');
      expect(bytes, everyElement(0));
    });

    test('the sealer opens a record sealed by a raw-bytes sealer', () async {
      final alice = await deriver.derive(prf(), '@alice');
      final record = jsonDecode(_aliceRecord) as Map<String, dynamic>;
      final aad = utf8.encode(jsonEncode({
        'alg': 'A256GCM',
        'iv': record['iv'],
        'kdf': 'HKDF-SHA256',
        'typ': 'atkeys',
        'v': 2
      }));
      final plain = await alice.sealer
          .open(iv, base64Decode(record['ct'] as String), aad);
      expect(jsonDecode(utf8.decode(plain))['selfEncryptionKey'], 'self');
    });

    test('the @bob sealer opens a @bob record and the @alice sealer does not',
        () async {
      final alice = await deriver.derive(prf(), '@alice');
      final bob = await deriver.derive(prf(), '@bob');
      final aad = utf8.encode('aad');
      final plain = await bob.sealer.open(iv, base64Decode(_bobSealed), aad);
      expect(utf8.decode(plain), '{"selfEncryptionKey":"self"}');
      await expectLater(alice.sealer.open(iv, base64Decode(_bobSealed), aad),
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

  group('the derived sealing key', () {
    test(
        'is not extractable, carries exactly encrypt and decrypt, and cannot '
        'be exported', () async {
      final real = window.crypto.subtle;
      final keys = <CryptoKey>[];
      JSAny? forward(String name, List<JSAny?> args) =>
          (real as JSObject).callMethodVarArgs<JSAny?>(name.toJS, args);
      final spy = JSObject()
        ..setProperty(
            'importKey'.toJS,
            ((JSAny? f, JSAny? d, JSAny? a, JSAny? e, JSAny? u) =>
                forward('importKey', [f, d, a, e, u])).toJS)
        ..setProperty(
            'deriveBits'.toJS,
            ((JSAny? a, JSAny? k, JSAny? l) => forward('deriveBits', [a, k, l]))
                .toJS)
        ..setProperty(
            'deriveKey'.toJS,
            ((JSAny? a, JSAny? k, JSAny? t, JSAny? e, JSAny? u) =>
                (forward('deriveKey', [a, k, t, e, u]) as JSPromise)
                    .toDart
                    .then((key) {
                  keys.add(key as CryptoKey);
                  return key;
                }).toJS).toJS);
      await WebCryptoKeyDeriver(subtle: spy as SubtleCrypto)
          .derive(prf(), '@alice');

      expect(keys, hasLength(1));
      final key = keys.single;
      expect(key.extractable, isFalse);
      expect(
          (key.usages as JSArray<JSString>).toDart.map((u) => u.toDart).toSet(),
          {'encrypt', 'decrypt'});
      expect((key.usages as JSArray<JSString>).length, 2);
      await expectLater(real.exportKey('raw', key).toDart, throwsA(anything));
    });
  });

  group('the HKDF master key', () {
    test('is imported as non-extractable and cannot be exported', () async {
      final real = window.crypto.subtle;
      final imports = <({String format, JSAny? extractable, CryptoKey key})>[];
      JSAny? forward(String name, List<JSAny?> args) =>
          (real as JSObject).callMethodVarArgs<JSAny?>(name.toJS, args);
      final spy = JSObject()
        ..setProperty(
            'importKey'.toJS,
            ((JSAny? f, JSAny? d, JSAny? a, JSAny? e, JSAny? u) =>
                (forward('importKey', [f, d, a, e, u]) as JSPromise)
                    .toDart
                    .then((key) {
                  imports.add((
                    format: (f as JSString).toDart,
                    extractable: e,
                    key: key as CryptoKey
                  ));
                  return key;
                }).toJS).toJS)
        ..setProperty(
            'deriveBits'.toJS,
            ((JSAny? a, JSAny? k, JSAny? l) => forward('deriveBits', [a, k, l]))
                .toJS)
        ..setProperty(
            'deriveKey'.toJS,
            ((JSAny? a, JSAny? k, JSAny? t, JSAny? e, JSAny? u) =>
                forward('deriveKey', [a, k, t, e, u])).toJS);
      await WebCryptoKeyDeriver(subtle: spy as SubtleCrypto)
          .derive(prf(), '@alice');

      expect(imports, hasLength(1));
      expect(imports.single.format, 'raw');
      expect((imports.single.extractable as JSBoolean).toDart, isFalse);
      expect(imports.single.key.extractable, isFalse);
      await expectLater(
          real.exportKey('raw', imports.single.key).toDart, throwsA(anything));
    });

    test('the sealing key cannot be exported as a JWK', () async {
      final keys = <CryptoKey>[];
      final real = window.crypto.subtle;
      final spy = JSObject()
        ..setProperty(
            'importKey'.toJS,
            ((JSAny? f, JSAny? d, JSAny? a, JSAny? e, JSAny? u) =>
                (real as JSObject).callMethodVarArgs<JSAny?>(
                    'importKey'.toJS, [f, d, a, e, u])).toJS)
        ..setProperty(
            'deriveBits'.toJS,
            ((JSAny? a, JSAny? k, JSAny? l) => (real as JSObject)
                .callMethodVarArgs<JSAny?>('deriveBits'.toJS, [a, k, l])).toJS)
        ..setProperty(
            'deriveKey'.toJS,
            ((JSAny? a, JSAny? k, JSAny? t, JSAny? e, JSAny? u) =>
                ((real as JSObject).callMethodVarArgs<JSAny?>(
                        'deriveKey'.toJS, [a, k, t, e, u]) as JSPromise)
                    .toDart
                    .then((key) {
                  keys.add(key as CryptoKey);
                  return key;
                }).toJS).toJS);
      await WebCryptoKeyDeriver(subtle: spy as SubtleCrypto)
          .derive(prf(), '@alice');

      await expectLater(
          real.exportKey('jwk', keys.single).toDart, throwsA(anything));
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

    bool allZero(JSAny? buffer) {
      final view = buffer.isA<JSArrayBuffer>()
          ? (buffer as JSArrayBuffer).toDart.asUint8List()
          : (buffer as JSUint8Array).toDart;
      return view.every((b) => b == 0);
    }

    test('every buffer deriveBits returns is zeroed once copied', () async {
      final real = window.crypto.subtle as JSObject;
      final results = <JSAny?>[];
      final spy = JSObject()
        ..setProperty(
            'importKey'.toJS,
            ((JSAny? f, JSAny? d, JSAny? a, JSAny? e, JSAny? u) => real
                .callMethodVarArgs<JSAny?>(
                    'importKey'.toJS, [f, d, a, e, u])).toJS)
        ..setProperty(
            'deriveKey'.toJS,
            ((JSAny? a, JSAny? k, JSAny? t, JSAny? e, JSAny? u) => real
                .callMethodVarArgs<JSAny?>(
                    'deriveKey'.toJS, [a, k, t, e, u])).toJS)
        ..setProperty(
            'deriveBits'.toJS,
            ((JSAny? a, JSAny? k, JSAny? l) =>
                (real.callMethodVarArgs<JSAny?>('deriveBits'.toJS, [a, k, l])
                        as JSPromise)
                    .toDart
                    .then((r) {
                  results.add(r);
                  return r;
                }).toJS).toJS);
      await WebCryptoKeyDeriver(subtle: spy as SubtleCrypto)
          .derive(prf(), '@alice');

      expect(results, hasLength(3));
      for (final buffer in results) {
        expect(allZero(buffer), isTrue);
      }
    });

    test('the PRF bytes handed to importKey are zeroed once imported',
        () async {
      final real = window.crypto.subtle as JSObject;
      JSAny? given;
      final spy = JSObject()
        ..setProperty(
            'importKey'.toJS,
            ((JSAny? f, JSAny? d, JSAny? a, JSAny? e, JSAny? u) {
              given = d;
              return real
                  .callMethodVarArgs<JSAny?>('importKey'.toJS, [f, d, a, e, u]);
            }).toJS)
        ..setProperty(
            'deriveBits'.toJS,
            ((JSAny? a, JSAny? k, JSAny? l) => real
                .callMethodVarArgs<JSAny?>('deriveBits'.toJS, [a, k, l])).toJS)
        ..setProperty(
            'deriveKey'.toJS,
            ((JSAny? a, JSAny? k, JSAny? t, JSAny? e, JSAny? u) => real
                .callMethodVarArgs<JSAny?>(
                    'deriveKey'.toJS, [a, k, t, e, u])).toJS);
      await WebCryptoKeyDeriver(subtle: spy as SubtleCrypto)
          .derive(prf(), '@alice');

      expect(given, isNotNull);
      expect(allZero(given), isTrue);
    });

    test('the plaintext given to encrypt is zeroed once sealed', () async {
      JSAny? given;
      final s = WebCryptoRecordSealer(
          spying('encrypt', (args, _) => given = args[2]), await aesKey());
      await s.seal(iv, utf8.encode('secret'), utf8.encode('a'));

      expect(given, isNotNull);
      expect(allZero(given), isTrue);
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
      expect(allZero(returned), isTrue);
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
