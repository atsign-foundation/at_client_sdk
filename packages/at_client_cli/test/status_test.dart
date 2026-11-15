import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart' show AtActivate;
import 'package:mocktail/mocktail.dart' show Fake;
import 'package:test/test.dart';

import 'lifecycle_rig.dart' show refusedPort;

/// The public key the atServer holds for @alice, when it holds one.
const _alicePublicKey = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAalice';

/// at_activate status's exit code, and its connection to the atServer,
/// observed against an atDirectory and an atServer on the loopback interface.
///
/// Catalogue: features/at_client_cli/status.feature
void main() {
  late Directory certs;
  late SecurityContext serving;
  final atServers = <_AtServer>[];
  final atDirectories = <_AtDirectory>[];

  setUpAll(() async {
    certs = Directory.systemTemp.createTempSync('status_test_');
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
    // NOTE: the atDirectory and the atServer are both reached through
    // SecurityContext.defaultContext, which is this test file's isolate's own.
    SecurityContext.defaultContext
        .setTrustedCertificates('${certs.path}/cert.pem');
    serving = SecurityContext()
      ..useCertificateChain('${certs.path}/cert.pem')
      ..usePrivateKey('${certs.path}/key.pem');
  });

  tearDown(() async {
    for (final server in atServers) {
      await server.close();
    }
    for (final directory in atDirectories) {
      await directory.close();
    }
    atServers.clear();
    atDirectories.clear();
  });

  tearDownAll(() => certs.deleteSync(recursive: true));

  Future<_AtServer> atServer({String? publicKey}) async {
    final server = await _AtServer.bind(serving, publicKey: publicKey);
    atServers.add(server);
    return server;
  }

  Future<_AtDirectory> atDirectory(String answer) async {
    final directory = await _AtDirectory.bind(serving, answer);
    atDirectories.add(directory);
    return directory;
  }

  test('at_activate status returns 0 when found', () async {
    final server = await atServer(publicKey: _alicePublicKey);
    final root = await atDirectory('127.0.0.1:${server.port}');

    final run = await _status(root.port);

    expect(server.received, contains('lookup:publickey@alice'),
        reason: 'the premise: the atServer the atDirectory names is asked for '
            'the key; status wrote: ${run.stderr}');
    expect(run.code, 0,
        reason: 'the atServer holds @alice\'s public key; status wrote: '
            '${run.stderr}');
  });

  test('at_activate status returns 1 when absent', () async {
    final server = await atServer();
    final root = await atDirectory('127.0.0.1:${server.port}');

    final run = await _status(root.port);

    expect(server.received, contains('lookup:publickey@alice'),
        reason: 'the premise: the atServer the atDirectory names is asked for '
            'the key; status wrote: ${run.stderr}');
    expect(run.code, 1,
        reason: 'the atServer holds no public key for @alice; status wrote: '
            '${run.stderr}');
  });

  test('at_activate status returns 2 when atServer unreachable', () async {
    final root = await atDirectory('127.0.0.1:${await refusedPort()}');

    final run = await _status(root.port);

    expect(root.asked, contains('alice'),
        reason: 'the premise: the atDirectory is asked for @alice; status '
            'wrote: ${run.stderr}');
    expect(run.code, 2,
        reason: 'nothing answers where the atDirectory says @alice\'s atServer '
            'is; status wrote: ${run.stderr}');
  });

  test('at_activate status returns 3 when not in the atDirectory', () async {
    final root = await atDirectory('null');

    final run = await _status(root.port);

    expect(root.asked, contains('alice'),
        reason: 'the premise: the atDirectory is asked for @alice; status '
            'wrote: ${run.stderr}');
    expect(run.code, 3,
        reason: 'the atDirectory has no record for @alice; status wrote: '
            '${run.stderr}');
  });

  test('at_activate status returns 4 when atDirectory unreachable', () async {
    final run = await _status(await refusedPort());

    expect(run.code, 4,
        reason: 'nothing answers at the root; status wrote: ${run.stderr}');
  });

  test('at_activate status closes its connection to the atServer', () async {
    final server = await atServer(publicKey: _alicePublicKey);
    final root = await atDirectory('127.0.0.1:${server.port}');

    final run = await _status(root.port);

    expect(run.code, 0,
        reason: 'the premise: the atServer holds @alice\'s public key; status '
            'wrote: ${run.stderr}');
    final connection = server.connections.single;
    expect(connection.received, ['lookup:publickey@alice'],
        reason: 'the premise: the lookup is answered on this connection');
    expect(await connection.endedWithin(const Duration(seconds: 5)), isTrue,
        reason: 'status closes its connection to the atServer once it has '
            'read the answer');
  });
}

