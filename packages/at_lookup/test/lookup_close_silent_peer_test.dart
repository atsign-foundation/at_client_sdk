import 'dart:async';
import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';

class _RecordedLogs implements LoggingHandler {
  final List<({String level, String message})> records = [];

  @override
  void call(dynamic record) => records
      .add((level: '${record.level.name}', message: '${record.message}'));

  Iterable<String> at(String level) =>
      records.where((r) => r.level == level).map((r) => r.message);
}

/// A server that accepts connections and never answers, not even the TLS
/// handshake, and records when each connection it accepted ends.
class _SilentServer {
  _SilentServer._(this._server) {
    _server.listen((socket) {
      final ended = Completer<void>();
      socket.listen((_) {},
          onDone: ended.complete, onError: (_) => ended.complete());
      connections.add((socket: socket, ended: ended.future));
    });
  }

  static Future<_SilentServer> bind() async =>
      _SilentServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  final List<({Socket socket, Future<void> ended})> connections = [];

  int get port => _server.port;

  Future<void> close() async {
    for (final connection in connections) {
      connection.socket.destroy();
    }
    await _server.close();
  }
}

/// `close()` ends a lookup whose connect is waiting on a peer that never
/// answers, over the real TLS transport: the call in flight fails at once and
/// the socket it was opening closes.
void main() {
  final recorded = _RecordedLogs();
  late _SilentServer silent;

  setUpAll(() {
    AtSignLogger.defaultLoggingHandler = recorded;
    registerFallbackValue(SecureSocketConfig());
  });

  setUp(() async {
    recorded.records.clear();
    silent = await _SilentServer.bind();
  });

  tearDown(() => silent.close());

  AtLookupMuxable build(SecondaryAddressFinder finder) =>
      AtLookUp.withSecureSocket(
        atSign: '@alice',
        rootDomain: AtRootDomain('127.0.0.1', silent.port),
        authenticator: (_) async => true,
        secondaryAddressFinder: finder,
        transport: secureSocketTransport(SecureSocketConfig()),
      );

  /// Starts a request on [atLookup], waits for [silent] to accept its
  /// connection, closes the lookup, and returns what the request threw.
  Future<Object?> closeWhileConnecting(AtLookupMuxable atLookup) async {
    Object? thrown;
    final pending = atLookup
        .executeCommand('noop:0\n')
        .then<void>((_) {}, onError: (Object e) => thrown = e);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (silent.connections.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(silent.connections, hasLength(1),
        reason: 'the connect must be waiting on the silent peer');

    await atLookup.close().timeout(const Duration(seconds: 2),
        onTimeout: () => fail('close() waited for the connect'));
    await pending.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the request waited for its connect'));
    return thrown;
  }

  test('an atServer that never answers the handshake', () async {
    final finder = MockSecondaryAddressFinder();
    when(() => finder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress('127.0.0.1', silent.port));

    final thrown = await closeWhileConnecting(build(finder));

    expect(thrown, isA<StoppedException>());
    await silent.connections.single.ended.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the socket still being opened was left open, '
            'and an open socket keeps the process alive'));
    expect(recorded.at('SEVERE'), isEmpty);
  });

  test('an atDirectory that never answers the handshake', () async {
    final finder = CacheableSecondaryAddressFinder('127.0.0.1', silent.port);

    final thrown = await closeWhileConnecting(build(finder));

    expect(thrown, isA<StoppedException>());
    await silent.connections.single.ended.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the atDirectory lookup\'s socket was left '
            'open, though the finder is not the lookup\'s own'));
    await Future.delayed(const Duration(milliseconds: 500));
    expect(silent.connections, hasLength(1),
        reason: 'an abandoned atDirectory lookup is not retried');
    expect(recorded.at('SEVERE'), isEmpty,
        reason: 'a close the owner asked for is not an atDirectory failure');
  });

  test('an atDirectory that completes the handshake and then says nothing',
      () async {
    final certs = Directory.systemTemp.createTempSync('silent_directory_');
    addTearDown(() => certs.deleteSync(recursive: true));
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
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final directory = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain('${certs.path}/cert.pem')
          ..usePrivateKey('${certs.path}/key.pem'));
    final ended = <Future<void>>[];
    directory.listen((socket) {
      final done = Completer<void>();
      socket.listen((_) {},
          onDone: done.complete, onError: (_) => done.complete());
      ended.add(done.future);
    });
    addTearDown(directory.close);
    final atLookup = build(CacheableSecondaryAddressFinder(
        '127.0.0.1', directory.port,
        socketConfig: SecureSocketConfig()
          ..pathToCerts = '${certs.path}/cert.pem'));

    Object? thrown;
    final pending = atLookup
        .executeCommand('noop:0\n')
        .then<void>((_) {}, onError: (Object e) => thrown = e);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (ended.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(ended, hasLength(1), reason: 'the handshake must have completed');
    await Future.delayed(const Duration(milliseconds: 200));

    await atLookup.close().timeout(const Duration(seconds: 2),
        onTimeout: () => fail('close() waited for the atDirectory'));
    await pending.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the request waited for the atDirectory'));

    expect(thrown, isA<StoppedException>());
    await ended.single.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('the atDirectory connection was left open, '
            'polling for an answer that is not coming'));
    expect(recorded.at('SEVERE'), isEmpty);
  });
}
