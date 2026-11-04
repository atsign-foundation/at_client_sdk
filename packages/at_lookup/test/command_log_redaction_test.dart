import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

class _RecordedLogs implements LoggingHandler {
  final List<String> messages = [];

  @override
  void call(dynamic record) => messages.add('${record.message}');

  /// Each `SENDING:` line, without the line break a command ends in.
  Iterable<String> get sent => messages
      .where((m) => m.startsWith('SENDING: '))
      .map((m) => m.trimRight());
}

/// An atServer that answers every command at once.
class _AnsweringServer implements AtTransportFactory {
  @override
  Future<AtTransport> connect(String host, String port,
          {Duration? timeout}) async =>
      _AnsweringTransport(description: '$host:$port');
}

class _AnsweringTransport extends FakeAtServerTransport {
  _AnsweringTransport({required super.description});

  @override
  void add(List<int> bytes) {
    super.add(bytes);
    unawaited(serverSends('data:ok\n@alice@'));
  }
}

/// Catalogue: features/at_lookup/command_log_redaction.feature
void main() {
  const host = '127.0.0.1';
  const port = 12345;
  const passcode = 'SPP4Z9QK';
  const otp = 'OTP7Q2X';

  late _RecordedLogs recorded;
  late MockSecondaryAddressFinder addressFinder;

  setUp(() {
    recorded = _RecordedLogs();
    final level = AtSignLogger.root_level;
    final handler = AtSignLogger.defaultLoggingHandler;
    AtSignLogger.root_level = 'finest';
    AtSignLogger.defaultLoggingHandler = recorded;
    addTearDown(() {
      AtSignLogger.root_level = level;
      AtSignLogger.defaultLoggingHandler = handler;
    });
    addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
  });

  AtLookupMuxable build({AtAuthenticator? authenticator}) {
    final atLookup = AtLookUp.withSecureSocket(
      atSign: '@alice',
      rootDomain: const AtRootDomain(host, 64),
      authenticator: authenticator ?? (_) async => true,
      secondaryAddressFinder: addressFinder,
      transport: AtLookupTransport(transportFactory: _AnsweringServer()),
    );
    addTearDown(atLookup.stop);
    return atLookup;
  }

  Iterable<String> holding(String value) =>
      recorded.messages.where((m) => m.contains(value));

  test('An otp:put command is logged without its passcode', () async {
    await build().executeCommand('otp:put:$passcode:ttl:600000\n');

    expect(recorded.sent, contains(startsWith('SENDING: otp:put:')),
        reason: 'the control: the command was logged');
    expect(holding(passcode), isEmpty,
        reason: 'no log line holds the passcode');
    expect(recorded.sent, contains('SENDING: otp:put:***:ttl:600000'));
  });

  test('An enroll command is logged without its one-time code', () async {
    await build().executeCommand('enroll:request:{"appName":"app",'
        '"deviceName":"phone","otp":"$otp","apkamPublicKey":"pk"}\n');

    expect(recorded.sent, contains(startsWith('SENDING: enroll:request:')),
        reason: 'the control: the command was logged');
    expect(holding(otp), isEmpty, reason: 'no log line holds the otp');
    expect(
        recorded.sent,
        contains('SENDING: enroll:request:{"appName":"app",'
            '"deviceName":"phone","otp":"***","apkamPublicKey":"pk"}'));
  });

  test(
      'An enroll command an authenticator sends is logged without its '
      'one-time code', () async {
    final atLookup = build(authenticator: (executor) async {
      await executor.sendSync('enroll:request:{"otp":"$otp"}\n');
      return true;
    });

    await atLookup.executeCommand('noop:0\n', auth: true);

    expect(recorded.sent, contains(startsWith('SENDING: enroll:request:')),
        reason: 'the control: the authenticator\'s command was logged');
    expect(holding(otp), isEmpty, reason: 'no log line holds the otp');
  });

  test('Any other command is logged as it is sent', () async {
    await build().executeCommand('lookup:phone@bob\n');

    expect(recorded.sent, contains('SENDING: lookup:phone@bob'));
  });
}
