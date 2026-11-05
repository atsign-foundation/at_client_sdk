/// Every scenario of the SDK map's feature file has a test of the same
/// title.
///
/// Catalogue: features/at_map/sdk_map.feature
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  test('every scenario has a test titled as it is', () {
    final feature = File(p.join(repoRoot(), featureFile)).readAsStringSync();
    final titles = RegExp(r'^\s*Scenario: (.+?)\s*$', multiLine: true)
        .allMatches(feature)
        .map((m) => m.group(1)!)
        .toList();
    expect(titles, hasLength(53),
        reason: 'the feature file holds 53 scenarios; a different count means '
            'this parse stopped finding them');

    final tests = <String>{};
    for (final f in Directory(p.join(repoRoot(), 'tools/at_map/test'))
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))) {
      tests.addAll(RegExp(r"test\(\s*'((?:\\.|[^'\\])*)'")
          .allMatches(f.readAsStringSync())
          .map((m) => m.group(1)!.replaceAll(r"\'", "'")));
    }
    final missing = titles.where((t) => !tests.contains(t)).toList();
    expect(missing, isEmpty,
        reason: 'each scenario needs a test whose title is the scenario '
            'title, so a reader can find its proof by name');
  });
}
