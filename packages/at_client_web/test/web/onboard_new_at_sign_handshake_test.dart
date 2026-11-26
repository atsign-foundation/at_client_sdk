// The onboarding path is exercised without an atServer: the entry point takes
// only SessionTransportOptions, which names a real atServer, so the test stops
// once the first connection reaches a bound port and fails its TLS handshake.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client_web/src/keys/indexeddb_store.dart';
import 'package:at_client_web/src/session/session_transport_options.dart';
import 'package:at_client_web/src/session/web_passkey_entry.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

/// The credential id both faked ceremonies return.
const _credentialId = [9, 8, 7];

/// A bound loopback port that destroys every connection it accepts.
///
/// The browser transport only opens `wss://`, so a `WebSocket` to this port
/// fails its TLS handshake at once: an entry point that reaches the atServer
/// stage dials it and no other process can take the port while the test runs.
/// [dialed] completes when the port accepts a connection.
Future<int> _handshakeFailingAtServerPort(Completer<void> dialed) async {
  final fake = spawnHybridUri('tls_handshake_failing_at_server_fake.dart');
  addTearDown(fake.sink.close);
  final replies = StreamIterator<dynamic>(fake.stream);
  await replies.moveNext();
  final port = (replies.current as num).toInt();
  unawaited(() async {
    while (await replies.moveNext()) {
      if (replies.current == 'connection' && !dialed.isCompleted) {
        dialed.complete();
      }
    }
  }());
  return port;
}

/// A `navigator.credentials.[kind]` that records the call and resolves to a
/// credential whose rawId is [_credentialId] and whose extension results are
/// the JS object literal [results].
JSFunction _ceremonyStub(JSArray<JSString> calls, String kind, String results) {
  final make = globalContext.callMethod<JSFunction>(
      'Function'.toJS,
      'calls'.toJS,
      'return function (options) {'
              ' const k = options.publicKey;'
              ' const bytes = (v) => Array.from(ArrayBuffer.isView(v)'
              ' ? new Uint8Array(v.buffer, v.byteOffset, v.byteLength)'
              ' : new Uint8Array(v));'
              ' calls.push(JSON.stringify({'
              '  kind: "$kind",'
              '  rp: k.rp, rpId: k.rpId,'
              '  userName: k.user && k.user.name,'
              '  selection: k.authenticatorSelection,'
              '  userVerification: k.userVerification,'
              '  allow: k.allowCredentials'
              ' && k.allowCredentials.map((c) => bytes(c.id)),'
              '  prf: !!k.extensions.prf,'
              '  prfEval: !!(k.extensions.prf && k.extensions.prf.eval)'
              ' }));'
              ' return Promise.resolve({'
              '  rawId: new Uint8Array([9, 8, 7]).buffer,'
              '  getClientExtensionResults() { return $results; }'
              ' });'
              '};'
          .toJS);
  return make.callAsFunction(null, calls) as JSFunction;
}

List<Map<String, Object?>> _recorded(JSArray<JSString> calls) => [
      for (final call in calls.toDart)
        jsonDecode(call.toDart) as Map<String, Object?>
    ];

