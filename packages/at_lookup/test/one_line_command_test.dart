import 'dart:async';

import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// Catalogue: features/at_lookup/one_line_command.feature
void main() {
  const host = '127.0.0.1';
  const port = 12345;

  late FakeAtServerTransportFactory transports;
  late MockSecondaryAddressFinder addressFinder;
  late int authentications;

  List<FakeAtServerTransport> sockets() => transports.created;

  setUp(() {
    transports = FakeAtServerTransportFactory();
    authentications = 0;
    addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
  });

  AtLookupMuxable build() => AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        authenticator: (_) async {
          authentications++;
          return true;
        },
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(transportFactory: transports),
      );

  /// Sends [command] and, once it has been written, answers it the way the
  /// atServer would.
  Future<String?> answered(AtLookupMuxable atLookup, String command,
      {bool auth = false}) async {
    final response = atLookup.executeCommand(command, auth: auth);
    for (var i = 0;
        i < 100 &&
            (sockets().isEmpty || !sockets().last.written.contains(command));
        i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    await sockets().last.serverSends('data:ok\n@alice@');
    return response;
  }

  /// What [future] throws, or null when it completes.
  Future<Object?> errorOf(Future<void> future) async {
    try {
      await future;
      return null;
    } catch (e) {
      return e;
    }
  }

  /// What [command] on [atLookup] throws, or a [TimeoutException] when it
  /// waits for an answer that nothing sends.
  Future<Object?> thrownBy(AtLookupMuxable atLookup, String command,
          {bool auth = false}) =>
      errorOf(atLookup
          .executeCommand(command, auth: auth)
          .timeout(const Duration(seconds: 5)));

  /// Matches a refusal naming the line feed at [offset] of [command], and no
  /// part of [command].
  Matcher refusalOf(String command, int offset) => allOf([
        contains('offset $offset of ${command.length}'),
        for (final piece in command.split('\n'))
          if (piece.isNotEmpty) isNot(contains(piece)),
      ]);

  test(
      'A command holding a line feed before its end is refused, and none of '
      'it is sent', () async {
    final atLookup = build();
    expect(await answered(atLookup, 'noop:0\n'), 'data:ok');
    final socket = sockets().single;
    final written = List.of(socket.written);
    final flushes = socket.flushCount;

    const refused = [
      ('lookup:phone@bob\n\n', 16),
      ('\nlookup:phone@bob\n', 0),
      ('lookup:ph\none@bob\n', 9),
      ('lookup:phone@bob\nnoop:0', 16),
    ];
    for (final (command, offset) in refused) {
      expect(
          await thrownBy(atLookup, command),
          isA<IllegalArgumentException>()
              .having((e) => e.message, 'message', refusalOf(command, offset)),
          reason: 'a command holding a line feed at offset $offset of '
              '${command.length} is refused, naming no part of the command');
    }
    expect(atLookup.connection!.isInValid(), isFalse,
        reason: 'a refused command leaves the connection usable');
    for (final (command, offset) in refused) {
      expect(
          await errorOf(atLookup.connection!.write(command)),
          isA<IllegalArgumentException>()
              .having((e) => e.message, 'message', refusalOf(command, offset)),
          reason: 'the connection refuses it when written to directly');
      expect(atLookup.connection!.isInValid(), isFalse,
          reason: 'a write the connection refuses leaves it usable');
    }
    expect(
        await errorOf((atLookup as AtCommandExecutor)
            .sendSync('lookup:ph\none@bob\n')
            .timeout(const Duration(seconds: 5))),
        isA<IllegalArgumentException>(),
        reason: 'sendSync refuses it at the write');

    expect(socket.written, written,
        reason: 'nothing reaches the atServer before the refusal');
    expect(socket.flushCount, flushes,
        reason: 'nothing is flushed before the refusal');

    expect(await answered(atLookup, 'lookup:phone@bob\n'), 'data:ok',
        reason: 'the next one-line command is answered');
    expect(sockets(), hasLength(1),
        reason: 'the next command runs on the same connection');
    expect(socket.written, [...written, 'lookup:phone@bob\n'],
        reason: 'the next one-line command is sent as given');
    await atLookup.stop();
  });

  test('A lookup refuses such a command before it connects or authenticates',
      () async {
    final atLookup = build();
    addTearDown(atLookup.stop);
    const command = 'lookup:ph\none@bob\n';
    final update = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'note'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()..isPublic = true))
      ..value = 'line one\nline two';

    expect(
        await thrownBy(atLookup, command, auth: true),
        isA<IllegalArgumentException>()
            .having((e) => e.message, 'message', refusalOf(command, 9)),
        reason: 'executeCommand throws IllegalArgumentException, naming no '
            'part of the command');
    expect(
        await errorOf(
            atLookup.executeVerb(update).timeout(const Duration(seconds: 5))),
        isA<AtLookUpException>()
            .having((e) => e.errorCode, 'errorCode', 'AT0022')
            .having((e) => e.errorMessage, 'errorMessage',
                allOf(isNot(contains('line one')), isNot(contains('note')))),
        reason: 'executeVerb reports the refusal as AT0022, naming no part of '
            'the command');
    expect(sockets(), isEmpty, reason: 'no connection is opened');
    expect(authentications, 0, reason: 'nothing authenticates');
    verifyNever(() => addressFinder.findSecondary(any()));

    expect(await answered(atLookup, 'scan\n', auth: true), 'data:ok',
        reason: 'the control: a one-line command needing authentication is '
            'answered');
    expect(sockets(), hasLength(1),
        reason: 'the control opens a connection, so the count can move');
    expect(authentications, 1,
        reason: 'the control authenticates, so the count can move');
    expect(sockets().single.written, ['scan\n'],
        reason: 'the control is the only command sent');
  });

  test('A one-line command is sent as given', () async {
    final socket = FakeAtServerTransport();
    final connection = OutboundConnectionImpl(socket);

    expect(await errorOf(connection.write('lookup:phone@bob\n')), isNull,
        reason: 'a command whose only line feed is its last character is '
            'written');
    expect(await errorOf(connection.write('noop:0')), isNull,
        reason: 'a command with no line feed is written');

    expect(socket.written, ['lookup:phone@bob\n', 'noop:0']);
  });

  test('A carriage return is sent as given', () async {
    final socket = FakeAtServerTransport();
    final connection = OutboundConnectionImpl(socket);

    expect(await errorOf(connection.write('update:public:note@alice a\rb\r\n')),
        isNull,
        reason: 'a carriage return is written as given, since only a line '
            'feed ends a command');

    expect(socket.written, ['update:public:note@alice a\rb\r\n']);
  });
}
