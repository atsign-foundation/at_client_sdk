import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:test/test.dart';

/// Collects what a program writes to stderr.
class _CapturedStderr implements Stdout {
  final List<String> written = [];

  String get text => written.join();

  @override
  void write(Object? object) => written.add('$object');

  @override
  void writeln([Object? object = '']) => written.add('$object\n');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Catalogue: features/at_client/notification_drop_reported.feature
void main() {
  test('a CLIBase program puts the SDK\'s warnings on stderr by default',
      () async {
    final level = AtSignLogger.root_level;
    final handler = AtSignLogger.defaultLoggingHandler;
    addTearDown(() {
      AtSignLogger.root_level = level;
      AtSignLogger.defaultLoggingHandler = handler;
    });
    final home = await Directory.systemTemp.createTemp('cli_base_log_level');
    addTearDown(() => home.delete(recursive: true));
    final err = _CapturedStderr();

    await IOOverrides.runZoned(() async {
      CLIBase(
          atSign: '@juliet',
          nameSpace: 'sensor',
          rootDomain: 'root.atsign.org',
          homeDir: home.path);
      final sdk = AtSignLogger('NotificationServiceImpl');
      sdk.warning('Dropping notification @juliet:reading.d1.sensor@india');
      sdk.info('Received @juliet:reading.d1.sensor@india');
    }, stderr: () => err);

    expect(err.text,
        allOf(contains('WARNING|'), contains('Dropping notification')));
    expect(err.text, isNot(contains('Received')),
        reason: 'the control: what is below a warning stays quiet');
  });
}
