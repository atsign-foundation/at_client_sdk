/// Guards the wiring that **populates** the acceptance ledger.
///
/// `acceptance_ledger_test.dart` guards the join — what the renderer does with
/// the citations and the reports once it has them. The step before that was
/// unguarded: whether the suites still *emit* those inputs at all.
///
/// Why that matters more than it looks. Each emitting job carries an
/// environment variable or a reporter flag, and each uploads its artefact with
/// `if-no-files-found: warn`. So a job that quietly stops emitting leaves the
/// build **green**, the upload merely warns, and the ledger reports fewer rows
/// as exercised. That failure does not look like a failure — it looks like a
/// coverage report, which is the same reason the join underneath it is pinned.
///
/// This reads the workflow and the runner scripts as text rather than parsing
/// YAML, matching the other rails here, and it checks what the jobs
/// **declare**. That is the right question: the declaration *is* the
/// mechanism — an absent `--file-reporter` writes no report however the job
/// otherwise behaves.
library;

import 'dart:io';

import 'package:test/test.dart';

/// The repo root, found by walking up from the current directory.
///
/// `dart test` runs from the package root, but this file's inputs live outside
/// the package, so neither a relative path nor the package root will do.
Directory repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/.github/workflows').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('no .github/workflows above ${Directory.current.path}');
    }
    dir = parent;
  }
}

/// The workflow's jobs, as name → the block of text belonging to that job.
///
/// A job is a 2-space-indented key **under `jobs:`**, and the qualifier is the
/// whole difficulty: `on:` has 2-space-indented keys too, so a matcher that
/// only knows the indentation returns `workflow_dispatch`, `push` and
/// `pull_request` as though they were jobs. The negative control below is
/// exactly that case.
Map<String, String> jobsOf(String workflow) {
  final lines = workflow.split('\n');
  final start = lines.indexWhere((l) => l.trimRight() == 'jobs:');
  if (start < 0) return {};

  final jobs = <String, String>{};
  String? current;
  final buffer = <String>[];
  final header = RegExp(r'^  ([A-Za-z_][A-Za-z0-9_-]*):\s*$');

  void flush() {
    final name = current;
    if (name != null) jobs[name] = buffer.join('\n');
    buffer.clear();
  }

  for (final line in lines.skip(start + 1)) {
    // A non-indented, non-blank line ends the jobs mapping entirely.
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
      break;
    }
    final match = header.firstMatch(line);
    if (match != null) {
      flush();
      current = match.group(1);
      continue;
    }
    if (current != null) buffer.add(line);
  }
  flush();
  return jobs;
}

/// Whether [block] asks its runner for the machine-readable stream the ledger
/// joins against.
bool emitsReport(String block) => block.contains('--file-reporter json:');

/// Whether [block] uploads what it emitted, unconditionally.
///
/// `if: always()` is part of the contract rather than a nicety: a suite that
/// **failed** is when knowing which rows lost their proof matters most, and an
/// upload skipped on failure loses exactly that run.
bool uploadsReport(String block) =>
    block.contains('acceptance-report-') && block.contains('always()');