/// at_activate status run for @alice with its root at [rootPort] on the
/// loopback interface: the code it returns and what it wrote on stderr.
Future<({int code, String stderr})> _status(int rootPort) async {
  final written = _Written();
  final code = await IOOverrides.runZoned(
      () => AtActivate.main(
          ['status', '-a', '@alice', '-r', '127.0.0.1:$rootPort']),
      stderr: () => written);
  return (code: code, stderr: written.text);
}

/// An atDirectory on the loopback interface that answers every atSign it is
/// asked for with [answer]: an atServer's `host:port`, or `null` for no
/// record.
class _AtDirectory {
  _AtDirectory._(this._server, this.answer) {
    _server.listen(_serve, onError: (_) {});
  }

  /// An atDirectory bound to a free port, serving TLS under [context].
  static Future<_AtDirectory> bind(
          SecurityContext context, String answer) async =>
      _AtDirectory._(
          await SecureServerSocket.bind(
              InternetAddress.loopbackIPv4, 0, context),
          answer);

  final SecureServerSocket _server;
  final String answer;
  final List<SecureSocket> _sockets = [];

  /// Each atSign asked for, without its `@`, in order.
  final List<String> asked = [];

  int get port => _server.port;

  void _serve(SecureSocket socket) {
    _sockets.add(socket);
    socket.done.ignore();
    socket.write('@');
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line == '@exit') {
        socket.destroy();
        return;
      }
      asked.add(line);
      socket.write('$answer\n@');
    }, onError: (_) => socket.destroy(), onDone: socket.destroy);
  }

  /// Stops listening and ends every connection still open.
  Future<void> close() async {
    await _server.close();
    for (final socket in _sockets) {
      socket.destroy();
    }
  }
}

/// An atServer on the loopback interface that answers a lookup of @alice's
/// public key with [publicKey], or as holding none when that is null.
class _AtServer {
  _AtServer._(this._server, this.publicKey) {
    _server.listen(_serve, onError: (_) {});
  }

  /// An atServer bound to a free port, serving TLS under [context].
  static Future<_AtServer> bind(SecurityContext context,
          {String? publicKey}) async =>
      _AtServer._(
          await SecureServerSocket.bind(
              InternetAddress.loopbackIPv4, 0, context),
          publicKey);

  final SecureServerSocket _server;
  final String? publicKey;

  /// Each connection accepted, in order.
  final List<_Connection> connections = [];

  int get port => _server.port;

  /// Every command received, over every connection.
  List<String> get received => [for (final c in connections) ...c.received];

  void _serve(SecureSocket socket) {
    final connection = _Connection(socket);
    connections.add(connection);
    socket.done.ignore();
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((command) {
      connection.received.add(command);
      socket.write(_answer(command));
    }, onError: (_) => connection._end(), onDone: connection._end);
  }

  String _answer(String command) {
    if (command != 'lookup:publickey@alice') {
      return 'error:AT0003-unexpected command\n@';
    }
    final key = publicKey;
    return key == null
        ? 'error:AT0015-key not found : public:publickey@alice does not '
            'exist in keystore\n@'
        : 'data:$key\n@';
  }

  /// Stops listening and ends every connection still open.
  Future<void> close() async {
    await _server.close();
    for (final connection in connections) {
      connection._socket.destroy();
    }
  }
}

/// A connection [_AtServer] accepted: the commands it received, and when the
/// client ended it.
class _Connection {
  _Connection(this._socket);

  final SecureSocket _socket;
  final List<String> received = [];
  final Completer<void> _ended = Completer();

  /// Whether the client ends this connection within [limit].
  Future<bool> endedWithin(Duration limit) =>
      _ended.future.then((_) => true).timeout(limit, onTimeout: () => false);

  void _end() {
    if (!_ended.isCompleted) _ended.complete();
    _socket.destroy();
  }
}

/// Collects what at_activate writes on stderr.
class _Written extends Fake implements Stdout {
  final List<String> _written = [];

  String get text => _written.join();

  @override
  void write(Object? object) => _written.add('$object');

  @override
  void writeln([Object? object = '']) => _written.add('$object\n');
}
