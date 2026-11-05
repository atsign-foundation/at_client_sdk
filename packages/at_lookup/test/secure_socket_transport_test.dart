/// Exercised over a plain [ServerSocket], not a [SecureServerSocket].
///
/// [SecureSocketTransport] delegates every member to [Socket], and
/// `SecureSocket extends Socket`, so a cleartext socket reaches all of it. The
/// TLS a `SecureServerSocket` would add belongs to `SecureSocketUtil`, which
/// this step does not touch — and standing one up needs a checked-in keypair
/// and mutates the process-global `SecurityContext.defaultContext`, which
/// leaks into every other suite in the isolate.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  group('SecureSocketTransport', () {
    late ServerSocket server;
    late Completer<Socket> accepted;
    late Socket socket;
    late SecureSocketTransport transport;

    setUp(() async {
      accepted = Completer<Socket>();
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(accepted.complete);
      socket = await Socket.connect(server.address, server.port);
      transport = SecureSocketTransport(socket);
    });

    tearDown(() async {
      transport.destroy();
      await server.close();
    });

    test('inbound is the socket, not a re-broadcast of it', () {
      expect(identical(transport.inbound, socket), isTrue,
          reason: 'a StreamController between the two would answer a pause out '
              'of a local buffer and the far end would keep sending');
    });

    test('add and flush put the bytes on the wire', () async {
      final peer = await accepted.future;
      final firstLine =
          utf8.decoder.bind(peer).transform(const LineSplitter()).first;

      transport.add(utf8.encode('from the client\n'));
      await transport.flush();

      expect(await firstLine, 'from the client');
    });

    test('inbound delivers what the far end sends', () async {
      final peer = await accepted.future;
      final firstLine = utf8.decoder
          .bind(transport.inbound)
          .transform(const LineSplitter())
          .first;

      peer.add(utf8.encode('from the server\n'));
      await peer.flush();

      expect(await firstLine, 'from the server');
    });

    test('destroy ends the inbound stream', () async {
      await accepted.future;
      final drained = transport.inbound.drain<void>();

      transport.destroy();

      await drained;
    });

    test('description names the far end', () {
      expect(transport.description, '${server.address.address}:${server.port}');
    });
  });

  group('SecureSocketTransport over a socket that fails', () {
    test('add reports a refused write as AtIOException', () {
      for (final refusal in [
        const SocketException('Broken pipe'),
        const HandshakeException('alert'),
        StateError('Cannot add event after closing'),
      ]) {
        final transport = SecureSocketTransport(_FailingSocket(refusal));

        expect(
            () => transport.add([0x41]),
            throwsA(isA<AtIOException>().having((e) => e.message, 'message',
                allOf(contains('127.0.0.1:64'), contains('$refusal')))),
            reason: '${refusal.runtimeType} is the socket\'s own type; the '
                'contract names AtIOException');
      }
    });

    test('flush reports a failed socket as AtIOException', () async {
      for (final failure in [
        const SocketException('Connection reset by peer'),
        const TlsException('bad record mac'),
      ]) {
        final transport = SecureSocketTransport(_FailingSocket(failure));

        await expectLater(
            transport.flush(),
            throwsA(isA<AtIOException>().having((e) => e.message, 'message',
                allOf(contains('127.0.0.1:64'), contains('$failure')))),
            reason: '${failure.runtimeType} is the socket\'s own type; the '
                'contract names AtIOException');
      }
    });
  });

  group('SecureSocketTransportFactory', () {
    final factory =
        SecureSocketTransportFactory(secureSocketConfig: SecureSocketConfig());

    test('a refused connection becomes SecondaryConnectException', () async {
      final vacated = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = vacated.port;
      await vacated.close();

      await expectLater(
          factory.connect('127.0.0.1', '$port', timeout: Duration(seconds: 5)),
          throwsA(isA<SecondaryConnectException>()));
    });

    test('a far end that is not speaking TLS becomes SecondaryConnectException',
        () async {
      final cleartext =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = <Socket>[];
      cleartext.listen((socket) async {
        accepted.add(socket);
        socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
        await socket.flush();
      });
      addTearDown(() async {
        for (final socket in accepted) {
          socket.destroy();
        }
        await cleartext.close();
      });

      await expectLater(
          factory.connect('127.0.0.1', '${cleartext.port}',
              timeout: Duration(seconds: 5)),
          throwsA(isA<SecondaryConnectException>().having(
              (e) => e.message, 'message', contains('HandshakeException'))),
          reason: 'a far end answering in cleartext fails the TLS handshake, '
              'and a HandshakeException is not a SocketException');
    });
  });
}

/// A socket whose writes fail with [failure], as a failed or closed one does.
class _FailingSocket extends Fake implements Socket {
  final Object failure;

  _FailingSocket(this.failure);

  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;

  @override
  int get remotePort => 64;

  @override
  Future<void> get done => Completer<void>().future;

  @override
  void add(List<int> data) => throw failure;

  @override
  Future<void> flush() => Future.error(failure);
}
