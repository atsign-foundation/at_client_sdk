/// The production tag feeds one lane note; step-by-step comparison is local.
///
/// Catalogue: features/at_map/sdk_map.feature
library;

import 'dart:io';

import 'package:at_map/src/decls.dart';
import 'package:at_map/src/source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/harness.dart';

const _prodSha = '3c3bd74b659b8f81f21c340ada455f9cda536fab';
const _manager =
    'packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart';

void main() {
  late Harness h;
  setUpAll(() async => h = await Harness.open());
  tearDownAll(() => h.close());

  test('Nothing public names a step as differing from production', () async {
    final atProd = GitRefTree(h.ws.server.dir, _prodSha).read(_manager)!;
    expect(
        indexDeclarations(
            parseUnit(atProd))['NotificationManager._pushToMonitors'],
        isNull,
        reason: '_pushToMonitors is absent at p3.19.0, so there is a '
            'difference a public file could name');
    expect(
        indexDeclarations(parseUnit(h.serverFile(_manager)))[
            'NotificationManager._pushToMonitors'],
        isNotNull);

    final built = await h.build();
    expect(built.code, 0, reason: '$built');
    final checked = await h.check();
    final note = flowJson(built)['laneNote'] as String;
    expect(note, contains('p3.19.0'));

    final files = <String, String>{
      for (final dir in [built.data, h.committedData])
        for (final f
            in Directory(dir).listSync(recursive: true).whereType<File>())
          '${p.basename(dir)}/${p.relative(f.path, from: dir)}':
              f.readAsStringSync()
    };
    expect(files.keys, contains('data/flows/share-record.js'),
        reason: 'the committed files are part of what is scanned');
    for (final e in files.entries) {
      final rest = e.value
          .replaceAll(note, '')
          .replaceAll('"productionTag": "p3.19.0"', '')
          .replaceAll('"production": "$_prodSha"', '')
          .replaceAll('Production SHA: `$_prodSha`', '');
      expect(rest, isNot(contains('p3.19.0')),
          reason: '${e.key} names the production tag outside the lane note');
      expect(rest, isNot(contains(_prodSha)),
          reason: '${e.key} names the production SHA outside its pin record');
      expect(rest.toLowerCase(),
          isNot(anyOf(contains('absent at'), contains('differs at'))),
          reason: '${e.key} compares a step with production');
    }
    for (final line in [...built.lines, ...checked.lines]) {
      expect(
          line,
          isNot(allOf(contains('share-record.'),
              anyOf(contains('p3.19.0'), contains('production')))),
          reason: 'a log line names a step beside production');
    }
    expect(checked.code, 0, reason: '$checked');
  });

  test('diff-prod lists the differing steps locally', () async {
    final r = await h.diffProd(env: const {});
    expect(r.code, 0, reason: '$r');
    expect(r.lines,
        contains(startsWith('share-record.bob-server-push: absent at p3.19.0')),
        reason: '$r');
  });

  test('diff-prod refuses to run in CI', () async {
    final r = await h.diffProd(env: const {'CI': 'true'});
    expect(r.code, isNot(0));
    expect(r.text, isNot(contains('share-record.')),
        reason: 'it prints no step: $r');
  });
}
