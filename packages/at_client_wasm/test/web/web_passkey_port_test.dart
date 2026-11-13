@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/web_passkey_port.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

/// A credential whose PRF `first` result is [buffer].
PublicKeyCredential _credentialWith(JSArrayBuffer? buffer) {
  final make = globalContext.callMethod<JSFunction>(
      'Function'.toJS,
      'buffer'.toJS,
      'return {getClientExtensionResults() { return {prf: '
              '{results: {first: buffer}}}; }};'
          .toJS);
  return make.callAsFunction(null, buffer) as PublicKeyCredential;
}

void main() {
  group('prfFirstOf', () {
    test('returns the PRF bytes and zeroes the browser buffer', () {
      final bytes = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final buffer = bytes.buffer.toJS;
      final result = prfFirstOf(_credentialWith(buffer));
      expect(result, List.generate(32, (i) => i + 1));
      final view = Uint8List.fromList(buffer.toDart.asUint8List());
      expect(view, everyElement(0));
    });

    test('returns null without a PRF result', () {
      expect(prfFirstOf(_credentialWith(null)), isNull);
    });
  });
}