void main() {
  group('onboarding stops at the atServer TLS handshake', () {
    late String dbName;
    late List<IndexedDbHintStore> opened;
    late Future<IndexedDbHintStore> Function() defaultOpen;
    late JSObject credentials;
    late JSAny? originalPublicKeyCredential;
    late JSObject storagePrototype;
    late JSAny? originalPersist;
    late JSArray<JSString> ceremonyCalls;
    late JSArray<JSString> signalCalls;

    setUp(() {
      dbName = 'onboard_new_at_sign_${DateTime.now().microsecondsSinceEpoch}';
      opened = [];
      defaultOpen = openEntryHintStore;
      openEntryHintStore = () async {
        final store = await IndexedDbHintStore.open(dbName: dbName);
        opened.add(store);
        return store;
      };
      ceremonyCalls = JSArray<JSString>();
      signalCalls = JSArray<JSString>();
      credentials = window.navigator.credentials as JSObject;
      credentials['create'] =
          _ceremonyStub(ceremonyCalls, 'create', '{prf: {enabled: true}}');
      credentials['get'] = _ceremonyStub(ceremonyCalls, 'get',
          '{prf: {results: {first: new Uint8Array(32).fill(5).buffer}}}');
      final make = globalContext.callMethod<JSFunction>(
          'Function'.toJS,
          'signals'.toJS,
          'return {'
                  ' getClientCapabilities() {'
                  '  return Promise.resolve({"extension:prf": true}); },'
                  ' signalUnknownCredential(o) {'
                  '  signals.push(JSON.stringify(o)); return Promise.resolve(); }'
                  '};'
              .toJS);
      originalPublicKeyCredential = globalContext['PublicKeyCredential'];
      globalContext['PublicKeyCredential'] =
          make.callAsFunction(null, signalCalls) as JSObject;
      // The onboarding asks the browser to keep this origin's storage; the
      // grant is not what this test is about, and a headless browser may leave
      // it pending. Stub it on the prototype, whichever StorageManager
      // instance the page's navigator hands out.
      storagePrototype = (globalContext['StorageManager']
          as JSObject)['prototype'] as JSObject;
      originalPersist = storagePrototype['persist'];
      final persist = globalContext.callMethod<JSFunction>('Function'.toJS,
          'return function () { return Promise.resolve(true); };'.toJS);
      storagePrototype['persist'] = persist.callAsFunction(null) as JSFunction;
      window.localStorage.removeItem('at_client_web:prf-miss-at');
    });

    tearDown(() {
      credentials.delete('create'.toJS);
      credentials.delete('get'.toJS);
      storagePrototype['persist'] = originalPersist;
      globalContext['PublicKeyCredential'] = originalPublicKeyCredential;
      openEntryHintStore = defaultOpen;
    });

    test(
        'onboarding a new atSign runs the PRF ceremonies and stops at the '
        'atServer TLS handshake', () async {
      final dialed = Completer<void>();
      final port = await _handshakeFailingAtServerPort(dialed);

      final onboarding = onboardNewAtSign(
          atSign: '@alice',
          cram: 'cram-secret',
          app: 'wavi',
          rpId: 'localhost',
          rpName: 'Test',
          transport:
              SessionTransportOptions(proxyHost: '127.0.0.1', proxyPort: port));
      // The activation holds the atSign's setup lock and polls an unreachable
      // atServer for the whole onboarding provisioning budget (five minutes)
      // before it throws. This test observes the chain up to the first dial and
      // ends; the page closes with the onboarding still polling.
      unawaited(onboarding.then<void>((_) {}, onError: (Object _) {}));

      await dialed.future.timeout(const Duration(seconds: 15));

      final ceremonies = _recorded(ceremonyCalls);
      expect(ceremonies, hasLength(2),
          reason: 'one create ceremony and one PRF assertion');
      final creation = ceremonies.first;
      expect(creation['kind'], 'create');
      expect(creation['rp'], {'id': 'localhost', 'name': 'Test'});
      expect(creation['userName'], '@alice');
      expect(creation['selection'],
          {'residentKey': 'required', 'userVerification': 'required'},
          reason: 'a discoverable, user-verified passkey named for @alice');
      expect(creation['prf'], isTrue);
      expect(creation['prfEval'], isFalse,
          reason: 'the create ceremony enables PRF without an eval input');

      final assertion = ceremonies.last;
      expect(assertion['kind'], 'get');
      expect(assertion['rpId'], 'localhost');
      expect(assertion['userVerification'], 'required');
      expect(assertion['allow'], [_credentialId],
          reason: 'narrowed to the passkey just registered');
      expect(assertion['prfEval'], isTrue,
          reason: 'the assertion evaluates PRF on the record salt');

      expect(opened, hasLength(1), reason: 'the entry point opened its store');
      expect(await opened.single.credentialId('@alice'), isNull);
      expect(await opened.single.enrollmentId('@alice'), isNull,
          reason: 'nothing is kept for the atSign before the atServer answers');
      expect(window.localStorage.getItem('at_client_web:prf-miss-at'), isNull,
          reason: 'the ceremony returned a usable PRF result');
    });
  });
}
