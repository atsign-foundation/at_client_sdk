import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/util/keys_problem.dart';
import 'package:test/test.dart';

/// The one message `reportKeysProblem` writes for keys holding pending
/// enrollment requests or no credential.
void main() {
  const atSign = '@alice';

  /// The lines [report] writes to stderr, without colour or blank lines.
  List<String> stderrOf(void Function() report) {
    final err = _Captured();
    IOOverrides.runZoned(report, stderr: () => err);
    return err.text
        .replaceAll(RegExp(r'\x1b\[[0-9;]*[A-Za-z]'), '')
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();
  }

  group(
      'Given AtEnrollmentPendingException.several for two pending enrollment '
      'requests that match', () {
    test(
        'when it is reported, then the report gives that case\'s own '
        'instruction and no wait', () {
      final several =
          AtEnrollmentPendingException.several(atSign, ['e-1', 'e-2']);

      final lines =
          stderrOf(() => reportKeysProblem(several, absentHint: const []));

      expect(lines, [several.message, keysProblemFooter]);
      expect(lines.first, contains('name both the app and the device'));
      expect(lines.join('\n'), isNot(contains('is approved')));
    });
  });

  group('Given keys holding only pending enrollment requests', () {
    test(
        'when one is reported, then the report names its id in the singular '
        'and says to run the same enroll command again once it is approved',
        () {
      final lines = stderrOf(() => reportKeysProblem(
          AtEnrollmentPendingException(atSign, ['e-1']),
          absentHint: const []));

      expect(lines, [
        'This keyfile holds only a pending enrollment request for $atSign '
            '(id e-1). Once it is approved, run the same at_activate enroll '
            'command again to finish it.',
        keysProblemFooter,
      ]);
    });

    test(
        'when two are reported, then the report names both ids in the plural '
        'and says to run the enroll command that made one again once it is '
        'approved', () {
      final lines = stderrOf(() => reportKeysProblem(
          AtEnrollmentPendingException(atSign, ['e-1', 'e-2']),
          absentHint: const []));

      expect(lines, [
        'This keyfile holds only pending enrollment requests for $atSign '
            '(ids e-1, e-2). Once one is approved, run the at_activate enroll '
            'command that made it again to finish it.',
        keysProblemFooter,
      ]);
    });

    test('when two are reported with their keyfile, then the report names it',
        () {
      final lines = stderrOf(() => reportKeysProblem(
          AtEnrollmentPendingException(atSign, ['e-1', 'e-2'],
              source: '/keys/alice.atKeys'),
          absentHint: const []));

      expect(lines, [
        'The keyfile at /keys/alice.atKeys holds only pending enrollment '
            'requests for $atSign (ids e-1, e-2). Once one is approved, run '
            'the at_activate enroll command that made it again to finish it.',
        keysProblemFooter,
      ]);
    });
  });

  group('Given keys holding no credential', () {
    test('when reported with their keyfile, then the report names it', () {
      final lines = stderrOf(() => reportKeysProblem(
          AtNoCredentialException(atSign, source: '/keys/alice.atKeys'),
          absentHint: const []));

      expect(lines, [
        'The keyfile at /keys/alice.atKeys holds no credential for $atSign: '
            'its enrollment was denied, cancelled or expired, or never '
            'completed. Enroll this machine again.',
        keysProblemFooter,
      ]);
    });

    test('when reported with no keyfile, then the report gives its message',
        () {
      final noCredential = AtNoCredentialException(atSign);

      final lines =
          stderrOf(() => reportKeysProblem(noCredential, absentHint: const []));

      expect(lines, [noCredential.message, keysProblemFooter]);
    });
  });
}

/// Collects what is written to it, for a test to read.
class _Captured implements Stdout {
  final List<String> written = [];

  String get text => written.join();

  @override
  void write(Object? object) => written.add('$object');

  @override
  void writeln([Object? object = '']) => written.add('$object\n');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
