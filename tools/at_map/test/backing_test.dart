/// The backing rules: what a claim must cite, from where, and on which path.
///
/// Catalogue: features/at_map/sdk_map.feature
library;

import 'package:test/test.dart';

import 'support/harness.dart';

const _feature = 'features/notify/peer_reserved_namespace.feature';

/// The flow model with [lines] added to bob-server-accept's claims.
String withClaim(Harness h, String lines) => edit(
    h.sdkFile(flowYaml),
    '    claims:\n      - refuses: a notification whose sharedBy is not the atSign pol proved\n',
    '    claims:\n$lines      - refuses: a notification whose sharedBy is not the atSign pol proved\n');

void main() {
  late Harness h;
  setUpAll(() async => h = await Harness.open());
  tearDownAll(() => h.close());

  test('An unbacked refusal claim fails the map job', () async {
    final r = await h.check(sdk: {
      flowYaml: withClaim(h, '      - refuses: a notification sent at night\n')
    });
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(
            contains('share-record.bob-server-accept'),
            contains('refuses a notification sent at night'),
            contains('cites no extracted exit and no Gherkin clause'))),
        reason: 'the failure names the step and the claim: $r');
  });

  test('A server claim backed only from at_client_sdk fails the map job',
      () async {
    final r = await h.check(sdk: {
      flowYaml: withClaim(
          h,
          '      - refuses: "a second monitor: from two starts at once"\n'
          '        backing:\n'
          '          gherkin:\n'
          '            feature: sdk:features/at_lookup/start_notifications_once.feature\n'
          '            scenario: "Two starts at once send one monitor:"\n'
          '            clause: "Then one monitor: is sent, and both starts complete"\n')
    });
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(
            contains('refuses a second monitor: from two starts at once'),
            contains('which is not from at_server'))),
        reason: 'the failure names the claim and says its backing is not '
            'from at_server: $r');
  });

  test('A claim backed by an exit on another branch fails the map job',
      () async {
    final r = await h.check(sdk: {
      flowYaml: withClaim(
          h,
          '      - refuses: a notification into a reserved namespace\n'
          '        backing:\n'
          '          exit: {symbol: NotifyVerbHandler._handleAuthenticatedConnection, guard: "reserved != null"}\n')
    });
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(
            contains('refuses a notification into a reserved namespace'),
            contains('on the branch "atConnectionMetadata.isAuthenticated"'),
            contains("not on share-record.bob-server-accept's own path"))),
        reason:
            'the failure names the claim and the branch the exit is on: $r');
  });

  test(
      'A refusal claim backed by an exit that does not refuse fails the map '
      'job', () async {
    final r = await h.check(sdk: {
      flowYaml: withClaim(
          h,
          '      - refuses: an expired notification\n'
          '        backing:\n'
          '          exit: {symbol: NotifyVerbHandler._handlePolAuthenticatedConnection, guard: "n.isExpired()"}\n')
    });
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(contains('refuses an expired notification'),
            contains('a success exit, which refuses nothing'))),
        reason: 'only a throw or an error answer backs a refusal: $r');
  });

  test('A Gherkin backing whose clause changed fails the map job', () async {
    final changed = edit(h.serverFile(_feature), 'Then it gets data:success',
        'Then it gets data:ok');
    final r = await h.check(server: {_feature: changed});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(
            contains('postcondition "a notification into a reserved namespace '
                'is dropped and answered data:success"'),
            contains('no longer finds clause "Then it gets data:success"'))),
        reason: 'the failure names the postcondition and the clause: $r');
  });

  test('The job counts unverified contract text', () async {
    final clean = await h.check();
    expect(clean.lines, contains('REPORT 0 unverified contract lines'),
        reason: 'the committed model backs all of its contract text');
    final yaml = edit(
        h.sdkFile(flowYaml),
        '      contains: "sink.push(n, report: report);"\n',
        '      contains: "sink.push(n, report: report);"\n'
            '    post:\n'
            '      - text: every monitor connection of @bob has the notification\n');
    final built = await h.build(sdk: {flowYaml: yaml});
    expect(built.code, 0, reason: 'unverified text does not fail a build');
    final r = await h.check(data: built.data, sdk: {flowYaml: yaml});
    expect(r.code, 0, reason: 'unverified text is reported, not failed: $r');
    expect(r.lines, contains('REPORT 1 unverified contract line'));
  });
}
