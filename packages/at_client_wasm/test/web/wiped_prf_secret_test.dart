@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client_wasm/src/keys/web_crypto_passkey.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  PrfSecret secret() =>
      PrfSecret(Uint8List.fromList(List.generate(32, (i) => i + 1)));

  /// The page's SubtleCrypto behind a wrapper that notes each importKey call.
  ({SubtleCrypto subtle, JSArray<JSString> calls}) countingSubtle() {
    final calls = JSArray<JSString>();
    final make = globalContext.callMethod<JSFunction>(
        'Function'.toJS,
        'subtle'.toJS,
        'calls'.toJS,
        'return new Proxy(subtle, { get(target, name) {'
                ' const value = target[name];'
                ' if (typeof value !== "function") return value;'
                ' return (...args) => { calls.push(String(name));'
                ' return value.apply(target, args); }; } });'
            .toJS);
    final subtle =
        make.callAsFunction(null, window.crypto.subtle, calls) as SubtleCrypto;
    return (subtle: subtle, calls: calls);
  }

  test('the counting SubtleCrypto sees a derivation from a live secret',
      () async {
    final counting = countingSubtle();
    await WebCryptoKeyDeriver(subtle: counting.subtle)
        .derive(secret(), '@alice');
    expect(counting.calls.toDart.map((c) => c.toDart), contains('importKey'));
  });

  test('A wiped PRF secret cannot be derived from', () async {
    final counting = countingSubtle();
    final wiped = secret()..wipe();
    await expectLater(
        WebCryptoKeyDeriver(subtle: counting.subtle).derive(wiped, '@alice'),
        throwsStateError);
    expect(counting.calls.toDart, isEmpty);
  });
}
