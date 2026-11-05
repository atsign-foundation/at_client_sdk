/// The weekly drift job: counts in CI, steps locally, and no pin moved.
///
/// Catalogue: features/at_map/sdk_map.feature
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/harness.dart';

const _notifyHandler =
    'packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart';
const _workflow = '.github/workflows/map_drift.yaml';

/// The pinned at_server with a drop added to bob's acceptance path, standing
/// in for a trunk that has moved past the pin.
Map<String, String> movedTrunk(Harness h) => {
      _notifyHandler: edit(
          h.serverFile(_notifyHandler),
          '    if (_isText(verbParams)) {\n      logger.warning(\'Dropped text',
          '    if (verbParams.isEmpty) {\n      response.data = \'data:success\';\n'
              '      return;\n    }\n'
              '    if (_isText(verbParams)) {\n      logger.warning(\'Dropped text')
    };

List<String> _runs(YamlMap job) => [
      for (final s in (job['steps'] as YamlList).cast<YamlMap>())
        if (s['run'] != null) s['run'] as String
    ];

void main() {
  late Harness h;
  setUpAll(() async => h = await Harness.open());
  tearDownAll(() => h.close());

  test('The weekly drift job logs counts, not steps', () async {
    final wf = loadYaml(File(p.join(repoRoot(), _workflow)).readAsStringSync())
        as YamlMap;
    expect((wf['on'] as YamlMap)['schedule'], isNotNull,
        reason: 'the job runs on a schedule');
    final runs = (wf['jobs'] as YamlMap).values.cast<YamlMap>().expand(_runs);
    expect(runs.where((r) => r.contains('at_map check --server')), isNotEmpty,
        reason: 'the job runs at_map check against at_server trunk');

    final r = await h.drift(env: const {'CI': 'true'}, server: movedTrunk(h));
    expect(r.code, 0, reason: '$r');
    expect(
        r.lines,
        contains(matches(RegExp(r'^drift: [1-9]\d* of 15 steps would change '
            r'\(anchors \d+, edges \d+, samples \d+, exits \d+\)$'))),
        reason: 'the log gives the number of steps that would change: $r');
    expect(r.text, isNot(contains('share-record.')),
        reason: 'and names no step');
  });

  test('The drift job moves no pin', () async {
    final roots = File(p.join(repoRoot(), 'docs/map/model/roots.yaml'));
    final before = roots.readAsBytesSync();
    final data = snapshot(h.committedData);
    final repo = h.cloneServerGit();
    gitIn(repo, [
      'tag',
      'p3.99.0',
      gitIn(repo, ['rev-parse', 'HEAD'])
    ]);
    final r = await h.drift(
        env: const {'CI': 'true'}, server: movedTrunk(h), serverGit: repo);
    expect(r.code, 0, reason: '$r');
    expect(roots.readAsBytesSync(), before, reason: 'roots.yaml is unchanged');
    expect(snapshot(h.committedData), data,
        reason: 'the job writes no generated file');

    final wf = loadYaml(File(p.join(repoRoot(), _workflow)).readAsStringSync())
        as YamlMap;
    expect(wf['permissions'], {'contents': 'read'},
        reason: 'the job cannot push a commit');
    for (final run
        in (wf['jobs'] as YamlMap).values.cast<YamlMap>().expand(_runs)) {
      for (final word in ['git commit', 'git push', 'gh pr', 'roots.yaml']) {
        expect(run, isNot(contains(word)),
            reason: 'the job makes no commit and moves no pin');
      }
    }
  });

  test('check --server lists the drifting steps locally', () async {
    final r = await h.drift(env: const {}, server: movedTrunk(h));
    expect(r.code, 0, reason: '$r');
    expect(
        r.lines,
        contains(allOf(startsWith('  share-record.bob-server-accept: '),
            contains('anchors'), contains('exits'))),
        reason: 'outside CI it lists each step that would change: $r');
  });
}
