import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/util/keys_problem.dart';
import 'package:test/test.dart';

/// The one message `reportKeysProblem` writes for keys holding pending
/// enrollment requests.
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
      expect(lines.join('\n'), isNot(contains('Wait for')));
    });
  });

  group('Given keys holding only pending enrollment requests', () {
    test(
        'when one is reported, then the report names its id in the singular '
        'and says to wait for it', () {
      final lines = stderrOf(() => reportKeysProblem(
          AtEnrollmentPendingException(atSign, ['e-1']),
          absentHint: const []));

      expect(lines, [
        'This keyfile holds only a pending enrollment request for $atSign '
            '(id e-1). Wait for it to be approved, then run this command '
            'again.',
        keysProblemFooter,
      ]);
    });

    test(
        'when two are reported, then the report names both ids in the plural '
        'and says to wait for them', () {
      final lines = stderrOf(() => reportKeysProblem(
          AtEnrollmentPendingException(atSign, ['e-1', 'e-2']),
          absentHint: const []));

      expect(lines, [
        'This keyfile holds only pending enrollment requests for $atSign '
            '(ids e-1, e-2). Wait for them to be approved, then run this '
            'command again.',
        keysProblemFooter,
      ]);
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
