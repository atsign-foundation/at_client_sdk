import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_lookup/src/io/tls_connect.dart';
import 'package:test/test.dart';

/// [connectTls] against real sockets: a TLS server that answers, and a server
/// that accepts and never answers the handshake.
void main() {
  late Directory certs;
  late SecurityContext clientContext;
  late SecurityContext serverContext;

  setUpAll(() async {
    certs = Directory.systemTemp.createTempSync('tls_connect_test_');
    final made = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
      '-subj', '/CN=127.0.0.1',
      '-addext', 'subjectAltName=IP:127.0.0.1',
      // NOTE: macOS verifies through the system, which refuses a self-signed
      // certificate that names no server use.
      '-addext', 'extendedKeyUsage=serverAuth',
      '-addext', 'keyUsage=digitalSignature,keyEncipherment,keyCertSign',
      '-keyout', '${certs.path}/key.pem',
      '-out', '${certs.path}/cert.pem',
    ]);
    expect(made.exitCode, 0,
        reason: 'openssl made no test certificate: ${made.stderr}');
    clientContext = SecurityContext()
      ..setTrustedCertificates('${certs.path}/cert.pem');
    serverContext = SecurityContext()
      ..useCertificateChain('${certs.path}/cert.pem')
      ..usePrivateKey('${certs.path}/key.pem');
  });

  tearDownAll(() => certs.deleteSync(recursive: true));

  /// A server that accepts and never says anything, holding what it accepted.
  Future<(ServerSocket, List<Socket>)> silentServer() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final held = <Socket>[];
    server.listen(held.add);
    addTearDown(() async {
      for (final socket in held) {
        socket.destroy();
      }
      await server.close();
    });
    return (server, held);
  }

  group('against a TLS server that answers', () {
    late SecureServerSocket server;
    late StreamController<SecureSocket> accepted;

    setUp(() async {
      server = await SecureServerSocket.bind(
          InternetAddress.loopbackIPv4, 0, serverContext);
      accepted = StreamController();
      server.listen(accepted.add);
    });

    tearDown(() => server.close());

    test('carries bytes both ways, and a destroy ends both ends', () async {
      final client = await connectTls('127.0.0.1', server.port,
          context: clientContext, timeout: const Duration(seconds: 10));
      final peer = await accepted.stream.first;
      final fromPeer =
          StreamIterator(client.cast<List<int>>().transform(utf8.decoder));
      final toPeer =
          StreamIterator(peer.cast<List<int>>().transform(utf8.decoder));

      client.write('scan\n');
      await client.flush();
      expect(await toPeer.moveNext(), isTrue);
      expect(toPeer.current, 'scan\n');

      peer.write('data:[]\n@');
      await peer.flush();
      expect(await fromPeer.moveNext(), isTrue);
      expect(fromPeer.current, 'data:[]\n@');

      client.destroy();
      await client.done;
      expect(await toPeer.moveNext(), isFalse,
          reason: 'the peer sees the connection end');
      expect(await fromPeer.moveNext(), isFalse,
          reason: 'and so does the reader on this side');
    });

    test('a paused reader receives nothing until it resumes', () async {
      final client = await connectTls('127.0.0.1', server.port,
          context: clientContext, timeout: const Duration(seconds: 10));
      final peer = await accepted.stream.first;
      final received = <String>[];
      final subscription =
          client.listen((bytes) => received.add(utf8.decode(bytes)));

      subscription.pause();
      peer.write('while paused');
      await peer.flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, isEmpty);

      subscription.resume();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received.join(), 'while paused');

      client.destroy();
      peer.destroy();
    });

    test('writes larger than one socket write all arrive, in order', () async {
      final client = await connectTls('127.0.0.1', server.port,
          context: clientContext, timeout: const Duration(seconds: 10));
      final peer = await accepted.stream.first;
      final payload = List.generate(200000, (i) => 'line $i\n').join();
      final arrived = peer.cast<List<int>>().transform(utf8.decoder).join();

      client.write(payload);
      await client.flush();
      client.destroy();

      expect(await arrived, payload);
    });
  });

  group('against a server that never answers the handshake', () {
    test('the timeout ends the connect, not only the TCP part of it', () async {
      final (server, held) = await silentServer();
      final elapsed = Stopwatch()..start();

      await expectLater(
          connectTls('127.0.0.1', server.port,
              context: clientContext,
              timeout: const Duration(milliseconds: 500)),
          throwsA(isA<SocketException>()
              .having((e) => e.message, 'message', contains('timed out'))));
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 5)));
      expect(held, hasLength(1), reason: 'the TCP connect did succeed');
    });

    test('abandoning its owner ends the connect at once', () async {
      final (server, _) = await silentServer();
      final owner = Abandonment();
      final connecting = owner.run(() => connectTls('127.0.0.1', server.port,
          context: clientContext, timeout: const Duration(seconds: 30)));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final elapsed = Stopwatch()..start();

      owner.abandon();

      await expectLater(
          connecting,
          throwsA(isA<SocketException>()
              .having((e) => e.message, 'message', contains('abandoned'))));
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('a connect begun after its owner was abandoned fails at once',
        () async {
      final (server, held) = await silentServer();
      final owner = Abandonment()..abandon();

      await expectLater(
          owner.run(() => connectTls('127.0.0.1', server.port,
              context: clientContext, timeout: const Duration(seconds: 30))),
          throwsA(isA<SocketException>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(held, isEmpty, reason: 'nothing was connected');
    });
  });
}
