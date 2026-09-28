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
      cleartext.listen((socket) => socket.destroy());
      addTearDown(cleartext.close);

      await expectLater(
          factory.connect('127.0.0.1', '${cleartext.port}',
              timeout: Duration(seconds: 5)),
          throwsA(isA<SecondaryConnectException>()),
          reason:
              'HandshakeException is not a SocketException; before 4.0.0 it '
              'escaped createOutBoundConnection raw');
    });
  });
}
