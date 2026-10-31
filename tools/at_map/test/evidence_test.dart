/// Test evidence: which at_server tests name an exit by its message's text,
/// and the figure the map job reports against `ratchet.yaml`.
///
/// Catalogue: features/at_map/sdk_map.feature
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'support/chrome.dart';
import 'support/harness.dart';
import 'support/page.dart';

const _sharedBy =
    'NotifyVerbHandler._refuseForeignAtSigns sharedBy != fromAtSign throw';
const _signature = 'PolVerbHandler.processVerb fromPublicKey == null || '
    'signedChallenge == null || message == null throw';

Map<String, Object?> _indexes(Result r) {
  final text = r.file('indexes.js');
  final json = text.substring(text.indexOf('= ') + 2).trim();
  return jsonDecode(json.substring(0, json.length - 1)) as Map<String, Object?>;
}

Map<String, Object?> _exit(Map<String, Object?> ix, String step, String id) =>
    ((((ix['flows'] as Map)['share-record'] as Map)['steps'] as Map)[step]
        as Map)['exits'][id] as Map<String, Object?>;

void main() {
  late Harness h;
  late Chrome chrome;
  late Result built;
  setUpAll(() async {
    h = await Harness.open();
    chrome = await Chrome.start();
    built = await h.build();
    final ix = await h.indexes(data: built.data);
    expect(ix.code, 0, reason: '$ix');
  });
  tearDownAll(() async {
    await chrome.close();
    await h.close();
  });

  Future<String> exitRow(String step, String id) async {
    final page = await chrome
        .open('${pageOver(built.data, h.temp)}#flow=share-record&step=$step');
    await page.waitFor(
        'document.body.getAttribute("data-ready") === "share-record.$step"');
    return (await page.eval('Array.from(document.querySelectorAll("tr.exit"))'
        '.filter(r => r.getAttribute("data-exit") === ${jsonEncode(id)})'
        '.map(r => r.textContent)[0] || ""')) as String;
  }

  test('An exit a test\'s string literal holds is named by that test',
      () async {
    final ev = _exit(
        _indexes(Result(0, [], built.data)), 'bob-server-accept', _sharedBy);
    expect(ev['status'], 'named');
    final tests = (ev['tests'] as List).cast<Map>();
    expect(tests.map((t) => t['path']),
        contains('packages/at_secondary_server/test/notify_verb_test.dart'),
        reason: 'notify_verb_test.dart holds "@eve is not authorized to send '
            'notification as @bob"');
    final row = await exitRow('bob-server-accept', _sharedBy);
    expect(row, contains('named by (text match)'));
    for (final t in tests) {
      expect(row, contains(t['test'] as String),
          reason: 'the page lists each test whose literal holds the text');
    }
  });

  test('An exit no test names says so', () async {
    final ev = _exit(
        _indexes(Result(0, [], built.data)), 'bob-server-pol', _signature);
    expect(ev['status'], 'none',
        reason: 'no at_server test literal holds "Unable to verify '
            'signature"');
    final row = await exitRow('bob-server-pol', _signature);
    expect(
        row,
        allOf(contains('throw AtException'),
            contains("'Unable to verify signature'")),
        reason: 'the row is the exit raising that message');
    expect(row, contains('no test names this'));
  });

  test('The job reports test evidence against the recorded figure', () async {
    final clean = await h.check();
    expect(
        clean.lines,
        contains(startsWith('REPORT test evidence for share-record: 14 exits '
            'named by a test (text match); recorded 14')),
        reason: 'ratchet.yaml records the figure the committed tree gives');

    const certTest =
        'packages/at_secondary_server/test/from_client_certificate_test.dart';
    final fewer = h
        .serverFile(certTest)
        .replaceAll('Certificate Verification Failed', 'refused');
    final r = await h.check(server: {certTest: fewer});
    expect(r.code, 0, reason: 'a fall is reported, never failed: $r');
    expect(
        r.lines,
        contains('REPORT test evidence for share-record: 13 exits named by a '
            'test (text match); recorded 14; no longer named: '
            'bob-server-from: FromVerbHandler.processVerb !result throw'),
        reason: 'the report gives the figure, the recorded figure and the '
            'exits no longer named: $r');
  });
}
