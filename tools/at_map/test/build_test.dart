/// What `at_map build` writes, what it refuses to write, and what its inputs
/// pin.
///
/// Catalogue: features/at_map/sdk_map.feature
library;

import 'dart:io';

import 'package:at_map/at_map.dart';
import 'package:at_map/src/source.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

const _pin = 'd654f25bd4bdef2668c77556f563f9e43960b325';
const _prodSha = '3c3bd74b659b8f81f21c340ada455f9cda536fab';

void main() {
  late Harness h;
  setUpAll(() async => h = await Harness.open());
  tearDownAll(() => h.close());

  test('A build writes share-record\'s files', () async {
    final r = await h.build();
    expect(r.code, 0, reason: 'the committed model builds: $r');
    final model = loadModel(Tree('sdk', repoRoot())).model!;
    for (final f in ['flows/share-record.js', 'flows/share-record.md']) {
      final text = r.file(f);
      expect(text, contains(model.hash),
          reason: '$f records the model hash it was built from');
      expect(text, contains(_pin), reason: '$f records the at_server SHA');
      expect(text, contains(_prodSha),
          reason: '$f records the production tag\'s SHA');
    }
  });

  test('A rebuild is byte-identical', () async {
    final first = await h.build();
    final second = await h.build();
    expect(first.code, 0, reason: '$first');
    final a = snapshot(first.data);
    final b = snapshot(second.data);
    expect(a.keys, containsAll(['core.js', 'flows/share-record.js']),
        reason: 'a build writes files, so the comparison compares something');
    expect(b, equals(a),
        reason: 'the same inputs must give the same bytes, with nothing '
            'time-dependent in them');
  });

  test('A new production tag changes no build', () async {
    final before = await h.build();
    final repo = h.cloneServerGit();
    gitIn(repo, ['tag', 'p3.99.0', _pin]);
    expect(gitIn(repo, ['rev-parse', 'p3.99.0^{commit}']), _pin,
        reason: 'the later tag exists in the repository the build reads');
    final after = await h.build(serverGit: repo);
    expect(after.code, 0, reason: '$after');
    expect(snapshot(after.data), equals(snapshot(before.data)),
        reason: 'a build reads production by its pinned SHA, never by the '
            'newest tag');
  });

  test('A production tag moved to another commit fails the map job', () async {
    final repo = h.cloneServerGit();
    gitIn(repo, ['tag', '-f', 'p3.19.0', _pin]);
    final r = await h.check(serverGit: repo);
    expect(r.code, isNot(0), reason: 'a moved tag fails the job: $r');
    expect(
        r.failures,
        contains(allOf(contains('p3.19.0'), contains(_prodSha),
            contains('resolves to $_pin'))),
        reason: 'the failure names the tag, the pinned SHA and the SHA it '
            'now resolves to');
  });

  test('YAML aliases over the cap fail the build', () async {
    const file = 'docs/map/model/lenses.yaml';
    final bomb =
        StringBuffer('\nbomb:\n  a0: &a0 [x, x, x, x, x, x, x, x, x]\n');
    for (var i = 1; i < 8; i++) {
      bomb.writeln('  a$i: &a$i [${List.filled(9, '*a${i - 1}').join(', ')}]');
    }
    final r = await h.build(sdk: {file: h.sdkFile(file) + bomb.toString()});
    expect(r.code, isNot(0));
    expect(r.failures,
        contains(allOf(contains(file), contains('aliases expand past'))),
        reason: 'the failure names the file whose aliases blew the cap: $r');

    final small = await h.build(
        sdk: {file: '${h.sdkFile(file)}\nsmall:\n  a: &a [x]\n  b: *a\n'});
    expect(small.text, isNot(contains('aliases expand past')),
        reason: 'one alias within the cap is not refused as one');
  });

  test('A link outside the allowlist fails the build', () async {
    final yaml = edit(
        h.sdkFile(flowYaml),
        '      contains: "_refuseForeignAtSigns(verbParams,"\n',
        '      contains: "_refuseForeignAtSigns(verbParams,"\n'
            '    links:\n'
            '      - {title: Elsewhere, href: "https://example.com/notes"}\n'
            '      - {title: Script, href: "javascript:alert(1)"}\n'
            '      - {title: Ours, href: "https://github.com/atsign-foundation/at_server"}\n'
            '      - {title: Here, href: packages/at_client/README.md}\n');
    final r = await h.build(sdk: {flowYaml: yaml});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        containsAll([
          allOf(contains('share-record.bob-server-accept'),
              contains('"https://example.com/notes"')),
          allOf(contains('share-record.bob-server-accept'),
              contains('"javascript:alert(1)"')),
        ]),
        reason: 'each refused link is named with the step holding it: $r');
    expect(r.text,
        isNot(contains('"https://github.com/atsign-foundation/at_server"')),
        reason: 'a page under atsign-foundation is allowed');
    expect(r.text, isNot(contains('"packages/at_client/README.md"')),
        reason: 'a path in this repository is allowed');
  });

  test('A file over its size budget fails the build', () async {
    final extra = StringBuffer();
    for (var i = 0; i < 200; i++) {
      extra.writeln('  - {id: bulk-$i, lane: alice.client, sublane: '
          'LocalSecondary, intent: x, anchor: {code: "sdk:packages/at_client/'
          'lib/src/client/local_secondary.dart", symbol: LocalSecondary._update}, '
          'reached: {via: untraced, note: x}}');
    }
    final yaml = '${h.sdkFile(flowYaml)}\n$extra';
    expect(yaml.length, lessThan(64 * 1024),
        reason: 'the change is within the model file cap, so it is the flow '
            'file budget that refuses it');
    final r = await h.build(sdk: {flowYaml: yaml});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(
            contains('docs/map/data/flows/share-record.js'),
            matches(RegExp(r'would be \d+ bytes')),
            contains('budget of ${1536 * 1024}'))),
        reason: 'the failure names the file, its size and the budget: '
            '${r.failures}');
  });

  test('Model text naming an atSign other than @alice or @bob fails the build',
      () async {
    final note = await h.build(sdk: {
      flowYaml: edit(
          h.sdkFile(flowYaml),
          'note: the put transformer reaches it through the crypto provider the key\'s write selected',
          'note: handed over by @carol\'s client')
    });
    expect(note.code, isNot(0));
    expect(note.failures, contains(contains('names @carol')), reason: '$note');
    final sample = await h.build(sdk: {
      flowYaml: edit(
          h.sdkFile(flowYaml), 'sample: "from:@alice"', 'sample: "from:@dave"')
    });
    expect(sample.code, isNot(0));
    expect(sample.failures, contains(contains('names @dave')),
        reason: '$sample');
  });

  test('A step reached from itself fails the build', () async {
    final yaml = edit(
        h.sdkFile(flowYaml),
        '    reached:\n      from: alice-put\n    reviewed: 06f7912c16904574\n',
        '    reached:\n      from: alice-route\n    reviewed: 06f7912c16904574\n');
    final r = await h.build(sdk: {flowYaml: yaml});
    expect(r.code, isNot(0));
    expect(
        r.failures,
        contains(allOf(contains('share-record.alice-route'),
            contains('not an earlier step'))),
        reason: '$r');
  });

  test('A repository link the page would refuse fails the build', () async {
    final yaml = edit(
        h.sdkFile(flowYaml),
        '      contains: "_refuseForeignAtSigns(verbParams,"\n',
        '      contains: "_refuseForeignAtSigns(verbParams,"\n'
            '    links:\n'
            '      - {title: Usage, href: "packages/at_client/README.md#usage"}\n');
    final r = await h.build(sdk: {flowYaml: yaml});
    expect(r.code, isNot(0));
    expect(
        r.failures, contains(contains('"packages/at_client/README.md#usage"')),
        reason: 'the gate allows only the links the page draws: $r');
  });

  test('The server tree lists tracked files only', () async {
    final repo = h.cloneServerGit().replaceAll('.git', '-tree');
    gitIn(h.temp.path, ['clone', '--quiet', '--shared', h.ws.server.dir, repo]);
    File('$repo/packages/at_secondary_server/test/scratch_test.dart')
        .writeAsStringSync("void main() { print('untracked literal'); }\n");
    final tracked = Tree('server', repo, tracked: true).files();
    expect(tracked,
        contains('packages/at_secondary_server/test/notify_verb_test.dart'));
    expect(tracked,
        isNot(contains('packages/at_secondary_server/test/scratch_test.dart')),
        reason: 'a file CI\'s clone never has must not change a build');
  });

  test('A retired step id cannot be reused', () async {
    final retired =
        edit(h.sdkFile(flowYaml), 'retired: []', 'retired: [old-step]');
    final yaml = '$retired\n  - id: old-step\n'
        '    lane: bob.client\n'
        '    sublane: Monitor\n'
        '    intent: A step that reuses a retired id.\n'
        '    anchor:\n'
        '      code: sdk:packages/at_client/lib/src/manager/monitor.dart\n'
        '      symbol: Monitor.start\n'
        '    reached: {via: untraced, note: x}\n';
    final r = await h.check(sdk: {flowYaml: yaml});
    expect(r.code, isNot(0));
    expect(r.failures,
        contains(allOf(contains('share-record.old-step'), contains('retired'))),
        reason: 'the failure names the reused id: $r');
  });
}
