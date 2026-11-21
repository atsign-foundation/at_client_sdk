@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart' show passkeyDisplayName;
import 'package:at_client_web/src/keys/web_passkey_port.dart';
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

  group('ceremonies through navigator.credentials', () {
    final container = window.navigator.credentials as JSObject;
    final port = WebPasskeyPort(rpId: 'example.org', rpName: 'Example');
    late JSArray<JSString> calls;

    /// Replaces navigator.credentials.[method] with one that notes what its
    /// options carried and resolves to a credential whose rawId is 9, 8, 7
    /// and whose extension results are the JS object literal [results].
    void stub(String method, String results) {
      final make = globalContext.callMethod<JSFunction>(
          'Function'.toJS,
          'calls'.toJS,
          'return function(o) {'
                  ' const k = o.publicKey;'
                  ' const bytes = (v) => Array.from(ArrayBuffer.isView(v)'
                  ' ? new Uint8Array(v.buffer, v.byteOffset, v.byteLength)'
                  ' : new Uint8Array(v));'
                  ' calls.push(JSON.stringify({'
                  ' rp: k.rp, rpId: k.rpId,'
                  ' user: k.user && {name: k.user.name,'
                  ' displayName: k.user.displayName,'
                  ' idLength: bytes(k.user.id).length},'
                  ' selection: k.authenticatorSelection,'
                  ' userVerification: k.userVerification,'
                  ' allow: k.allowCredentials'
                  ' && k.allowCredentials.map((c) => bytes(c.id)),'
                  ' first: k.extensions.prf.eval'
                  ' && bytes(k.extensions.prf.eval.first)}));'
                  ' return Promise.resolve({'
                  ' rawId: new Uint8Array([9, 8, 7]).buffer,'
                  ' getClientExtensionResults() { return $results; }});'
                  ' };'
              .toJS);
      container[method] = make.callAsFunction(null, calls);
    }

    Map<String, Object?> lastCall() =>
        jsonDecode(calls.toDart.last.toDart) as Map<String, Object?>;

    setUp(() => calls = JSArray<JSString>());
    tearDown(() {
      container.delete('create'.toJS);
      container.delete('get'.toJS);
    });

    test('create returns the rawId and the PRF extension result', () async {
      stub('create', '{prf: {enabled: true}}');
      final creation = await port.create(
          atSign: '@alice',
          enrolledAt: DateTime.utc(2026, 11, 6, 14, 5),
          deviceName: 'Alice Mac');
      expect(calls.toDart, hasLength(1));
      expect(creation.credentialId, [9, 8, 7]);
      expect(creation.prfEnabled, isTrue);
    });

    test(
        'create asks for a discoverable, user-verified passkey named by the '
        'core rule', () async {
      stub('create', '{}');
      final at = DateTime.utc(2026, 11, 6, 14, 5);
      final creation = await port.create(
          atSign: '@alice', enrolledAt: at, deviceName: 'Mac');
      expect(creation.prfEnabled, isNull);
      final call = lastCall();
      expect(call['rp'], {'id': 'example.org', 'name': 'Example'});
      expect(call['user'], {
        'name': '@alice',
        'displayName': passkeyDisplayName(at, 'Mac'),
        'idLength': 64
      });
      expect(call['selection'],
          {'residentKey': 'required', 'userVerification': 'required'});
    });

    test('get returns the rawId and the PRF first result', () async {
      stub('get',
          '{prf: {results: {first: new Uint8Array(32).fill(5).buffer}}}');
      final assertion =
          await port.get(evalInput: Uint8List(32)..fillRange(0, 32, 1));
      expect(calls.toDart, hasLength(1));
      expect(assertion.credentialId, [9, 8, 7]);
      expect(assertion.prfFirst, List.filled(32, 5));
    });

    test(
        'get asks for user verification, narrows to the credential and '
        'evaluates PRF on the input', () async {
      stub('get', '{}');
      final input = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final assertion = await port.get(
          evalInput: input, allowCredential: Uint8List.fromList([4, 5, 6]));
      expect(assertion.prfFirst, isNull);
      final call = lastCall();
      expect(call['rpId'], 'example.org');
      expect(call['userVerification'], 'required');
      expect(call['allow'], [
        [4, 5, 6]
      ]);
      expect(call['first'], input);
    });
  });
}
