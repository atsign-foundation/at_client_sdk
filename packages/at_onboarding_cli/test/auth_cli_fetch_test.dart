import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;
import 'package:at_onboarding_cli/src/cli/auth_cli_args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockRemoteSecondary extends Mock implements RemoteSecondary {}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// Collects what `at_activate fetch` prints.
class _CapturedStdout extends Fake implements Stdout {
  final List<String> written = [];

  String get text => written.join();

  @override
  void write(Object? object) => written.add('$object');

  @override
  void writeln([Object? object = '']) => written.add('$object\n');
}

/// Catalogue: features/enrollment/approver_sees_expiry.feature
void main() {
  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  test(
      'at_activate fetch prints the expiry an enrollment asked for and when '
      'it expires', () async {
    const b = 'b0b0b0b0-1a2e-43e4-93bd-378f1d366ea7';
    const printedPrefix = 'Fetched enrollment OK: ';
    final client = _MockAtClient();
    final remote = _MockRemoteSecondary();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.getRemoteSecondary()).thenReturn(remote);
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      final String command =
          (invocation.positionalArguments.first as VerbBuilder).buildCommand();
      if (!command.startsWith('enroll:fetch:')) {
        throw StateError('this rig answers enroll:fetch only, not $command');
      }
      return 'data:${jsonEncode({
            'appName': 'wavi',
            'deviceName': 'phone',
            'namespace': {'wavi': 'rw'},
            'status': 'pending',
            'apkamKeysExpiryInMillis': 3600000,
            'expiresAt': '2026-10-14T09:00:00.000Z',
          })}';
    });
    final args = AuthCliArgs()
        .createFetchCommandParser()
        .parse(['-a', '@alice', '-i', b]);
    final out = _CapturedStdout();

    await IOOverrides.runZoned(() => auth_cli.fetch(args, client),
        stdout: () => out);

    final String line = out.text.trim();
    expect(line, startsWith(printedPrefix));
    final Map<String, dynamic> printed =
        jsonDecode(line.substring(printedPrefix.length));
    expect(printed['apkamKeysExpiryInMillis'], 3600000,
        reason: 'the 1-hour expiry B asked for');
    expect(printed['expiresAt'], '2026-10-14T09:00:00.000Z',
        reason: 'when B\'s record expires');
  });
}
