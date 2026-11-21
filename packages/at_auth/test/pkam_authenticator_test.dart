import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookup extends Mock implements AtLookUp {}

/// Every record logged through it, kept with its error and stack trace.
class _KeptLogs implements LoggingHandler {
  final List<dynamic> records = [];

  @override
  void call(dynamic record) => records.add(record);
}

void main() {
  final logs = _KeptLogs();

  setUpAll(() {
    // NOTE: before PkamAuthenticator first logs; its logger binds the handler
    // and the level it finds.
    AtSignLogger.defaultLoggingHandler = logs;
    AtSignLogger.root_level = 'finest';
  });

  // NOTE: each test sees only what it logged.
  setUp(logs.records.clear);

  group('PkamAuthenticator tests', () {
    late PkamAuthenticator pkamAuthenticator;
    late MockAtLookup mockAtLookup;
    final String atSign = '@alice';

    setUp(() {
      mockAtLookup = MockAtLookup();
      pkamAuthenticator = PkamAuthenticator();
    });

    test('authenticate() should return a successful AtAuthResponse', () async {
      when(() => mockAtLookup.pkamAuthenticate()).thenAnswer((_) async => true);

      final result = await pkamAuthenticator.authenticate(atSign, mockAtLookup);

      expect(result, isTrue);
    });

    test('authenticate() should throw UnAuthenticatedException on failure',
        () async {
      when(() => mockAtLookup.pkamAuthenticate())
          .thenThrow(UnAuthenticatedException('Unauthenticated'));

      expect(
          () async => await pkamAuthenticator.authenticate(atSign, mockAtLookup),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test(
        'a failed exchange throws a message holding no stack trace, and logs '
        'the trace at fine', () async {
      when(() => mockAtLookup.pkamAuthenticate())
          .thenThrow(UnAuthenticatedException('the atServer said no'));

      await expectLater(
          pkamAuthenticator.authenticate(atSign, mockAtLookup),
          throwsA(isA<UnAuthenticatedException>().having(
              (e) => e.message,
              'message',
              allOf(
                  contains('pkam auth failed for $atSign'),
                  contains('the atServer said no'),
                  isNot(contains('\n')),
                  isNot(contains('#0'))))));
      final fine = logs.records.where((r) =>
          '${r.level.name}' == 'FINE' &&
          '${r.message}'.contains('pkam auth failed for $atSign') &&
          '${r.error}'.contains('the atServer said no'));
      expect(fine, isNotEmpty, reason: 'the failure is logged at fine');
      expect(fine.first.stackTrace, isNotNull, reason: 'with its trace');
    });
  });

  group('Given a lookup its owner has stopped', () {
    test(
        'when PkamAuthenticator authenticates on it, then the '
        'StoppedException passes through as thrown', () async {
      final lookUp = MockAtLookup();
      final stopped =
          StoppedException('the lookup for @alice has been stopped');
      when(() => lookUp.pkamAuthenticate()).thenThrow(stopped);

      await expectLater(PkamAuthenticator().authenticate('@alice', lookUp),
          throwsA(same(stopped)));
    });
  });

  group('Given a lookup whose PKAM times out', () {
    test(
        'when PkamAuthenticator authenticates on it, then it throws an '
        'UnAuthenticatedException naming the atSign', () async {
      final lookUp = MockAtLookup();
      when(() => lookUp.pkamAuthenticate())
          .thenThrow(AtTimeoutException('Waited for 10 millis. No response'));

      await expectLater(
          PkamAuthenticator().authenticate('@alice', lookUp),
          throwsA(isA<UnAuthenticatedException>()
              .having((e) => e.message, 'message', contains('@alice'))));
    });
  });
}
