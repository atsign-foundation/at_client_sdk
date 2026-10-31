/// Review state: a changed client body is amber, a blessed one is not, and a
/// changed server body fails the job.
///
/// Catalogue: features/at_map/sdk_map.feature
@Timeout(Duration(minutes: 2))
library;

import 'package:at_map/at_map.dart';
import 'package:test/test.dart';

import 'support/chrome.dart';
import 'support/harness.dart';
import 'support/page.dart';

const _localSecondary =
    'packages/at_client/lib/src/client/local_secondary.dart';
const _notifyHandler =
    'packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart';

/// `_enqueueForSync` with an early return added.
String earlyReturn(Harness h) => edit(
    h.sdkFile(_localSecondary),
    '    if (!shouldEnqueueForSync(atKey, op)) return;\n',
    '    if (!shouldEnqueueForSync(atKey, op)) return;\n'
        '    if (atKey.isEmpty) return;\n');

void main() {
  late Harness h;
  setUpAll(() async => h = await Harness.open());
  tearDownAll(() => h.close());

  test('A changed client body is reported as changed since review', () async {
    final code = {_localSecondary: earlyReturn(h)};
    final built = await h.build(sdk: code);
    expect(built.code, 0, reason: '$built');
    final r = await h.check(data: built.data, sdk: code);
    expect(r.code, 0,
        reason: 'a changed client body is reported, not '
            'failed: $r');
    expect(
        r.lines,
        contains(
            'REPORT share-record.alice-enqueue: changed since reviewed (drawn amber)'));
  });

  test('Blessing a step clears its amber', () async {
    final code = {_localSecondary: earlyReturn(h)};
    final amber = await h.build(sdk: code);
    expect(stepOf(flowJson(amber), 'alice-enqueue')['changed'], isTrue,
        reason: 'the step starts out changed since reviewed');

    await h.ws.overlay(sdk: code);
    String? blessed;
    final status = runBless(h.ws, ['share-record.alice-enqueue'], log: (_) {},
        write: (path, text) {
      expect(path, flowYaml);
      blessed = text;
    });
    expect(status, 0);
    expect(blessed, isNotNull);

    final after = await h.build(sdk: {...code, flowYaml: blessed!});
    expect(after.code, 0, reason: '$after');
    expect(stepOf(flowJson(after), 'alice-enqueue')['changed'], isFalse);

    final chrome = await Chrome.start();
    addTearDown(chrome.close);
    final page =
        await chrome.open('${pageOver(after.data, h.temp)}#flow=share-record');
    await page
        .waitFor('document.body.getAttribute("data-ready") === "share-record"');
    expect(
        await page.eval(
            'document.querySelector(\'g.step[data-step="alice-enqueue"]\')'
            '.classList.contains("amber")'),
        isFalse,
        reason: 'the blessed step is no longer drawn amber');
  });

  test('Blessing a server step refuses an at_server checkout off the pin',
      () async {
    final dir = '${h.temp.path}/off-pin';
    gitIn(h.temp.path, ['clone', '--quiet', '--shared', h.ws.server.dir, dir]);
    gitIn(dir, ['checkout', '--quiet', '--detach', 'HEAD~1']);
    final lines = <String>[];
    final status = runBless(Workspace(sdkDir: repoRoot(), serverDir: dir),
        ['share-record.bob-server-accept'],
        log: lines.add, write: (_, __) => fail('nothing may be written'));
    expect(status, isNot(0));
    expect(lines, contains(contains('not the pinned')), reason: '$lines');
  });

  test('A server step changed since review fails the map job', () async {
    final changed = edit(
        h.serverFile(_notifyHandler),
        '    if (_isText(verbParams)) {\n      logger.warning(\'Dropped text',
        '    if (verbParams.isEmpty) {\n      return;\n    }\n'
            '    if (_isText(verbParams)) {\n      logger.warning(\'Dropped text');
    final r = await h.check(server: {_notifyHandler: changed});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(
            contains('share-record.bob-server-accept'),
            contains('read the step, then run dart run at_map bless '
                'share-record.bob-server-accept'))),
        reason: 'the failure names the step and asks for bless after its '
            'author has read it: $r');
  });
}
