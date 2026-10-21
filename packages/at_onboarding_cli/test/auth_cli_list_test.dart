import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;
import 'package:at_onboarding_cli/src/cli/auth_cli_args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockEnrollmentService extends Mock implements EnrollmentService {}

class _FakeListParams extends Fake implements EnrollmentListRequestParam {}

/// Collects what `at_activate list` prints.
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
  setUpAll(() => registerFallbackValue(_FakeListParams()));

  test(
      'at_activate list shows the expiry each enrollment asked for and when '
      'it expires', () async {
    const b = 'b0b0b0b0-1a2e-43e4-93bd-378f1d366ea7';
    final client = _MockAtClient();
    final service = _MockEnrollmentService();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.enrollmentService).thenReturn(service);
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [
              Enrollment.fromJSON({
                'appName': 'wavi',
                'deviceName': 'phone',
                'namespace': {'wavi': 'rw'},
                'status': 'pending',
                'apkamKeysExpiryInMillis': 3600000,
                'expiresAt': '2026-10-14T09:00:00.000Z',
              })
                ..enrollmentId = b
            ]);
    final args =
        AuthCliArgs().createListCommandParser().parse(['-a', '@alice']);
    final out = _CapturedStdout();

    await IOOverrides.runZoned(() => auth_cli.list(args, client),
        stdout: () => out);

    final String row =
        out.text.split('\n').singleWhere((line) => line.startsWith(b));
    expect(row, contains(' 1h '),
        reason: 'the 1-hour expiry B asked for, in the form --expiry takes');
    expect(row, contains('2026-10-14T09:00:00.000Z'),
        reason: 'when B\'s record expires');
  });

  test(
      '--arx and --drx match regardless of the case the user and the '
      'enrollment disagree on', () async {
    const b = 'b0b0b0b0-1a2e-43e4-93bd-378f1d366ea7';
    final client = _MockAtClient();
    final service = _MockEnrollmentService();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.enrollmentService).thenReturn(service);
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [
              Enrollment.fromJSON({
                'appName': 'Wavi',
                'deviceName': 'Phone',
                'namespace': {'wavi': 'rw'},
                'status': 'pending',
                'apkamKeysExpiryInMillis': 3600000,
                'expiresAt': '2026-10-14T09:00:00.000Z',
              })
                ..enrollmentId = b
            ]);
    // Lower-case --arx against an upper-case appName, upper-case --drx
    // against a lower-case-initial deviceName.
    final args = AuthCliArgs()
        .createListCommandParser()
        .parse(['-a', '@alice', '-A', 'wavi', '-D', 'PHONE']);
    final out = _CapturedStdout();

    await IOOverrides.runZoned(() => auth_cli.list(args, client),
        stdout: () => out);

    expect(out.text.split('\n').any((line) => line.startsWith(b)), isTrue,
        reason: 'arx/drx must match case-insensitively');
  });

  test('--arx keeps \\D meaning non-digit rather than folding it with case',
      () async {
    const b = 'b0b0b0b0-1a2e-43e4-93bd-378f1d366ea7';
    final client = _MockAtClient();
    final service = _MockEnrollmentService();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.enrollmentService).thenReturn(service);
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [
              Enrollment.fromJSON({
                'appName': '12345',
                'deviceName': 'phone',
                'namespace': {'wavi': 'rw'},
                'status': 'pending',
                'apkamKeysExpiryInMillis': 3600000,
                'expiresAt': '2026-10-14T09:00:00.000Z',
              })
                ..enrollmentId = b
            ]);
    final args = AuthCliArgs()
        .createListCommandParser()
        .parse(['-a', '@alice', '-A', r'^\D+$']);
    final out = _CapturedStdout();

    await IOOverrides.runZoned(() => auth_cli.list(args, client),
        stdout: () => out);

    expect(out.text.split('\n').any((line) => line.startsWith(b)), isFalse,
        reason: 'a digits-only appName must not match \\D+, case-insensitivity '
            'must not touch the regex escape');
  });
}
