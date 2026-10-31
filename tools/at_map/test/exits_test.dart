/// The exits the walker extracts on bob-server-accept's path through the
/// real NotifyVerbHandler at the pinned SHA.
///
/// Catalogue: features/at_map/sdk_map.feature
library;

import 'package:at_map/at_map.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/harness.dart';

const _polBranch = '!atConnectionMetadata.isAuthenticated';

/// The flow model without claims or contract text, so a walker that misses
/// an exit fails the assertion about that exit rather than a backing.
String withoutContracts(String yaml) {
  final out = <String>[];
  var skipping = false;
  for (final line in yaml.split('\n')) {
    if (line == '    claims:' || line == '    post:' || line == '    pre:') {
      skipping = true;
      continue;
    }
    if (skipping && (line.startsWith('      ') || line.trim().isEmpty)) {
      continue;
    }
    skipping = false;
    out.add(line);
  }
  return out.join('\n');
}

void main() {
  late Harness h;
  late List<Map<String, Object?>> exits;
  setUpAll(() async {
    h = await Harness.open();
    final r =
        await h.build(sdk: {flowYaml: withoutContracts(h.sdkFile(flowYaml))});
    expect(r.code, 0, reason: '$r');
    exits = ((stepOf(flowJson(r), 'bob-server-accept')['exits'] as Map)['list']
            as List)
        .cast<Map<String, Object?>>();
  });
  tearDownAll(() => h.close());

  List<Map<String, Object?>> withGuard(String guard) =>
      exits.where((e) => e['guard'] == guard).toList();

  test('The pol path includes the checks before the branch', () {
    final firstOnBranch = exits.indexWhere((e) =>
        (e['branch'] as List).isNotEmpty &&
        (e['branch'] as List).first == _polBranch);
    expect(firstOnBranch, greaterThan(0));
    for (final g in [
      "verbParams[AtConstants.strategy] == 'latest' && verbParams[AtConstants.notifier] == null",
      'verbParams[AtConstants.notificationExpiresAt] != null && verbParams[AtConstants.ttlNotification] != null',
      '!atConnectionMetadata.isAuthenticated && !atConnectionMetadata.isPolAuthenticated',
      '(verbParams[AtConstants.id]?.length ?? 0) > maxIdLength',
    ]) {
      final hits = withGuard(g);
      expect(hits, hasLength(1), reason: 'the guard "$g" is listed once');
      expect(hits.single['branch'], isEmpty,
          reason: '"$g" comes before the branch, so no branch condition '
              'encloses it');
      expect(exits.indexOf(hits.single), lessThan(firstOnBranch),
          reason: '"$g" is listed before the exits on the pol branch');
    }
  });

  test('The pol path includes its refusals and drops', () {
    for (final g in [
      '_isText(verbParams)',
      'sharedWith != currentAtSign',
      'sharedBy != fromAtSign',
      '!isWellFormedAtKey(atKey)',
      'reserved != null',
      'n.isExpired()',
      'await notifMgr.isKeyExists(n.id!)',
    ]) {
      final hits = withGuard(g);
      expect(hits, hasLength(1), reason: 'the guard "$g" is listed once');
      expect(hits.single['branch'], [_polBranch],
          reason: '"$g" is on the branch $_polBranch');
    }
    expect(withGuard('sharedBy != fromAtSign').single['kind'], 'throw');
    expect(withGuard('reserved != null').single['kind'], 'success',
        reason: 'on the pol branch a reserved namespace is a drop answered '
            'data:success');
  });

  test('A helper in another file is followed', () {
    final hits = withGuard('length > maxNotificationKeyLength');
    expect(hits, hasLength(1));
    final e = hits.single;
    expect(e['symbol'], 'refuseOverlongNotificationKey');
    expect(e['type'], 'InvalidAtKeyException');
    expect(e['branch'], [_polBranch, 'caches'],
        reason: 'the helper is called under the guard caches');
    expect(e['url'], contains('/notification/notification_key_length.dart#L'),
        reason: 'the exit is in the helper\'s own file');
  });

  test('The pol path shows no exit of the client branch', () async {
    expect(
        exits.where((e) =>
            e['symbol'] == 'NotifyVerbHandler._handleAuthenticatedConnection' ||
            ((e['chain'] as List?) ?? const [])
                .contains('NotifyVerbHandler._handleAuthenticatedConnection') ||
            (e['branch'] as List)
                .contains('atConnectionMetadata.isAuthenticated')),
        isEmpty);

    final model = loadModel(h.ws.sdk).model!;
    final r = await h.ws.resolver(model.roots);
    final file = p.join(h.ws.server.dir,
        'packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart');
    final inv = await ExitWalker(r, h.ws.server.dir).walk([
      (await r.declaration(file, 'NotifyVerbHandler.processVerb'))!,
      (await r.declaration(
          file, 'NotifyVerbHandler._handlePolAuthenticatedConnection'))!,
    ]);
    final client = inv.exits
        .where((e) =>
            e.symbol == 'NotifyVerbHandler._handleAuthenticatedConnection')
        .toList();
    expect(client, isNotEmpty,
        reason: 'the walker does reach the client branch, so its absence '
            'from the path is the filter, not a blind spot');
    expect(client.every((e) => !e.onPath), isTrue);
  });
}
