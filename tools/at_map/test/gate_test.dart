/// What the map job blocks on: anchors, transitions, samples and freshness.
///
/// Catalogue: features/at_map/sdk_map.feature
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/harness.dart';

const _localSecondary =
    'packages/at_client/lib/src/client/local_secondary.dart';
const _clientImpl = 'packages/at_client/lib/src/client/at_client_impl.dart';
const _notificationService =
    'packages/at_client/lib/src/service/notification_service_impl.dart';
const _notificationManager =
    'packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart';

void main() {
  late Harness h;
  setUpAll(() async => h = await Harness.open());
  tearDownAll(() => h.close());

  test('A renamed anchored method fails the map job', () async {
    final original = h.sdkFile(_notificationService);
    Future<List<String>> failuresAfter(String text) async {
      final r = await h.check(sdk: {_notificationService: text});
      expect(r.code, isNot(0), reason: '$r');
      return r.failures;
    }

    final renamed = original.replaceAll(
        'handleNotificationReceipt', 'handleNotificationReceived');
    expect(
        await failuresAfter(renamed),
        contains(allOf(
            contains('share-record.bob-deliver'),
            contains('NotificationServiceImpl.handleNotificationReceipt'),
            contains(
                'candidates: NotificationServiceImpl.handleNotificationReceived'))),
        reason: 'the failure names the step, the anchor and the renamed method '
            'as a candidate');

    final unlike =
        original.replaceAll('handleNotificationReceipt', 'onMonitorJson');
    expect(
        await failuresAfter(unlike),
        contains(allOf(
            contains('share-record.bob-deliver'),
            contains(
                'NotificationServiceImpl.onMonitorJson (same body as reviewed)'))),
        reason: 'a rename to an unlike name is found by its unchanged body');

    final reworked =
        edit(renamed, r"logger.finest('DEBUG: $notificationJSON');", '');
    expect(
        await failuresAfter(reworked),
        contains(allOf(
            contains('share-record.bob-deliver'),
            contains(
                'candidates: NotificationServiceImpl.handleNotificationReceived'))),
        reason: 'a rename that also changes the body is found by its name');
  });

  test('An anchored statement edited in place fails the map job', () async {
    final edited = edit(
        h.sdkFile(_localSecondary),
        'await q.enqueue(atKey, op);',
        'await q.enqueue(atKey, op, urgent: true);');
    final r = await h.check(sdk: {_localSecondary: edited});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(contains('share-record.alice-enqueue'),
            contains('"await q.enqueue(atKey, op);"'), contains('0 times'))),
        reason: 'the failure names the step and the statement it no longer '
            'finds exactly once: $r');
  });

  test('A reformatted anchored statement still resolves', () async {
    final clean = await h.check();
    expect(clean.code, 0,
        reason: 'the committed data is fresh, so this test starts green: '
            '$clean');
    final rewrapped = edit(
        h.sdkFile(_localSecondary),
        'await q.enqueue(atKey, op);',
        'await q\n          .enqueue(\n      atKey,  op)   ;');
    final built = await h.build(sdk: {_localSecondary: rewrapped});
    expect(built.code, 0, reason: '$built');
    final r =
        await h.check(data: built.data, sdk: {_localSecondary: rewrapped});
    expect(r.code, 0, reason: 'a rewrap changes layout, not tokens: $r');
    expect(r.text, isNot(contains('alice-enqueue: changed since reviewed')),
        reason: 'the body hash is over tokens, so the step stays reviewed');
    final step = stepOf(flowJson(built), 'alice-enqueue');
    expect((step['snippet'] as Map)['text'], contains('.enqueue(\n'),
        reason: 'the rewrapped source is what the snippet shows, so this run '
            'really read the rewrap');
  });

  test('A broken call edge fails the map job', () async {
    final rerouted = edit(
            h.sdkFile(_clientImpl),
            'var putResponse = await executeUpdateOrDelete(\n'
                '        putBuilder, _routingFor(atKey, putRequestOptions?.useRemoteAtServer));',
            'var putResponse = await _routeWrite(putBuilder, atKey, putRequestOptions);')
        .replaceFirst(
            '  Future<AtResponse> _putInternal(',
            '  Future<String?> _routeWrite(UpdateVerbBuilder b, AtKey k, '
                'PutRequestOptions? o) =>\n'
                '      executeUpdateOrDelete(b, _routingFor(k, o?.useRemoteAtServer));\n\n'
                '  Future<AtResponse> _putInternal(');
    final r = await h.check(sdk: {_clientImpl: rerouted});
    expect(r.code, isNot(0));
    expect(r.failures.where((f) => f.contains('anchor')), isEmpty,
        reason: 'every anchor still resolves, so only the edge can fail: $r');
    expect(
        r.failures,
        contains(allOf(
            contains('share-record.alice-put -> share-record.alice-route'),
            contains('AtClientImpl._putInternal no longer calls '
                'AtClientImpl.executeUpdateOrDelete'))),
        reason: 'the failure names the edge and the call it no longer finds');
  });

  test('A transition that is neither an edge nor a hop fails the map job',
      () async {
    final yaml = '${h.sdkFile(flowYaml)}\n'
        '  - id: bob-extra\n'
        '    lane: bob.client\n'
        '    sublane: Monitor\n'
        '    intent: A step its predecessor neither calls nor binds.\n'
        '    anchor:\n'
        '      code: sdk:packages/at_client/lib/src/manager/monitor.dart\n'
        '      symbol: Monitor.start\n';
    final r = await h.check(sdk: {flowYaml: yaml});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(
            contains('share-record.bob-deliver -> share-record.bob-extra'),
            contains('neither an edge nor a hop'))),
        reason: 'the failure names both steps: $r');
  });

  test('A transition a binder binds needs no declaration', () async {
    final block = h.sdkFile(flowYaml).split('  - id: bob-deliver').last;
    expect(block, isNot(contains('reached:')),
        reason: 'bob-deliver declares nothing about how it is reached');
    final r = await h.build();
    expect(r.code, 0, reason: '$r');
    final reached = stepOf(flowJson(r), 'bob-deliver')['reached'] as Map;
    expect(reached['kind'], 'field');
    expect(
        reached['text'],
        allOf(contains('function-field hop through Monitor.handleNotification'),
            contains('bound in NotificationServiceImpl.')));

    final unbound = edit(
        h.sdkFile(_notificationService),
        'handleNotification: handleNotificationReceipt,',
        'handleNotification: (json) => handleNotificationReceipt(json),');
    final without = await h.build(sdk: {_notificationService: unbound});
    expect(
        without.failures,
        contains(allOf(
            contains('share-record.bob-receive -> share-record.bob-deliver'),
            contains('neither an edge nor a hop'))),
        reason: 'with the tear-off gone from Monitor\'s construction nothing '
            'binds the two, so the binder is what resolved the transition');
  });

  test('A hop with an unresolved end fails the map job', () async {
    final renamed =
        h.serverFile(_notificationManager).replaceAll('notifs', 'pending');
    final r = await h.check(server: {_notificationManager: renamed});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(
            contains(
                'share-record.alice-server-queue -> share-record.alice-server-send'),
            contains('stream hop through PerAtSignNotifSender.notifs'),
            contains('the field is not declared'))),
        reason: 'the failure names the hop and the end it cannot resolve: $r');
  });

  test('A sample dispatching elsewhere fails the map job', () async {
    final yaml = edit(
        h.sdkFile(flowYaml),
        'sample: "notify:id:0a1b2c3d-1111-2222-3333-444455556666:update:messageType:key:@bob:note.ns@alice:bm90IGEgcmVhbCBjaXBoZXJ0ZXh0"',
        'sample: "notify:list"');
    final r = await h.check(sdk: {flowYaml: yaml});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(
            contains('share-record.bob-server-accept'),
            contains(
                'dispatch chose NotifyListVerbHandler, not NotifyVerbHandler'),
            matches(RegExp(r"at_commons 5\.\d+\.\d+ \(at_server's lock\)")))),
        reason: 'the failure names the step, the handler dispatch chose and '
            'the at_commons version it was replayed with: $r');
  });

  test('A sample one at_commons version rejects fails the map job', () async {
    final config = jsonDecode(File(p.join(h.ws.server.dir,
            'packages/at_secondary_server/.dart_tool/package_config.json'))
        .readAsStringSync()) as Map;
    final commons = (config['packages'] as List)
        .cast<Map>()
        .firstWhere((x) => x['name'] == 'at_commons');
    final syntax = p.join(Uri.parse(commons['rootUri'] as String).toFilePath(),
        'lib/src/verb/syntax.dart');
    final stricter = edit(File(syntax).readAsStringSync(),
        r"r'^from:(?<atSign>@?[^:@\s]+)", r"r'^from:(?<atSign>@[^:@\s]+):only");
    final r = await h.check(outside: {syntax: stricter});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(contains('share-record.bob-server-from'),
            contains('"from:@alice"'), contains("(at_server's lock)"))),
        reason: 'the failure names the step, the sample and the at_commons '
            'version that rejects it: $r');
    expect(r.failures.where((f) => f.contains('(this checkout)')), isEmpty,
        reason: 'the client\'s at_commons still accepts the sample');
  });

  test('A stale flow file fails the map job', () async {
    final changed = edit(
        h.sdkFile(_localSecondary),
        '    if (!shouldEnqueueForSync(atKey, op)) return;\n',
        '    if (!shouldEnqueueForSync(atKey, op)) return;\n'
            '    if (atKey.isEmpty) return;\n');
    final r = await h.check(sdk: {_localSecondary: changed});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(contains('docs/map/data/flows/share-record.js'),
            contains('not what a build produces'))),
        reason: 'the committed flow file no longer matches a build: $r');
  });

  test('An index-only change passes the map job', () async {
    const testFile = 'packages/at_client/test/notification_service_test.dart';
    final cited = h.sdkFile(testFile).replaceFirst(RegExp(r'^'),
        '/// Catalogue: features/at_lookup/start_notifications_once.feature\n');
    final before = snapshot(h.committedData);
    final r = await h.check(sdk: {testFile: cited});
    expect(r.code, 0, reason: 'nothing the gate builds reads a test: $r');
    expect(snapshot(h.committedData), equals(before),
        reason: 'the job writes nothing under docs/map/data');

    final plain = await h.indexes(data: h.freshData());
    final withLine =
        await h.indexes(data: h.freshData(), sdk: {testFile: cited});
    expect(withLine.file('indexes.js'), isNot(plain.file('indexes.js')),
        reason: 'the change does reach the indexes, which is why only '
            'build --indexes may write them');
  });
}
