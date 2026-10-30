import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_lookup/src/io/tls_connect.dart';
import 'package:at_lookup/src/web/web_socket_transport.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import 'fake_at_server_transport.dart';

/// Catalogue: features/at_lookup/transports.feature
void main() {
  const rootDomain = AtRootDomain('127.0.0.1', 64);

  /// Authenticates as enrollment `e-1`: the `from:` and `pkam:` a client
  /// sends, against an atServer that accepts any signature.
  Future<bool> authenticate(AtCommandExecutor executor) async {
    await executor.sendSync('from:@alice\n');
    return await executor.sendSync('pkam:enrollmentId:e-1:c2lnbmF0dXJl\n') ==
        'data:success';
  }

  group('over a local atServer', () {
    late Directory certs;
    late SecurityContext clientContext;
    late SecureServerSocket tlsServer;
    late HttpServer wsServer;
    final held = <Object>[];
    final received = <String, List<String>>{'tls': [], 'ws': []};

    String answer(String command) {
      if (command.startsWith('from:')) {
        return 'data:_3c5b4f0e-4b0e-4d5e-9a3c-0f1e2d3c4b5a@alice'
            ':7d6c5b4a-3e2d-4c1b-8a09-f8e7d6c5b4a3';
      }
      if (command.startsWith('pkam:')) return 'data:success';
      if (command == 'llookup:phone@alice') return 'data:+44 1234';
      return 'error:AT0011-Internal server exception';
    }

    setUpAll(() async {
      certs = Directory.systemTemp.createTempSync('transports_test_');
      final made = await Process.run('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
        '-subj', '/CN=127.0.0.1',
        '-addext', 'subjectAltName=IP:127.0.0.1',
        // NOTE: macOS verifies through the system, which refuses a
        // self-signed certificate that names no server use.
        '-addext', 'extendedKeyUsage=serverAuth',
        '-addext', 'keyUsage=digitalSignature,keyEncipherment,keyCertSign',
        '-keyout', '${certs.path}/key.pem',
        '-out', '${certs.path}/cert.pem',
      ]);
      expect(made.exitCode, 0,
          reason: 'openssl made no test certificate: ${made.stderr}');
      clientContext = SecurityContext()
        ..setTrustedCertificates('${certs.path}/cert.pem');

      tlsServer = await SecureServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
          SecurityContext()
            ..useCertificateChain('${certs.path}/cert.pem')
            ..usePrivateKey('${certs.path}/key.pem'));
      tlsServer.listen((socket) {
        held.add(socket);
        utf8.decoder
            .bind(socket)
            .transform(const LineSplitter())
            .listen((command) {
          received['tls']!.add(command);
          socket.write('${answer(command)}\n@alice@');
        });
      });

      wsServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      wsServer.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        held.add(socket);
        socket.listen((message) {
          final command = (message is String
                  ? message
                  : utf8.decode(message as List<int>))
              .trim();
          received['ws']!.add(command);
          socket.add('${answer(command)}\n@alice@');
        });
      });
    });

    tearDownAll(() async {
      for (final socket in held) {
        if (socket is Socket) socket.destroy();
        if (socket is WebSocket) await socket.close();
      }
      await tlsServer.close();
      await wsServer.close(force: true);
      certs.deleteSync(recursive: true);
    });

    AtLookupMuxable lookUpOver(AtTransportFactory factory, int port) =>
        AtLookUp.withTransport(
            atSign: '@alice',
            rootDomain: rootDomain,
            authenticator: authenticate,
            transport: AtLookupTransport(transportFactory: factory),
            secondaryAddressFinder: FixedSecondaryAddressFinder(
                InternetAddress.loopbackIPv4.address, port));

    test('A lookup runs the same over either transport', () async {
      final overTls =
          lookUpOver(_TlsTransportFactory(clientContext), tlsServer.port);
      final overWebSocket = lookUpOver(_IoWebSocketFactory(), wsServer.port);
      addTearDown(() async {
        await overTls.stop();
        await overWebSocket.stop();
      });

      final tlsAnswer =
          await overTls.executeCommand('llookup:phone@alice\n', auth: true);
      final webSocketAnswer = await overWebSocket
          .executeCommand('llookup:phone@alice\n', auth: true);

      expect(tlsAnswer, 'data:+44 1234');
      expect(webSocketAnswer, tlsAnswer,
          reason: 'the same command gets the same answer');
      expect(received['ws'], received['tls'],
          reason: 'the same commands reached the atServer, in order');
      expect(received['tls'], [
        'from:@alice',
        'pkam:enrollmentId:e-1:c2lnbmF0dXJl',
        'llookup:phone@alice'
      ]);
      for (final lookUp in [overTls, overWebSocket]) {
        expect(lookUp.connection!.getMetaData()!.authenticatedAsEnrollmentId,
            'e-1',
            reason: 'each connection authenticated as the same enrollment');
      }
    });
  });

  test('A lookup authenticates only with its authenticator', () async {
    final transports = FakeAtServerTransportFactory();
    AtLookupMuxable lookUpWith(AtAuthenticator? authenticator) =>
        AtLookUp.withTransport(
            atSign: '@alice',
            rootDomain: rootDomain,
            authenticator: authenticator,
            transport: AtLookupTransport(transportFactory: transports),
            secondaryAddressFinder: FixedSecondaryAddressFinder('h', 1));

    await expectLater(
        lookUpWith(null).executeCommand('llookup:phone@alice\n', auth: true),
        throwsA(isA<UnAuthenticatedException>()));
    expect(transports.created.expand((t) => t.written), isEmpty,
        reason: 'the command is never sent');

    final control = lookUpWith((_) async => true);
    final answered = control.executeCommand('llookup:phone@alice\n', auth: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await transports.last.settle();
    expect(transports.last.written, ['llookup:phone@alice\n'],
        reason: 'the control: with an authenticator the command is sent');
    await transports.last.serverSends('data:+44 1234\n@alice@');
    expect(await answered, 'data:+44 1234');
    await control.stop();
  });

  test('A WebSocket holding too much unread closes', () async {
    final warnings = _Warnings();
    final ports = <_FakeWebSocketPort>[];
    final lookUp = AtLookUp.withTransport(
        atSign: '@alice',
        rootDomain: rootDomain,
        authenticator: null,
        transport: AtLookupTransport(
            transportFactory: _FakeWebSocketFactory(ports,
                (port) => WebSocketTransport(port, 'ws://fake',
                    maxInboundBytes: 64,
                    logger: AtSignLogger('WebSocketTransport',
                        loggingHandler: warnings)))),
        secondaryAddressFinder: FixedSecondaryAddressFinder('h', 1));
    addTearDown(lookUp.stop);

    final first = lookUp.executeCommand('noop:0\n');
    await pumpEventQueue();
    ports.single.receive('data:ok\n@');
    expect(await first, 'data:ok');
    final notifications = lookUp.notifications.listen((_) {})..pause();
    addTearDown(notifications.cancel);

    for (var i = 0; i < 4; i++) {
      ports.single.receive('notification: {"id":"n$i","value":"${'x' * 20}"}\n');
    }
    await pumpEventQueue();

    expect(ports.single.closeCalls, 1,
        reason: 'the caller is not reading, so what arrives is held, and '
            'past the bound the connection closes');
    expect(warnings.messages, [contains('64-byte bound')]);

    final next = lookUp.executeCommand('noop:1\n');
    await pumpEventQueue();
    expect(ports, hasLength(2), reason: 'the next command reconnects');
    ports.last.receive('data:ok\n@');
    expect(await next, 'data:ok');
  });
}

