@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_chops/at_chops.dart' show AESKey, RsaKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client_web/at_client_web.dart';
import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/js/error_codes.dart';
import 'package:at_client_web/src/js/bridge.dart';
import 'package:at_client_web/src/session/at_client_session.dart';
import 'package:at_client_web/src/session/session_options.dart';
import 'package:test/test.dart';

import '../session/wire_fakes.dart';
import '../test_utils.dart';
import 'bridge_test_helpers.dart';

void main() {
  late Wire wire;
  late AtClient client;
  late JSObject bridge;

  AtKeys cryptoReadyKeys() {
    final pair = RsaKeyPair.generate();
    return classicalAtKeys()
      ..fileLegacyMaterial(
          selfEncryptionKey: AESKey.generate(32).key,
          encryptionPublicKey: pair.atPublicKey.publicKey,
          encryptionPrivateKey: pair.atPrivateKey.privateKey);
  }

  setUp(() {
    wire = Wire()
      ..answer = (cmd) {
        if (cmd.startsWith('enroll:fetch:')) {
          return 'data:${jsonEncode({
                'appName': 'myapp',
                'deviceName': 'test',
                'namespace': {'myapp': 'rw'},
                'status': 'approved',
              })}';
        }
        if (cmd.startsWith('stats:')) {
          return 'data:[{"id":"3","name":"lastCommitID","value":"-1"}]';
        }
        if (cmd.startsWith('sync:')) {
          return 'data:[]';
        }
        return null;
      };
    bridge = createJSInteropWrapper(BridgeEntry(
      isSecureContext: () => true,
      open: (o) async {
        final keys = (o as KeysSessionOptions).keys;
        final root = o.rootDomain ?? AtRootDomain.atsignDomain;
        client = await portalSession(
          atSign: o.atSign,
          app: o.namespace,
          keys: keys,
          transport: (
            lookUps: wire.lookUps,
            finder: FixedSecondaryAddressFinder('atserver.test', 1),
            root: root,
          ),
          prefs: AtClientPreference()
            ..namespace = o.namespace
            ..rootDomain = root.rootDomain
            ..rootPort = root.rootPort
            ..monitorAutoStart = false,
        );
        return AtClientSession(client, namespace: o.namespace);
      },
    ));
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
  });

  test('BridgeEntry -> AtClientSession -> JsCollectionsAdapter end-to-end',
      () async {
    // 1. Credential-less keys fail with bad_key.
    final badKeys = await rejected(invoke(bridge, 'create', [
      jsObject({'atSign': '@alice', 'namespace': 'MyApp', 'keys': '{}'})
    ]));
    expect(badKeys.code, 'bad_key');

    // 2. Open real session with mixed-case namespace (folded to lowercase).
    final keysJson = jsonEncode(cryptoReadyKeys().toJson());
    final session = (await resolved(invoke(bridge, 'create', [
      jsObject({'atSign': '@alice', 'namespace': 'MyApp', 'keys': keysJson})
    ])))! as JSObject;

    // 3. Opening a data-only collection does not start monitor; default starts it.
    final dataOnly = (await resolved(invoke(session, 'collection', [
      'dataonly'.toJS,
      jsObject({'type': 'Note', 'eventSource': 'data'})
    ])))! as JSObject;
    expect(wire.lookUpsBuilt.every((l) => l.notificationStarts == 0), isTrue);

    final todos = (await resolved(invoke(session, 'collection', [
      'Todos'.toJS,
      jsObject({'type': 'Todo'})
    ])))! as JSObject;
    expect(wire.lookUpsBuilt.any((l) => l.notificationStarts > 0), isTrue);

    // 4. Create stamps the declared type tag on the stored record (T6.9).
    final created = (await resolved(invoke(todos, 'create', [
      jsObject({'title': 'ship'}),
      jsObject({'id': 't1'})
    ])))! as JSObject;
    expect(created['id'].dartify(), 't1');
    expect(created['type'].dartify(), 'Todo');
    final stored = await client.get(AtKey.fromString('t1.todos.myapp@alice'));
    expect(jsonDecode(stored.value as String)['type'], 'Todo');

    // 5. Get, list, query, update, remove work end-to-end.
    final got = (await resolved(invoke(todos, 'get', [
      jsObject({'id': 't1'})
    ])))! as JSObject;
    expect((got['data']! as JSObject)['title'].dartify(), 'ship');

    final listed = (await resolved(invoke(todos, 'list')))! as JSObject;
    expect((listed['items']! as JSArray).length, 1);

    final queried = (await resolved(invoke(todos, 'query', [
      [
        {'path': 'title', 'op': '==', 'value': 'ship'}
      ].jsify()
    ])))! as JSObject;
    expect((queried['items']! as JSArray).length, 1);

    await resolved(invoke(todos, 'update', [
      jsObject({'id': 't1'}),
      jsObject({'title': 'done'})
    ]));
    final updated = (await resolved(invoke(todos, 'get', [
      jsObject({'id': 't1'})
    ])))! as JSObject;
    expect((updated['data']! as JSObject)['title'].dartify(), 'done');

    // 6. Over-deep item stored directly rejects get with COLLECTION_ITEM_TOO_DEEP + id/owner.
    final deepJson = '{"type":"Todo","obj":${'{"k":' * 65}1${'}' * 65}}';
    await client.put(AtKey.fromString('deep.todos.myapp@alice'), deepJson);
    final tooDeep = await rejected(invoke(todos, 'get', [
      jsObject({'id': 'deep'})
    ]));
    expect(tooDeep.code, collectionErrorCode(CollectionFailure.tooDeep));
    expect(tooDeep.field('id'), 'deep');
    expect(tooDeep.field('owner'), '@alice');

    // 7. Invalid owner rejects with invalid_argument naming owner.
    final badOwner = await rejected(invoke(dataOnly, 'get', [
      jsObject({'id': 't1', 'owner': '@a@b-sentinel'})
    ]));
    expect(badOwner.code, 'invalid_argument');
    expect(badOwner.field('id'), 't1');
    expect(badOwner.message, contains('owner'));
    expect(badOwner.message, isNot(contains('sentinel')));

    // 8. Notify key validation rejects bad_key without hitting wire.
    wire.commands.clear();
    for (final key in [
      {'key': 'k', 'sharedWith': '@bob', 'public': true},
      {'key': 'k', 'sharedWith': '@bob', 'cached': true},
      {'key': 'k', 'sharedWith': '@bob', 'sharedBy': '@carol'},
      {'key': '', 'sharedWith': '@bob'},
    ]) {
      final err =
          await rejected(invoke(session, 'notify', [jsObject(key), 'v'.toJS]));
      expect(err.code, 'bad_key');
    }
    expect(wire.commands.where((c) => c.startsWith('notify')), isEmpty);

    // 9. Remove works, then close() stops session & post-close collection calls reject closed.
    await resolved(invoke(todos, 'remove', [
      jsObject({'id': 't1'})
    ]));
    expect(
        await resolved(invoke(todos, 'get', [
          jsObject({'id': 't1'})
        ])),
        isNull);

    await resolved(invoke(session, 'close'));
    final afterClose = await rejected(invoke(todos, 'list'));
    expect(afterClose.code, 'closed');
    final watchAfterClose =
        invoke(todos, 'watch', [((JSAny? _) {}).toJS])! as JSObject;
    expect(watchAfterClose['code'].dartify(), 'closed');
  });

  test('opening a keys session records the stop that close awaits', () async {
    final wire = Wire();
    final options = KeysSessionOptions(
        atSign: '@alice',
        namespace: 'wavi',
        keys: classicalAtKeys().toJson(),
        rootDomain: 'root.example');
    final root = options.rootDomain!;

    final session = await openJsSession(options, keysTransport: (
      lookUps: wire.lookUps,
      finder: FixedSecondaryAddressFinder('atserver.test', 1),
      root: root,
    ));

    expect(session, isA<AtClientSession>());
    expect(wire.roots, isNotEmpty);
    for (final dialled in wire.roots) {
      expect((dialled.rootDomain, dialled.rootPort), ('root.example', 64));
    }
    final stops = wire.stops;
    await session.close();
    expect(wire.stops, greaterThan(stops));
  });

  test('opening a passkey session records the stop that close awaits',
      () async {
    final passkey = GatedPasskeySession(PasskeyClient())
      ..stopGate = Completer<void>();
    final login = RecordingPasskeyLogin(passkey);
    final options = PasskeySessionOptions(
        atSign: '@alice',
        namespace: 'wavi',
        rpId: 'example.org',
        rpName: 'Wavi',
        rootDomain: 'root.example');

    final session = await openJsSession(options, passkeyOpen: login.call);

    expect(session, isA<AtClientSession>());
    final opened = login.seen.single;
    expect((opened.atSign, opened.namespace, opened.rpId, opened.rpName),
        ('@alice', 'wavi', 'example.org', 'Wavi'));
    final transport = login.transports.single;
    expect((transport.root.rootDomain, transport.root.rootPort),
        ('root.example', 64));

    var closed = false;
    final closing = session.close().then((_) => closed = true);
    await pumpEventQueue();
    expect(closed, isFalse, reason: 'close awaits the recorded stop');
    passkey.stopGate!.complete();
    await closing;
    expect(passkey.stops, 1);
  });
}
