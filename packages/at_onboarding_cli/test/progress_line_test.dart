import 'package:at_onboarding_cli/src/cli/auth_cli.dart';
import 'package:at_utils/at_progress.dart';
import 'package:chalkdart/chalk.dart';
import 'package:test/test.dart';

/// Catalogue: features/at_utils/web_safe.feature
void main() {
  test('A CLI still colours its progress output', () {
    final level = chalk.level;
    chalk.level = 3;
    addTearDown(() => chalk.level = level);
    ProgressEvent event(ProgressEventType type) =>
        ProgressEvent(group: 'activate', msg: 'keys stored', type: type);

    final warning = progressLine(event(ProgressEventType.warning), 10);
    final error = progressLine(event(ProgressEventType.error), 10);

    expect(warning, contains('\x1b['),
        reason: 'the group is coloured where the terminal takes colour');
    expect(warning.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), ''),
        '  activate : keys stored');
    expect(warning, isNot(error), reason: 'the colour follows the type');
  });
}
