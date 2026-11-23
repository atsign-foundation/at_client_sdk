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
import 'package:at_client_web/src/js/at_error_code.dart';
import 'package:at_client_web/src/js/bridge.dart';
import 'package:at_client_web/src/js/js_session.dart';
import 'package:test/test.dart';

import '../session/wire_fakes.dart';
import '../test_utils.dart';

Future<JSAny?> _settled(JSAny? promise, {required bool expectReject}) {
  final done = Completer<JSAny?>();
  (promise! as JSObject).callMethod(
      'then'.toJS,
      ((JSAny? v) {
        if (expectReject) {
          done.completeError(
              TestFailure('expected rejection, resolved with $v'));
        } else {
          done.complete(v);
        }
      }).toJS,
      ((JSAny? r) {
        if (!expectReject) {
          final obj = r! as JSObject;
          done.completeError(TestFailure(
              'rejected with ${obj['code'].dartify()}: ${obj['message'].dartify()} (${obj.dartify()})'));
        } else {
          done.complete(r);
        }
      }).toJS);
  return done.future;
}

Future<JSAny?> _resolved(JSAny? promise) =>
    _settled(promise, expectReject: false);

Future<JSObject> _rejected(JSAny? promise) async =>
    (await _settled(promise, expectReject: true))! as JSObject;

JSObject _obj(Map<String, Object?> map) => map.jsify()! as JSObject;

JSAny? _call(JSObject target, String name, [List<JSAny?> args = const []]) =>
    args.isEmpty
        ? target.callMethod(name.toJS)
        : target.callMethodVarArgs(name.toJS, args);

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
    bridge = createJSInteropWrapper(AtClientWebBridge(
      isSecureContext: () => true,
      open: (o) async {
        final AtKeys keys;
        try {
          keys = AtKeys.fromJson(o.keys);
        } on Object {
          throw BadKeyException('keys is not a usable .atKeys document');
        }
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
        return AtClientJsSession(client, namespace: o.namespace);
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

  test(
      'AtClientWebBridge -> AtClientJsSession -> JsCollectionsAdapter end-to-end',
      () async {
    // 1. Credential-less keys fail with bad_key.
    final badKeys = await _rejected(_call(bridge, 'create', [
      _obj({'atSign': '@alice', 'namespace': 'MyApp', 'keys': '{}'})
    ]));
    expect(badKeys['code'].dartify(), 'bad_key');

    // 2. Open real session with mixed-case namespace (folded to lowercase).
    final keysJson = jsonEncode(cryptoReadyKeys().toJson());
    final session = (await _resolved(_call(bridge, 'create', [
      _obj({'atSign': '@alice', 'namespace': 'MyApp', 'keys': keysJson})
    ])))! as JSObject;

    // 3. Opening a data-only collection does not start monitor; default starts it.
    final dataOnly = (await _resolved(_call(session, 'collection', [
      'dataonly'.toJS,
      _obj({'type': 'Note', 'eventSource': 'data'})
    ])))! as JSObject;
    expect(wire.lookUpsBuilt.every((l) => l.notificationStarts == 0), isTrue);

    final todos = (await _resolved(_call(session, 'collection', [
      'Todos'.toJS,
      _obj({'type': 'Todo'})
    ])))! as JSObject;
    expect(wire.lookUpsBuilt.any((l) => l.notificationStarts > 0), isTrue);

    // 4. Create stamps the declared type tag on the stored record (T6.9).
    final created = (await _resolved(_call(todos, 'create', [
      _obj({'title': 'ship'}),
      _obj({'id': 't1'})
    ])))! as JSObject;
    expect(created['id'].dartify(), 't1');
    expect(created['type'].dartify(), 'Todo');
    final stored = await client.get(AtKey.fromString('t1.todos.myapp@alice'));
    expect(jsonDecode(stored.value as String)['type'], 'Todo');

    // 5. Get, list, query, update, remove work end-to-end.
    final got = (await _resolved(_call(todos, 'get', [
      _obj({'id': 't1'})
    ])))! as JSObject;
    expect((got['data']! as JSObject)['title'].dartify(), 'ship');

    final listed = (await _resolved(_call(todos, 'list')))! as JSObject;
    expect((listed['items']! as JSArray).length, 1);

    final queried = (await _resolved(_call(todos, 'query', [
      [
        {'path': 'title', 'op': '==', 'value': 'ship'}
      ].jsify()
    ])))! as JSObject;
    expect((queried['items']! as JSArray).length, 1);

    await _resolved(_call(todos, 'update', [
      _obj({'id': 't1'}),
      _obj({'title': 'done'})
    ]));
    final updated = (await _resolved(_call(todos, 'get', [
      _obj({'id': 't1'})
    ])))! as JSObject;
    expect((updated['data']! as JSObject)['title'].dartify(), 'done');

    // 6. Over-deep item stored directly rejects get with COLLECTION_ITEM_TOO_DEEP + id/owner.
    final deepJson = '{"type":"Todo","obj":${'{"k":' * 65}1${'}' * 65}}';
    await client.put(AtKey.fromString('deep.todos.myapp@alice'), deepJson);
    final tooDeep = await _rejected(_call(todos, 'get', [
      _obj({'id': 'deep'})
    ]));
    expect(tooDeep['code'].dartify(),
        collectionErrorCode(CollectionFailure.tooDeep));
    expect(tooDeep['id'].dartify(), 'deep');
    expect(tooDeep['owner'].dartify(), '@alice');

    // 7. Invalid owner rejects with invalid_argument naming owner.
    final badOwner = await _rejected(_call(dataOnly, 'get', [
      _obj({'id': 't1', 'owner': '@a@b-sentinel'})
    ]));
    expect(badOwner['code'].dartify(), 'invalid_argument');
    expect(badOwner['id'].dartify(), 't1');
    expect(badOwner['message'].dartify() as String, contains('owner'));
    expect(
        badOwner['message'].dartify() as String, isNot(contains('sentinel')));

    // 8. Notify key validation rejects bad_key without hitting wire.
    wire.commands.clear();
    for (final key in [
      {'key': 'k', 'sharedWith': '@bob', 'public': true},
      {'key': 'k', 'sharedWith': '@bob', 'cached': true},
      {'key': 'k', 'sharedWith': '@bob', 'sharedBy': '@carol'},
      {'key': '', 'sharedWith': '@bob'},
    ]) {
      final err =
          await _rejected(_call(session, 'notify', [_obj(key), 'v'.toJS]));
      expect(err['code'].dartify(), 'bad_key');
    }
    expect(wire.commands.where((c) => c.startsWith('notify')), isEmpty);

    // 9. Remove works, then close() stops session & post-close collection calls reject closed.
    await _resolved(_call(todos, 'remove', [
      _obj({'id': 't1'})
    ]));
    expect(
        await _resolved(_call(todos, 'get', [
          _obj({'id': 't1'})
        ])),
        isNull);

    await _resolved(_call(session, 'close'));
    final afterClose = await _rejected(_call(todos, 'list'));
    expect(afterClose['code'].dartify(), 'closed');
    final watchAfterClose =
        _call(todos, 'watch', [((JSAny? _) {}).toJS])! as JSObject;
    expect(watchAfterClose['code'].dartify(), 'closed');
  });
}
