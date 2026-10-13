/// Proves the scenarios in `features/e2e/run_scoped_enrollments.feature` that
/// can be shown without an atServer.
///
/// Pure local inspection; it talks to no atServer.
library;

import 'dart:math';

import 'package:at_end2end_test/src/run_marker.dart';
import 'package:test/test.dart';

void main() {
  test('An enrollment names the run that created it', () {
    final marker = runMarker(
        const {'GITHUB_RUN_ID': '38415451898', 'GITHUB_RUN_ATTEMPT': '2'});
    expect(enrollmentAppName(marker, 1072093810),
        startsWith('wavi-38415451898-2-'));

    for (final environment in const <Map<String, String>>[
      {},
      {'GITHUB_RUN_ID': '38415451898'},
      {'GITHUB_RUN_ATTEMPT': '2'},
      {'GITHUB_RUN_ID': '', 'GITHUB_RUN_ATTEMPT': '2'},
    ]) {
      expect(enrollmentAppName(runMarker(environment, random: Random(1)), 7),
          allOf(startsWith('wavi-local-'), isNot(contains('38415451898'))),
          reason: 'with $environment there is no complete run to name, so '
              'the label must not claim one');
    }
  });
}
