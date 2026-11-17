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

/// A credential whose extension results are the JSON [results].
PublicKeyCredential _credentialWithResults(String results) {
  final make = globalContext.callMethod<JSFunction>('Function'.toJS,
      'return {getClientExtensionResults() { return $results; }};'.toJS);
  return make.callAsFunction(null) as PublicKeyCredential;
}

void main() {
  group('prfEnabledOf', () {
    test('is null without a PRF extension result', () {
      expect(prfEnabledOf(_credentialWithResults('{}')), isNull);
    });

    test('is true when the extension reports enabled', () {
      expect(prfEnabledOf(_credentialWithResults('{prf: {enabled: true}}')),
          isTrue);
    });

    test('is false when the extension reports not enabled', () {
      expect(prfEnabledOf(_credentialWithResults('{prf: {enabled: false}}')),
          isFalse);
    });

    test('is true when a first result is present', () {
      expect(prfEnabledOf(_credentialWith(Uint8List(32).buffer.toJS)), isTrue);
    });

    test('is null when the extension result says nothing', () {
      expect(prfEnabledOf(_credentialWithResults('{prf: {}}')), isNull);
    });
  });

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

  group('signalUnknownCredential', () {
    late JSAny? original;

    setUp(() => original = globalContext['PublicKeyCredential']);
    tearDown(() => globalContext['PublicKeyCredential'] = original);

    JSObject stubWith(String body) {
      final make = globalContext.callMethod<JSFunction>(
          'Function'.toJS, 'return {calls: [], $body};'.toJS);
      final stub = make.callAsFunction(null) as JSObject;
      globalContext['PublicKeyCredential'] = stub;
      return stub;
    }

    final port = WebPasskeyPort(rpId: 'example.org', rpName: 'Example');
    final id = Uint8List.fromList([251, 255, 0, 1]);

    test('reports the rpId and the base64url credential id', () async {
      final stub = stubWith('signalUnknownCredential(o) {'
          ' this.calls.push(JSON.stringify(o)); return Promise.resolve(); }');
      await port.signalUnknownCredential(id);
      final calls = (stub['calls'] as JSArray).toDart;
      expect(calls.length, 1);
      expect((calls.single as JSString).toDart,
          '{"rpId":"example.org","credentialId":"-_8AAQ"}');
    });

    test('does nothing when the browser has no such call', () async {
      stubWith('x: 1');
      await port.signalUnknownCredential(id);
    });

    test('swallows a rejected signal', () async {
      stubWith('signalUnknownCredential() { return Promise.reject('
          'new Error("refused")); }');
      await port.signalUnknownCredential(id);
    });

    test('swallows a throwing signal', () async {
      stubWith('signalUnknownCredential() { throw new Error("refused"); }');
      await port.signalUnknownCredential(id);
    });
  });
}