class _TlsTransportFactory implements AtTransportFactory {
  final SecurityContext context;

  _TlsTransportFactory(this.context);

  @override
  Future<AtTransport> connect(String host, String port,
          {Duration? timeout}) async =>
      SecureSocketTransport(await connectTls(host, int.parse(port),
          context: context, timeout: timeout ?? const Duration(seconds: 10)));
}

/// The WebSocket transport over `dart:io`'s WebSocket, which stands in for a
/// browser's.
class _IoWebSocketFactory implements AtTransportFactory {
  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final url = 'ws://$host:$port/ws';
    return WebSocketTransport(
        _IoWebSocketPort(await WebSocket.connect(url)), url);
  }
}

class _IoWebSocketPort implements WebSocketPort {
  final WebSocket _socket;
  final _closed = StreamController<void>.broadcast();

  _IoWebSocketPort(this._socket) {
    _socket.done.whenComplete(() => _closed.add(null));
  }

  @override
  bool get isOpen => _socket.readyState == WebSocket.open;

  @override
  int get bufferedAmount => 0;

  @override
  void send(Uint8List bytes) => _socket.add(bytes);

  @override
  Stream<Object?> get onMessage => _socket.map((message) =>
      message is List<int> ? Uint8List.fromList(message).buffer : message);

  @override
  Stream<void> get onClose => _closed.stream;

  @override
  void close() => _socket.close();
}

class _FakeWebSocketFactory implements AtTransportFactory {
  final List<_FakeWebSocketPort> ports;
  final WebSocketTransport Function(_FakeWebSocketPort port) transportOver;

  _FakeWebSocketFactory(this.ports, this.transportOver);

  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final fake = _FakeWebSocketPort();
    ports.add(fake);
    return transportOver(fake);
  }
}

class _FakeWebSocketPort implements WebSocketPort {
  final _messages = StreamController<Object?>(sync: true);
  final _closes = StreamController<void>.broadcast(sync: true);
  int closeCalls = 0;

  @override
  bool isOpen = true;

  @override
  int get bufferedAmount => 0;

  @override
  Stream<Object?> get onMessage => _messages.stream;

  @override
  Stream<void> get onClose => _closes.stream;

  @override
  void send(Uint8List bytes) {}

  @override
  void close() {
    closeCalls++;
    isOpen = false;
  }

  void receive(String data) => _messages.add(data);
}

class _Warnings implements LoggingHandler {
  final messages = <String>[];

  @override
  void call(record) {
    if (record.level.name == 'WARNING') messages.add(record.message);
  }
}
