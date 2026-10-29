import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_socket.dart';

/// Catalogue: features/at_lookup/one_line_command.feature
void main() {
  const host = '127.0.0.1';
  const port = 12345;

  late List<FakeAtServerSocket> sockets;
  late MockSecondaryAddressFinder addressFinder;
  late MockSecureSocketFactory socketFactory;

  setUp(() {
    sockets = [];
    addressFinder = MockSecondaryAddressFinder();
    socketFactory = MockSecureSocketFactory();
    registerFallbackValue(SecureSocketConfig());
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    when(() => socketFactory.createSocket(host, '$port', any()))
        .thenAnswer((_) async {
      final socket = FakeAtServerSocket();
      sockets.add(socket);
      return socket;
    });
  });

  AtLookupMuxable build() => AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        authenticator: (_) async => true,
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(
          secureSocketConfig: SecureSocketConfig(),
          socketFactory: socketFactory,
        ),
      );

  /// Sends [command] and, once it has been written, answers it the way the
  /// atServer would.
  Future<String?> answered(AtLookupMuxable atLookup, String command) async {
    final response = atLookup.executeCommand(command);
    for (var i = 0;
        i < 100 && (sockets.isEmpty || !sockets.last.written.contains(command));
        i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    await sockets.last.serverSends('data:ok\n@alice@');
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
  Future<Object?> thrownBy(AtLookupMuxable atLookup, String command) => errorOf(
      atLookup.executeCommand(command).timeout(const Duration(seconds: 5)));

  test(
      'A command holding a line feed before its end is refused, and nothing '
      'is sent', () async {
    final atLookup = build();
    expect(await answered(atLookup, 'noop:0\n'), 'data:ok');
    final socket = sockets.single;
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
          isA<IllegalArgumentException>().having(
              (e) => e.message,
              'message',
              allOf(contains('offset $offset of ${command.length}'),
                  isNot(contains('phone')))),
          reason: 'a command holding a line feed at offset $offset of '
              '${command.length} is refused, naming no part of the command');
    }
    expect(atLookup.connection!.isInValid(), isFalse,
        reason: 'a refused command leaves the connection usable');
    for (final (command, _) in refused) {
      expect(await errorOf(atLookup.connection!.write(command)),
          isA<IllegalArgumentException>(),
          reason: 'the connection refuses it when written to directly');
    }

    expect(socket.written, written,
        reason: 'nothing reaches the atServer before the refusal');
    expect(socket.flushCount, flushes,
        reason: 'nothing is flushed before the refusal');

    expect(await answered(atLookup, 'lookup:phone@bob\n'), 'data:ok',
        reason: 'the next one-line command is answered');
    expect(sockets, hasLength(1),
        reason: 'the next command runs on the same connection');
    expect(socket.written, [...written, 'lookup:phone@bob\n'],
        reason: 'the next one-line command is sent as given');
    await atLookup.stop();
  });

  test('A one-line command is sent as given', () async {
    final socket = FakeAtServerSocket();
    final connection = OutboundConnectionImpl(socket);

    expect(await errorOf(connection.write('lookup:phone@bob\n')), isNull,
        reason: 'a command whose only line feed is its last character is '
            'written');
    expect(await errorOf(connection.write('noop:0')), isNull,
        reason: 'a command with no line feed is written');

    expect(socket.written, ['lookup:phone@bob\n', 'noop:0']);
  });

  test('A carriage return is sent as given', () async {
    final socket = FakeAtServerSocket();
    final connection = OutboundConnectionImpl(socket);

    expect(await errorOf(connection.write('update:public:note@alice a\rb\r\n')),
        isNull,
        reason: 'a carriage return is written as given, since only a line '
            'feed ends a command');

    expect(socket.written, ['update:public:note@alice a\rb\r\n']);
  });
}
