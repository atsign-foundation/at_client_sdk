/// The page, opened from disk in headless Chrome.
///
/// Catalogue: features/at_map/sdk_map.feature
@Tags(['chrome'])
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'support/chrome.dart';
import 'support/harness.dart';
import 'support/page.dart';

const _localSecondary =
    'packages/at_client/lib/src/client/local_secondary.dart';
const _feature = 'features/notify/peer_reserved_namespace.feature';
const _note = 'Server lane at at_server trunk d654f25bd; production p3.19.0 '
    'is 160 commits behind.';
const _payload = '</pre><img src=x onerror=alert(1)>';

void main() {
  late Harness h;
  late Chrome chrome;
  setUpAll(() async {
    h = await Harness.open();
    chrome = await Chrome.start();
  });
  tearDownAll(() async {
    await chrome.close();
    await h.close();
  });

  Future<Page> open(String url, String ready) async {
    final page = await chrome.open(url);
    await page.waitFor('document.body.getAttribute("data-ready") === "$ready"');
    return page;
  }

  Future<String> text(Page page, String selector) async =>
      (await page.eval('(document.querySelector(${jsonEncode(selector)}) || '
          '{textContent: ""}).textContent')) as String;

  test('A client-lane check carries no enforced-by label', () async {
    final built = await h.build();
    expect(built.code, 0, reason: '$built');
    final page = await open(
        '${pageOver(built.data, h.temp)}#flow=share-record&step=alice-put',
        'share-record.alice-put');
    final claim = await text(page, '#panel-contracts li.contract-refuses');
    expect(claim, contains('a key that fails AtKeyValidators'));
    expect(claim, contains('client-side, best effort'));
    expect(await text(page, '#panel'), isNot(contains('enforced by')));

    await page.select('share-record', 'bob-server-accept');
    expect(await text(page, '#panel-contracts'),
        contains('enforced by bob.server'),
        reason: 'a server claim does carry the label, so its absence above '
            'is the lane\'s doing');
  });

  test('A client step changed since review is drawn amber', () async {
    final built = await h.build(sdk: {
      _localSecondary: edit(
          h.sdkFile(_localSecondary),
          '    if (!shouldEnqueueForSync(atKey, op)) return;\n',
          '    if (!shouldEnqueueForSync(atKey, op)) return;\n'
              '    if (atKey.isEmpty) return;\n')
    });
    expect(built.code, 0, reason: '$built');
    final page = await open(
        '${pageOver(built.data, h.temp)}#flow=share-record', 'share-record');
    Future<Object?> amber(String step) => page.eval(
        'document.querySelector(\'g.step[data-step="$step"]\').classList.contains("amber")');
    expect(await amber('alice-enqueue'), isTrue);
    expect(await amber('alice-put'), isFalse,
        reason: 'an unchanged step is not amber');
  });

  test('The page marks unverified contract text', () async {
    final yaml = edit(
        h.sdkFile(flowYaml),
        '      contains: "sink.push(n, report: report);"\n',
        '      contains: "sink.push(n, report: report);"\n'
            '    post:\n'
            '      - text: every monitor connection of @bob has the notification\n');
    final built = await h.build(sdk: {flowYaml: yaml});
    expect(built.code, 0, reason: '$built');
    final page = await open(
        '${pageOver(built.data, h.temp)}#flow=share-record&step=bob-server-push',
        'share-record.bob-server-push');
    final post = await text(page, '#panel-contracts li.contract-post');
    expect(post,
        contains('every monitor connection of @bob has the notification'));
    expect(await text(page, '#panel-contracts li.contract-post .label'),
        'unverified');
  });

  test('The server lane carries one note about production', () async {
    final built = await h.build();
    expect(built.code, 0, reason: '$built');
    final page = await open(
        '${pageOver(built.data, h.temp)}#flow=share-record', 'share-record');
    final notes = (await page.eval('Array.from(document.querySelectorAll('
            '"g.lane")).map(g => [g.getAttribute("data-lane"), '
            '(g.querySelector(".lane-note") || {textContent: null}).textContent])'))
        as List;
    expect(notes, [
      ['alice.client', null],
      ['alice.server', _note],
      ['bob.server', _note],
      ['bob.client', null],
    ]);
  });

  test('The map opens from disk in Chrome', () async {
    final page = await open(committedPage(), 'share-record');
    expect(
        await page.eval('Array.from(document.querySelectorAll("g.lane"))'
            '.map(g => g.getAttribute("data-lane"))'),
        ['alice.client', 'alice.server', 'bob.server', 'bob.client']);
    expect(await page.eval('document.querySelectorAll("g.step").length'), 15);
    expect(page.errors, isEmpty);
  });

  test('The page requests nothing from the network', () async {
    final page = await open(committedPage(), 'share-record');
    final steps = ((await page.eval('Array.from(document.querySelectorAll('
            '"g.step")).map(g => g.getAttribute("data-step"))')) as List)
        .cast<String>();
    expect(steps, hasLength(15));
    for (final s in steps) {
      await page.select('share-record', s);
    }
    expect(page.requests, isNotEmpty,
        reason: 'the page\'s own files are requests, so the log is live');
    expect(page.requests.where((u) => !u.startsWith('file://')), isEmpty,
        reason: 'every request is a file of the clone');
    expect(page.errors, isEmpty);
  });

  test('Selecting a step shows what it does and where', () async {
    final page =
        await open('${committedPage()}#flow=share-record', 'share-record');
    await page.select('share-record', 'bob-server-accept');
    expect(
        await text(page, '#panel-intent'),
        "Accept @alice's notification only if it is for @bob and its sharedBy "
        'is the atSign pol proved.');
    expect(
        await text(page, '#panel-skeleton'), contains('_refuseForeignAtSigns'));
    final guards = await page.eval('Array.from(document.querySelectorAll('
        '"#panel-exits tr.exit td.exit-guard code")).map(c => c.textContent)');
    expect(guards, containsAll(['sharedBy != fromAtSign', 'reserved != null']));
    expect(await text(page, '#panel-snippet'),
        contains('Future<void> _handlePolAuthenticatedConnection('));
    expect(
        await page.eval(
            'document.querySelector("#panel-source").getAttribute("href")'),
        startsWith('https://github.com/atsign-foundation/at_server/blob/'
            'd654f25bd4bdef2668c77556f563f9e43960b325/packages/'
            'at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L'));
  });

  test('A deep link opens the step it names', () async {
    final page = await open(
        '${committedPage()}#flow=share-record&step=bob-server-accept',
        'share-record.bob-server-accept');
    expect(
        await page.eval('document.querySelector("g.step.selected")'
            '.getAttribute("data-step")'),
        'bob-server-accept');
    expect(await text(page, '.panel-title'), 'share-record.bob-server-accept');
  });

  test('Embedded text cannot become markup', () async {
    const title =
        "Another atServer's notification into a reserved namespace is dropped";
    final yaml = edit(
            h.sdkFile(flowYaml),
            'intent: Parse the notification, deliver it to each matching subscriber in order, then save its time as the watermark a reconnect replays from.',
            'intent: "$_payload"')
        .replaceFirst('scenario: $title', 'scenario: "$title $_payload"');
    final built = await h.build(sdk: {
      flowYaml: yaml,
      _localSecondary: edit(
          h.sdkFile(_localSecondary),
          '    if (cameFromServer) return;\n',
          '    if (cameFromServer) return;\n    // $_payload\n'),
    }, server: {
      _feature: edit(h.serverFile(_feature), 'Scenario Outline: $title',
          'Scenario Outline: $title $_payload'),
    });
    expect(built.code, 0, reason: '$built');
    expect(built.file('flows/share-record.js'), isNot(contains('</pre>')),
        reason: 'the data escapes markup characters');
    final page = await open(
        '${pageOver(built.data, h.temp)}#flow=share-record', 'share-record');
    for (final (step, where) in [
      ('bob-deliver', '#panel-intent'),
      ('alice-enqueue', '#panel-snippet'),
      ('bob-server-accept', '#panel-contracts .scenario-title'),
    ]) {
      await page.select('share-record', step);
      expect(await text(page, where), contains(_payload),
          reason: 'the text appears literally in $where');
      expect(await page.eval('document.querySelectorAll("img").length'), 0,
          reason: 'no element is created from it');
    }
    expect(page.dialogs, isEmpty, reason: 'no script ran from it');
  });
}
