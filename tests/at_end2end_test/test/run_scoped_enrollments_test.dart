/// Proves the scenarios in `features/e2e/run_scoped_enrollments.feature` that
/// can be shown without an atServer.
///
/// Pure local inspection; it talks to no atServer.
library;

import 'dart:io';
import 'dart:math';

import 'package:at_end2end_test/src/run_marker.dart';
import 'package:test/test.dart';

/// Each spelling of a call or verb that revokes an enrollment.
final _revokes = RegExp(r'\brevoke\s*\(|EnrollmentRequestDecision\.revoked\b|'
    r'enroll:revoke\b|EnrollOperationEnum\.revoke\b');

/// Each spelling of a call or verb that denies an enrollment.
final _denies = RegExp(r'\bdeny\s*\(|EnrollmentRequestDecision\.denied\b|'
    r'enroll:deny\b|EnrollOperationEnum\.deny\b');

/// The spelling of the approval `enrollment_setup.dart` makes, which every
/// scan below must find there before its silence about the others counts.
final _approves = RegExp(r'\bapprove\s*\(');

const _thisFile = 'test/run_scoped_enrollments_test.dart';

/// Every Dart file in this pack that can run against the long-lived atSigns:
/// all of `lib/` and `test/` except `test/pq/`, which only ever runs against
/// a virtualenv it starts and throws away.
Map<String, String> _sourcesThatReachTheSharedAtSigns() {
  final sources = <String, String>{};
  for (final root in ['lib', 'test']) {
    for (final file in Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final path = file.path.replaceAll(r'\', '/');
      // NOTE: this file names the spellings it looks for.
      if (path.startsWith('test/pq/') || path == _thisFile) continue;
      sources[path] = file.readAsStringSync();
    }
  }
  return sources;
}

/// The files among [sources] that [spelling] matches.
List<String> _matching(Map<String, String> sources, RegExp spelling) => [
      for (final entry in sources.entries)
        if (spelling.hasMatch(entry.value)) entry.key
    ]..sort();

/// Fails unless [sources] holds `enrollment_setup.dart` and the approval in
/// it is found, so that a scan finding nothing has read the file it matters
/// for.
void _expectTheScanReachesSetup(Map<String, String> sources) {
  expect(sources.keys, contains('test/enrollment_setup.dart'),
      reason: 'cwd is ${Directory.current.path}; the scan must start at the '
          'package root, where it finds the enrollment setup');
  expect(_matching(sources, _approves), contains('test/enrollment_setup.dart'),
      reason: 'the scan no longer finds the approval enrollment_setup.dart '
          'makes, so finding no deny or revoke beside it proves nothing');
}

/// The `end2end_test_14` job from the workflow that runs this pack against
/// the long-lived atSigns.
String _end2endTest14Job() {
  final workflow = File('../../.github/workflows/at_client_sdk.yaml');
  expect(workflow.existsSync(), isTrue,
      reason: 'cwd is ${Directory.current.path}; the workflow is read from '
          'two directories up');
  final lines = workflow.readAsLinesSync();
  final start = lines.indexOf('  end2end_test_14:');
  expect(start, isNot(-1),
      reason: 'the workflow has no end2end_test_14 job, so there is nothing '
          'here to check the steps of');
  final end = lines.indexWhere(
      (l) => RegExp(r'^  [A-Za-z0-9_-]+:\s*$').hasMatch(l), start + 1);
  return lines.sublist(start, end < 0 ? lines.length : end).join('\n');
}

/// The paths `dart_test.yaml` allows a bare `dart test` to run.
List<String> _allowlist() {
  final lines = File('dart_test.yaml').readAsLinesSync();
  final start = lines.indexWhere((l) => l.trimRight() == 'paths:');
  final paths = <String>[];
  for (final line in lines.skip(start + 1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (!trimmed.startsWith('- ')) break;
    paths.add(trimmed.substring(2).trim());
  }
  return paths;
}

void main() {
  test("Another run finishing does not revoke this run's approved enrollment",
      () {
    final sources = _sourcesThatReachTheSharedAtSigns();
    _expectTheScanReachesSetup(sources);
    expect(_matching(sources, _revokes), isEmpty,
        reason: 'these files revoke an enrollment, and every run shares the '
            'atSigns they run against, so a run finishing can revoke another '
            "run's. The atServer retires each enrollment at its own expiry");
  });

  test("Another run finishing does not deny this run's pending enrollment", () {
    final sources = _sourcesThatReachTheSharedAtSigns();
    _expectTheScanReachesSetup(sources);
    expect(_matching(sources, _denies), isEmpty,
        reason: 'these files deny an enrollment, and every run shares the '
            'atSigns they run against, so a run finishing can deny another '
            "run's before it is approved");
  });

  test('The job leaves its enrollments to expire', () {
    final job = _end2endTest14Job();
    final named = RegExp(r'(?:^|\s)(test/[\w/]+\.dart)', multiLine: true)
        .allMatches(job)
        .map((m) => m.group(1)!)
        .toSet();
    expect(named, contains('test/enrollment_setup.dart'),
        reason: 'the end2end_test_14 job no longer names the setup it runs, '
            'so this parse of its steps is reading something else');
    expect(job, isNot(contains('enroll:')),
        reason: 'a step in end2end_test_14 sends an enroll verb of its own');

    // NOTE: this file runs in the job too, and talks to no atServer.
    final runs = {...named, ..._allowlist()}..remove(_thisFile);
    expect(runs.where((p) => p.startsWith('test/pq/')), isEmpty,
        reason: 'end2end_test_14 runs post-quantum files against the '
            'long-lived atSigns');
    final sources = _sourcesThatReachTheSharedAtSigns();
    _expectTheScanReachesSetup(sources);
    final missing = runs.where((p) => !sources.containsKey(p)).toList();
    expect(missing, isEmpty,
        reason: 'end2end_test_14 runs files this scan did not read: $missing');
    final deciding = {
      ..._matching(sources, _revokes),
      ..._matching(sources, _denies),
    }.where(runs.contains);
    expect(deciding, isEmpty,
        reason: 'end2end_test_14 runs files that deny or revoke an '
            'enrollment on atSigns every run shares');
  });

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
