import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;
import 'package:at_client_cli/src/commands/auth_cli_args.dart';
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

/// Catalogue: features/enrollment/approver_sees_expiry.feature and
/// docs/projects/pq/acceptance.md UC-G3.25.
void main() {
  setUpAll(() {
    registerFallbackValue(_FakeListParams());
    registerFallbackValue(AtKey());
  });

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

  test('a malformed --arx still fails as before, not a silent match', () async {
    final client = _MockAtClient();
    final service = _MockEnrollmentService();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.enrollmentService).thenReturn(service);
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => []);
    final args = AuthCliArgs()
        .createListCommandParser()
        .parse(['-a', '@alice', '-A', '[abc']);

    await expectLater(
        IOOverrides.runZoned(() => auth_cli.list(args, client),
            stdout: () => _CapturedStdout()),
        throwsFormatException,
        reason: 'caseSensitive: false must not swallow the unterminated '
            'character class in --arx');
  });

  test('a malformed --drx still fails as before, not a silent match', () async {
    final client = _MockAtClient();
    final service = _MockEnrollmentService();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.enrollmentService).thenReturn(service);
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => []);
    final args = AuthCliArgs()
        .createListCommandParser()
        .parse(['-a', '@alice', '-D', '[abc']);

    await expectLater(
        IOOverrides.runZoned(() => auth_cli.list(args, client),
            stdout: () => _CapturedStdout()),
        throwsFormatException,
        reason: 'caseSensitive: false must not swallow the unterminated '
            'character class in --drx');
  });

  test(
      'at_activate list shows whether each approved enrollment is anchored, '
      'naming a key that fails', () async {
    const anchoredId = 'a0a0a0a0-1a2e-43e4-93bd-378f1d366ea7';
    const unsignedId = 'c0c0c0c0-1a2e-43e4-93bd-378f1d366ea7';
    const brokenId = 'd0d0d0d0-1a2e-43e4-93bd-378f1d366ea7';
    const pendingId = 'e0e0e0e0-1a2e-43e4-93bd-378f1d366ea7';
    final client = _MockAtClient();
    final service = _MockEnrollmentService();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.enrollmentService).thenReturn(service);
    Enrollment record(String id, String status) => Enrollment.fromJSON({
          'appName': 'wavi',
          'deviceName': 'phone',
          'namespace': {'wavi': 'rw'},
          'status': status,
        })
          ..enrollmentId = id;
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [
              record(anchoredId, 'approved'),
              record(unsignedId, 'approved'),
              record(brokenId, 'approved'),
              record(pendingId, 'pending'),
            ]);
    final asked = <String>[];
    Future<ChainResult> anchoring(String id) async {
      asked.add(id);
      return switch (id) {
        anchoredId => ChainResult(ChainVerdict.anchored, [id], null),
        unsignedId => ChainResult(ChainVerdict.unsigned, [id], null),
        _ => ChainResult(ChainVerdict.broken, [id], 'a forged link',
            kid: 'deadbeefdeadbeef'),
      };
    }

    final args =
        AuthCliArgs().createListCommandParser().parse(['-a', '@alice']);
    final out = _CapturedStdout();

    await IOOverrides.runZoned(
        () => auth_cli.list(args, client, anchoring: anchoring),
        stdout: () => out);

    String row(String id) =>
        out.text.split('\n').singleWhere((line) => line.startsWith(id));
    expect(row('Enrollment ID'), contains('Anchored'));
    expect(row(anchoredId), contains(' anchored '));
    expect(row(unsignedId), contains(' unsigned '));
    expect(row(brokenId), contains(' broken deadbeefdeadbeef '),
        reason: 'a failing key is named, so the approver knows which key to '
            'look at');
    expect(asked, isNot(contains(pendingId)),
        reason: 'a pending enrollment publishes no keys to walk');
    expect(row(pendingId), isNot(matches(RegExp(r' (anchored|unsigned) '))));
  });

  test(
      'at_activate list shows `?` for an enrollment whose anchoring cannot be '
      'read, and goes on to list the rest', () async {
    const unreadableId = 'a1a1a1a1-1a2e-43e4-93bd-378f1d366ea7';
    const anchoredId = 'b1b1b1b1-1a2e-43e4-93bd-378f1d366ea7';
    final client = _MockAtClient();
    final service = _MockEnrollmentService();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.enrollmentService).thenReturn(service);
    Enrollment record(String id) => Enrollment.fromJSON({
          'appName': 'wavi',
          'deviceName': 'phone',
          'namespace': {'wavi': 'rw'},
          'status': 'approved',
        })
          ..enrollmentId = id;
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [record(unreadableId), record(anchoredId)]);
    Future<ChainResult> anchoring(String id) async => id == unreadableId
        ? throw AtClientException.message('the record cannot be read')
        : ChainResult(ChainVerdict.anchored, [id], null);

    final args =
        AuthCliArgs().createListCommandParser().parse(['-a', '@alice']);
    final out = _CapturedStdout();

    await IOOverrides.runZoned(
        () => auth_cli.list(args, client, anchoring: anchoring),
        stdout: () => out);

    String row(String id) =>
        out.text.split('\n').singleWhere((line) => line.startsWith(id));
    expect(row(unreadableId), contains(' ? '));
    expect(row(anchoredId), contains(' anchored '),
        reason: 'one row that cannot be read does not cost the rest theirs');
  });

  test(
      'given no anchoring, at_activate list asks the client whether each '
      'approved enrollment is anchored', () async {
    const revokedId = 'f0f0f0f0-1a2e-43e4-93bd-378f1d366ea7';
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
                'status': 'approved',
              })
                ..enrollmentId = revokedId,
            ]);
    when(() => client.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenThrow(AtKeyNotFoundException('no _apsk'));
    when(() => client.get(
            any(that: predicate<AtKey>((k) => '$k'.contains('.r.__e'))),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((_) async => AtValue()..value = 'withdrawn');
    final args =
        AuthCliArgs().createListCommandParser().parse(['-a', '@alice']);
    final out = _CapturedStdout();

    await IOOverrides.runZoned(() => auth_cli.list(args, client),
        stdout: () => out);

    expect(out.text.split('\n').singleWhere((l) => l.startsWith(revokedId)),
        allOf(contains(' revoked '), isNot(contains('revoked ?'))),
        reason: 'an enrollment whose _apsk was moved to .r.__e reads revoked '
            'through client.enrollments.anchoring');
  });
}