void main() {
  late String workflow;
  late Map<String, String> jobs;

  /// The jobs that feed the ledger, and what each is for.
  const emittingJobs = <String, String>{
    'unit_at_client': 'the 67 citations that point at in-package unit tests, '
        'and the citation record itself',
    'functional_tests': 'the largest live pack',
    'pqe2e_tests': 'the cross-atSign rows',
    'legacy_server_tests': 'UC-B0.1, which no other job can exercise because '
        'it needs a pinned pre-PQ atServer',
  };

  setUpAll(() {
    final file =
        File('${repoRoot().path}/.github/workflows/at_client_sdk.yaml');
    expect(file.existsSync(), isTrue,
        reason: 'the workflow is this rail\'s input; without it the '
            'assertions below would all pass against an empty string');
    workflow = file.readAsStringSync();
    jobs = jobsOf(workflow);
  });

  group('the job matcher', () {
    // Both controls, drawn from the file rather than invented: without them a
    // broken extractor and a correctly-wired workflow print the same nothing.
    test('finds real jobs and rejects the keys under `on:`', () {
      expect(jobs.keys, contains('unit_at_client'),
          reason: 'positive control: a job that is definitely there');
      expect(jobs.keys, contains('legacy_server_tests'),
          reason: 'positive control at the other end of the file, so a '
              'matcher that stops early is caught');
      expect(jobs.keys, isNot(contains('workflow_dispatch')),
          reason: 'negative control, and the one this matcher gets wrong: '
              '`on:` carries 2-space-indented keys too, so an extractor '
              'keyed on indentation alone reports triggers as jobs');
      expect(jobs.keys, isNot(contains('push')),
          reason: 'the same trap, second instance');
    });

    test('a job block carries that job\'s own steps and not its neighbour\'s',
        () {
      expect(jobs['functional_tests'], contains('tests/at_functional_test'),
          reason: 'a block that did not contain its own working-directory '
              'would mean the split landed in the wrong place, and every '
              'per-job assertion below would be about the wrong text');
      expect(jobs['functional_tests'], isNot(contains('legacy-server')),
          reason: 'and it must not have swallowed a later job, or an absent '
              'flag in one job would be masked by its presence in another');
    });

    test('the predicates discriminate', () {
      const wired = '''
        run: dart test --concurrency=1 --file-reporter json:acceptance-report.json
      - name: Upload it
        if: \${{ always() }}
        with:
          name: acceptance-report-something
''';
      const unwired = '''
        run: dart test --concurrency=1
      - name: Upload something else
        with:
          name: coverage
''';
      expect(emitsReport(wired), isTrue);
      expect(emitsReport(unwired), isFalse);
      expect(uploadsReport(wired), isTrue);
      expect(uploadsReport(unwired), isFalse);
    });
  });

  group('every job that feeds the ledger still does', () {
    for (final entry in emittingJobs.entries) {
      test('${entry.key} emits and uploads a report', () {
        final block = jobs[entry.key];
        expect(block, isNotNull,
            reason: 'this job supplies ${entry.value}. If it was renamed, '
                'rename it here too — a job the ledger expects and cannot '
                'find is indistinguishable from one that ran and proved '
                'nothing');
        expect(emitsReport(block!), isTrue,
            reason: '${entry.key} supplies ${entry.value}, and without '
                '`--file-reporter json:` it writes no report. The rows it '
                'covers would then read NOT-EXERCISED while the job itself '
                'passed, which reads as missing coverage rather than as '
                'missing wiring');
        expect(uploadsReport(block), isTrue,
            reason: '${entry.key} must upload what it emitted, and with '
                '`always()`: a run that FAILED is when knowing which rows '
                'lost their proof matters most');
      });
    }

    test('unit_at_client also records the citations', () {
      expect(jobs['unit_at_client'], contains('ACCEPTANCE_LEDGER:'),
          reason: 'the citations are half the join, and this is the only job '
              'that records them — `provenIn` is inert unless '
              'ACCEPTANCE_LEDGER names a path. Without it the ledger has '
              'reports and nothing to join them to, and every row reads '
              'NO-LIVE-CITATION');
    });

    test('no job emits a report without uploading it', () {
      final emitted = jobs.entries.where((e) => emitsReport(e.value));
      expect(emitted, isNotEmpty,
          reason: 'if nothing emits, this guard is checking nothing');
      for (final e in emitted) {
        expect(uploadsReport(e.value), isTrue,
            reason: '${e.key} writes a report and does not upload it, so the '
                'work is done and thrown away. Either upload it or stop '
                'emitting it');
      }
    });
  });

  group('the local runners honour ACCEPTANCE_REPORT', () {
    // The live packs are how a ledger gets rendered off a developer's machine,
    // and each is a separate script that opted in separately.
    const runners = [
      'tests/at_functional_test/runLocal.sh',
      'tests/at_end2end_test/runLocal.sh',
      'tests/at_onboarding_cli_functional_tests/runLocal.sh',
    ];

    for (final path in runners) {
      test('$path turns ACCEPTANCE_REPORT into a reporter flag', () {
        final file = File('${repoRoot().path}/$path');
        expect(file.existsSync(), isTrue,
            reason: 'a runner this rail names and cannot find has either '
                'moved or gone; either way the ledger lost an input');
        final source = file.readAsStringSync();

        // ⚠️ Pin the COUPLING, not the two ends of it. This read
        //   expect(source, contains('ACCEPTANCE_REPORT'))
        //   expect(source, contains('--file-reporter json:'))
        // and a mutation that made the guard test a *different* variable left
        // both satisfied — the flag line and the echo still name
        // ACCEPTANCE_REPORT, so the strings were all present while nothing
        // read the opt-in any more. Two independent substrings can both hold
        // while the wire between them is cut.
        expect(source, contains(r'-n "${ACCEPTANCE_REPORT:-}"'),
            reason: 'the opt-in has to be what GATES the reporter. A runner '
                'that gates on something else emits no report however many '
                'times it mentions ACCEPTANCE_REPORT');
        expect(source, contains(r'--file-reporter json:${ACCEPTANCE_REPORT}'),
            reason: 'and the gated branch has to put that same variable into '
                'the flag, or the opt-in is accepted and the report is '
                'written somewhere nobody asked for');
      });
    }
  });
}
